// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IPool} from "aave-v3/contracts/interfaces/IPool.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {IOntraHook} from "./interfaces/IOntraHook.sol";

contract OntraHook is BaseHook, IOntraHook {
    using StateLibrary for IPoolManager;
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;
    using CurrencySettler for Currency;

    IPool public immutable AAVE_POOL;

    mapping(PoolId poolId => int24 lastTick) public _lastTicks;
    mapping(bytes32 positionKey => PositionInfo) public _positions;

    /**
     * @param manager The PoolManager this hook is associated with
     * @param aavePool The Aave Pool contract address
     */
    constructor(IPoolManager manager, IPool aavePool) BaseHook(manager) {
        AAVE_POOL = aavePool;
    }

    /// @inheritdoc BaseHook
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @inheritdoc IOntraHook
    function getPositionKey(address owner, PoolId poolId, int24 tickLower, int24 tickUpper)
        public
        pure
        returns (bytes32 key_)
    {
        key_ = keccak256(abi.encode(owner, poolId, tickLower, tickUpper));
    }

    /// @inheritdoc IOntraHook
    function addLiquidity(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint128 liquidity_) {
        // Use unlock to interact with PoolManager
        bytes memory result = poolManager.unlock(
            abi.encode(
                CallbackData({
                    sender: msg.sender,
                    key: key,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: int256(uint256(type(uint128).max)),
                    amount0: amount0Desired,
                    amount1: amount1Desired,
                    isAdd: true,
                    isRebalancing: false
                })
            )
        );

        liquidity_ = abi.decode(result, (uint128));
    }

    /// @inheritdoc IOntraHook
    function removeLiquidity(PoolKey calldata key, int24 tickLower, int24 tickUpper, uint128 liquidityToRemove)
        external
        returns (uint256 amount0_, uint256 amount1_)
    {
        bytes32 positionKey = getPositionKey(msg.sender, key.toId(), tickLower, tickUpper);
        PositionInfo storage position = _positions[positionKey];

        if (position.owner == address(0)) revert OntraNoPosition();
        if (!position.isInRange) revert OntraPositionAlreadyInAave();
        if (position.liquidity < liquidityToRemove) revert OntraNotEnoughLiquidity();

        bytes memory result = poolManager.unlock(
            abi.encode(
                CallbackData({
                    sender: msg.sender,
                    key: key,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(uint256(liquidityToRemove)),
                    amount0: 0,
                    amount1: 0,
                    isAdd: false,
                    isRebalancing: false
                })
            )
        );

        (amount0_, amount1_) = abi.decode(result, (uint256, uint256));
    }

    /// @inheritdoc IOntraHook
    function removeTokensFromAave(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0ToRemove,
        uint256 amount1ToRemove
    ) external returns (uint256 amount0_, uint256 amount1_) {
        bytes32 positionKey = getPositionKey(msg.sender, key.toId(), tickLower, tickUpper);
        PositionInfo storage position = _positions[positionKey];

        if (position.owner == address(0)) revert OntraNoPosition();
        if (position.isInRange) revert OntraPositionNotInAave();
        if (position.amount0OnAave < amount0ToRemove || position.amount1OnAave < amount1ToRemove) {
            revert OntraNotEnoughOnAave();
        }

        _withdrawFromAave(key.currency0, amount0ToRemove, msg.sender);
        _withdrawFromAave(key.currency1, amount1ToRemove, msg.sender);

        position.amount0OnAave -= amount0ToRemove;
        position.amount1OnAave -= amount1ToRemove;

        // If position is fully removed, delete it
        if (position.liquidity == 0 && position.amount0OnAave == 0 && position.amount1OnAave == 0) {
            delete _positions[positionKey];
        }

        emit OntraPositionRemoved(msg.sender, positionKey, amount0ToRemove, amount1ToRemove);

        return (amount0ToRemove, amount1ToRemove);
    }

    /// @inheritdoc IOntraHook
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory result_) {
        CallbackData memory params = abi.decode(data, (CallbackData));

        if (params.isAdd) {
            result_ = _handleAddLiquidity(params);
        } else {
            result_ = _handleRemoveLiquidity(params);
        }
    }

    /// @inheritdoc IOntraHook
    function rebalanceToAave(address owner, PoolKey calldata key, int24 tickLower, int24 tickUpper) external {
        bytes32 positionKey = getPositionKey(owner, key.toId(), tickLower, tickUpper);
        PositionInfo storage position = _positions[positionKey];

        if (position.owner == address(0)) revert OntraNoPosition();
        if (!position.isInRange) revert OntraPositionAlreadyInAave();
        if (position.liquidity == 0) revert OntraNoLiquidity();

        (, int24 currentTick,,) = poolManager.getSlot0(key.toId());
        require(currentTick < tickLower || tickUpper < currentTick, "Position still in range");

        // Remove liquidity from pool via unlock callback (using owner's position)
        bytes memory result = poolManager.unlock(
            abi.encode(
                CallbackData({
                    sender: owner,
                    key: key,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(uint256(position.liquidity)),
                    amount0: 0,
                    amount1: 0,
                    isAdd: false,
                    isRebalancing: true
                })
            )
        );
        (uint256 amount0, uint256 amount1) = abi.decode(result, (uint256, uint256));

        _aaveDeposit(key.currency0, amount0);
        _aaveDeposit(key.currency1, amount1);

        position.amount0OnAave += amount0;
        position.amount1OnAave += amount1;
        position.liquidity = 0;
        position.isInRange = false;

        emit OntraPositionRebalancedToAave(owner, positionKey, amount0, amount1);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Internal                                  */
    /* -------------------------------------------------------------------------- */

    function _afterInitialize(address, PoolKey calldata key, uint160, int24 tick) internal override returns (bytes4) {
        _lastTicks[key.toId()] = tick;
        return this.afterInitialize.selector;
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        (, int24 tick,,) = poolManager.getSlot0(key.toId());
        _lastTicks[key.toId()] = tick;
        return (BaseHook.afterSwap.selector, 0);
    }

    function _handleAddLiquidity(CallbackData memory params) internal returns (bytes memory) {
        (, int24 currentTick,,) = poolManager.getSlot0(params.key.toId());

        bytes32 positionKey = getPositionKey(params.sender, params.key.toId(), params.tickLower, params.tickUpper);
        PositionInfo storage position = _positions[positionKey];

        // Check if position is in range (contains current tick)
        bool isInRange = (params.tickLower <= currentTick && currentTick <= params.tickUpper);

        if (isInRange) {
            // Calculate liquidity based on current price and desired amounts
            (uint160 sqrtPriceX96Current, uint160 sqrtPriceX96Lower, uint160 sqrtPriceX96Upper) =
                _getSqrtPrices(params.tickLower, params.tickUpper, currentTick);

            uint128 liquidityAmount = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96Current, sqrtPriceX96Lower, sqrtPriceX96Upper, params.amount0, params.amount1
            );

            // Add liquidity to pool
            (BalanceDelta delta,) = poolManager.modifyLiquidity(
                params.key,
                ModifyLiquidityParams({
                    tickLower: params.tickLower,
                    tickUpper: params.tickUpper,
                    liquidityDelta: int256(uint256(liquidityAmount)),
                    salt: bytes32(uint256(uint160(params.sender)))
                }),
                ""
            );

            _settleCurrency(params.key.currency0, params.sender, uint256(uint128(-delta.amount0())));
            _settleCurrency(params.key.currency1, params.sender, uint256(uint128(-delta.amount1())));

            if (position.owner == address(0)) {
                _positions[positionKey] = PositionInfo({
                    owner: params.sender,
                    poolId: params.key.toId(),
                    tickLower: params.tickLower,
                    tickUpper: params.tickUpper,
                    liquidity: liquidityAmount,
                    isInRange: true,
                    amount0OnAave: 0,
                    amount1OnAave: 0
                });
            } else if (position.isInRange) {
                position.liquidity += liquidityAmount;
            } else {
                revert("Position on Aave, rebalance first");
            }

            emit OntraPositionAdded(params.sender, positionKey, true, liquidityAmount, 0, 0);
            return abi.encode(liquidityAmount);
        } else {
            // Position is out of range: deposit to Aave
            _transferAndDepositToAave(params.key.currency0, params.sender, params.amount0);
            _transferAndDepositToAave(params.key.currency1, params.sender, params.amount1);

            if (position.owner == address(0)) {
                _positions[positionKey] = PositionInfo({
                    owner: params.sender,
                    poolId: params.key.toId(),
                    tickLower: params.tickLower,
                    tickUpper: params.tickUpper,
                    liquidity: 0,
                    isInRange: false,
                    amount0OnAave: params.amount0,
                    amount1OnAave: params.amount1
                });
            } else {
                if (position.isInRange) {
                    revert("Position in pool, cannot add to Aave. Rebalance first or use different range");
                }
                require(position.liquidity == 0, "Position has liquidity in pool");
                position.amount0OnAave += params.amount0;
                position.amount1OnAave += params.amount1;
            }

            emit OntraPositionAdded(params.sender, positionKey, false, 0, params.amount0, params.amount1);
            return abi.encode(uint128(0));
        }
    }

    function _handleRemoveLiquidity(CallbackData memory params) internal returns (bytes memory) {
        bytes32 positionKey = getPositionKey(params.sender, params.key.toId(), params.tickLower, params.tickUpper);
        PositionInfo storage position = _positions[positionKey];

        uint128 liquidityToRemove = uint128(uint256(-params.liquidityDelta));

        // Remove liquidity from pool
        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            params.key,
            ModifyLiquidityParams({
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta,
                salt: bytes32(uint256(uint160(params.sender)))
            }),
            ""
        );

        uint256 amount0 = uint256(uint128(delta.amount0()));
        uint256 amount1 = uint256(uint128(delta.amount1()));

        address recipient = params.isRebalancing ? address(this) : params.sender;
        _takeCurrency(params.key.currency0, recipient, amount0);
        _takeCurrency(params.key.currency1, recipient, amount1);

        position.liquidity -= liquidityToRemove;

        // If position is fully removed, delete it (but not during rebalancing)
        if (
            !params.isRebalancing && position.liquidity == 0 && position.amount0OnAave == 0
                && position.amount1OnAave == 0
        ) {
            delete _positions[positionKey];
        }
        // Only emit remove event if not rebalancing
        if (!params.isRebalancing) {
            emit OntraPositionRemoved(params.sender, positionKey, amount0, amount1);
        }

        return abi.encode(amount0, amount1);
    }

    /**
     * @notice Calculates virtual liquidity from Aave amounts.
     * @param amount0OnAave The amount of token0 on Aave.
     * @param amount1OnAave The amount of token1 on Aave.
     * @param tickLower The lower tick of the position.
     * @param tickUpper The upper tick of the position.
     * @return virtualLiquidity_ The calculated virtual liquidity.
     */
    function _calculateVirtualLiquidity(uint256 amount0OnAave, uint256 amount1OnAave, int24 tickLower, int24 tickUpper)
        internal
        pure
        returns (uint128 virtualLiquidity_)
    {
        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(tickUpper);

        if (amount0OnAave > 0 && amount1OnAave > 0) {
            uint128 liq0 = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96Lower, sqrtPriceX96Upper, amount0OnAave);
            uint128 liq1 = LiquidityAmounts.getLiquidityForAmount1(sqrtPriceX96Lower, sqrtPriceX96Upper, amount1OnAave);
            return liq0 > liq1 ? liq0 : liq1;
        } else if (amount0OnAave > 0) {
            return LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96Lower, sqrtPriceX96Upper, amount0OnAave);
        } else if (amount1OnAave > 0) {
            return LiquidityAmounts.getLiquidityForAmount1(sqrtPriceX96Lower, sqrtPriceX96Upper, amount1OnAave);
        }
        return virtualLiquidity_;
    }

    /**
     * @notice Deposits tokens into Aave.
     * @param asset The asset being deposited.
     * @param amount Amount to deposit.
     */
    function _aaveDeposit(Currency asset, uint256 amount) internal {
        IERC20(Currency.unwrap(asset)).forceApprove(address(AAVE_POOL), amount);
        AAVE_POOL.supply(Currency.unwrap(asset), amount, address(this), 0);
    }

    /**
     * @notice Withdraws tokens from Aave.
     * @param asset The asset being withdrawn.
     * @param amount Amount to withdraw.
     * @return amountWithdrawn The amount withdrawn.
     */
    function _aaveWithdraw(Currency asset, uint256 amount) internal returns (uint256 amountWithdrawn) {
        amountWithdrawn = AAVE_POOL.withdraw(Currency.unwrap(asset), amount, address(this));
    }

    /**
     * @notice Helper to settle currency from a specific address.
     * @param currency The currency to settle.
     * @param from The address to settle from.
     * @param amount The amount to settle.
     */
    function _settleCurrency(Currency currency, address from, uint256 amount) internal {
        if (amount > 0) {
            currency.settle(poolManager, from, amount, false);
        }
    }

    /**
     * @notice Helper to take currency to a specific address.
     * @param currency The currency to take.
     * @param to The address to send the currency to.
     * @param amount The amount to take.
     */
    function _takeCurrency(Currency currency, address to, uint256 amount) internal {
        if (amount > 0) {
            currency.take(poolManager, to, amount, false);
        }
    }

    /**
     * @notice Withdraws from Aave
     * @param currency The currency to withdraw.
     * @param amount The principal amount to withdraw and send to the user.
     * @param recipient The address to send the principal to.
     */
    function _withdrawFromAave(Currency currency, uint256 amount, address recipient) internal {
        if (amount == 0) return;
        uint256 withdrawn = _aaveWithdraw(currency, amount);
        IERC20(Currency.unwrap(currency)).safeTransfer(recipient, withdrawn);
    }

    /**
     * @notice Transfers from user and deposits to Aave.
     * @param currency The currency to transfer and deposit.
     * @param from The address to transfer from.
     * @param amount The amount to transfer and deposit.
     */
    function _transferAndDepositToAave(Currency currency, address from, uint256 amount) internal {
        if (amount > 0) {
            IERC20(Currency.unwrap(currency)).safeTransferFrom(from, address(this), amount);
            _aaveDeposit(currency, amount);
        }
    }

    /**
     * @notice Calculates sqrt prices for a tick range.
     * @param tickLower The lower tick.
     * @param tickUpper The upper tick.
     * @param currentTick The current tick.
     * @return sqrtPriceX96Current_ The current sqrt price.
     * @return sqrtPriceX96Lower_ The lower sqrt price.
     * @return sqrtPriceX96Upper_ The upper sqrt price.
     */
    function _getSqrtPrices(int24 tickLower, int24 tickUpper, int24 currentTick)
        internal
        pure
        returns (uint160 sqrtPriceX96Current_, uint160 sqrtPriceX96Lower_, uint160 sqrtPriceX96Upper_)
    {
        sqrtPriceX96Current_ = TickMath.getSqrtPriceAtTick(currentTick);
        sqrtPriceX96Lower_ = TickMath.getSqrtPriceAtTick(tickLower);
        sqrtPriceX96Upper_ = TickMath.getSqrtPriceAtTick(tickUpper);
    }
}
