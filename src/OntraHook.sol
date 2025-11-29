// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

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

import {IOntra} from "./interfaces/IOntra.sol";

contract OntraHook is BaseHook, IOntra {
    using StateLibrary for IPoolManager;
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;
    using CurrencySettler for Currency;

    IPool public immutable AAVE_POOL;

    event PositionAdded(address indexed owner, bytes32 indexed positionKey, bool isInRange, uint128 liquidity);
    event PositionRemoved(address indexed owner, bytes32 indexed positionKey, uint256 amount0, uint256 amount1);
    event PositionRebalancedToAave(
        address indexed owner, bytes32 indexed positionKey, uint256 amount0, uint256 amount1
    );
    event PositionRebalancedToPool(address indexed owner, bytes32 indexed positionKey, uint128 liquidity);

    mapping(PoolId poolId => int24 lastTick) public _lastTicks;

    mapping(IERC20 => AssetData) _assets;
    mapping(bytes32 => uint256) _loanShares; // loanHash => shares
    mapping(bytes32 => uint256) _tickShares; // tickHash => shares

    // Position tracking
    struct PositionInfo {
        address owner;
        PoolId poolId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        bool isInRange;
        uint256 amount0OnAave; // Amount on Aave when out of range
        uint256 amount1OnAave; // Amount on Aave when out of range
    }

    mapping(bytes32 positionKey => PositionInfo) public positions;

    struct CallbackData {
        address sender;
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        uint256 amount0;
        uint256 amount1;
        bool isAdd;
        bool isRebalancing; // True when called from rebalance functions
    }

    // Constructor
    constructor(IPoolManager _manager, IPool _aavePool) BaseHook(_manager) {
        AAVE_POOL = _aavePool;
    }

    // BaseHook Functions
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

    /**
     * @notice Get the position key for a user's position
     * @param owner Owner of the position
     * @param poolId Pool ID
     * @param tickLower Lower tick
     * @param tickUpper Upper tick
     * @return key_ The unique key for this position
     */
    function getPositionKey(address owner, PoolId poolId, int24 tickLower, int24 tickUpper)
        public
        pure
        returns (bytes32 key_)
    {
        key_ = keccak256(abi.encode(owner, poolId, tickLower, tickUpper));
    }

    /**
     * @notice Add liquidity through the hook - tokens are deposited to Aave
     * @param key PoolKey of the pool
     * @param tickLower Lower tick of the position
     * @param tickUpper Upper tick of the position
     * @param amount0Desired Desired amount of token0 to add
     * @param amount1Desired Desired amount of token1 to add
     * @return liquidity Amount of liquidity added
     */
    function addLiquidity(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint128 liquidity) {
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

        liquidity = abi.decode(result, (uint128));
    }

    /**
     * @notice Remove liquidity through the hook - tokens are withdrawn from Aave
     * @param key PoolKey of the pool
     * @param tickLower Lower tick of the position
     * @param tickUpper Upper tick of the position
     * @param liquidityToRemove Amount of liquidity to remove
     * @return amount0 Amount of token0 withdrawn
     * @return amount1 Amount of token1 withdrawn
     */
    function removeLiquidity(PoolKey calldata key, int24 tickLower, int24 tickUpper, uint128 liquidityToRemove)
        external
        returns (uint256 amount0, uint256 amount1)
    {
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

        (amount0, amount1) = abi.decode(result, (uint256, uint256));
    }

    /**
     * @notice Unlock callback to handle add/remove liquidity
     * @param data Encoded CallbackData
     * @return Encoded result depending on add/remove liquidity
     */
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        CallbackData memory params = abi.decode(data, (CallbackData));

        if (params.isAdd) {
            return _handleAddLiquidity(params);
        } else {
            return _handleRemoveLiquidity(params);
        }
    }

    /**
     * @notice Rebalance a position from the pool to Aave when out of range
     * @dev Can be called by anyone to move an out-of-range position to Aave
     * @param owner Owner of the position
     * @param key PoolKey of the pool
     * @param tickLower Lower tick of the position
     * @param tickUpper Upper tick of the position
     */
    function rebalanceToAave(address owner, PoolKey calldata key, int24 tickLower, int24 tickUpper) external {
        bytes32 positionKey = getPositionKey(owner, key.toId(), tickLower, tickUpper);
        PositionInfo storage position = positions[positionKey];

        require(position.owner == owner, "Invalid position");
        require(position.isInRange, "Position already on Aave");
        require(position.liquidity > 0, "No liquidity to rebalance");

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

        // Deposit to Aave
        if (amount0 > 0) {
            _aaveDeposit(key.currency0, amount0);
        }
        if (amount1 > 0) {
            _aaveDeposit(key.currency1, amount1);
        }

        // Update position state - accumulate amounts if there were already some on Aave
        position.amount0OnAave += amount0;
        position.amount1OnAave += amount1;
        position.liquidity = 0;
        position.isInRange = false;

        emit PositionRebalancedToAave(owner, positionKey, amount0, amount1);
    }

    /**
     * @notice Rebalance a position from Aave to the pool when back in range
     * @dev Can be called by anyone to move a position back to the pool
     * @param owner Owner of the position
     * @param key PoolKey of the pool
     * @param tickLower Lower tick of the position
     * @param tickUpper Upper tick of the position
     */
    function rebalanceToPool(address owner, PoolKey calldata key, int24 tickLower, int24 tickUpper) external {
        bytes32 positionKey = getPositionKey(owner, key.toId(), tickLower, tickUpper);
        PositionInfo storage position = positions[positionKey];

        require(position.owner == owner, "Invalid position");
        require(!position.isInRange, "Position already in pool");

        (, int24 currentTick,,) = poolManager.getSlot0(key.toId());
        require(tickLower <= currentTick && currentTick <= tickUpper, "Position not in range");

        uint256 amount0 = position.amount0OnAave;
        uint256 amount1 = position.amount1OnAave;

        // Withdraw from Aave
        if (amount0 > 0) {
            _aaveWithdraw(key.currency0, amount0);
        }
        if (amount1 > 0) {
            _aaveWithdraw(key.currency1, amount1);
        }

        // Calculate liquidity and add to pool via unlock callback (using owner's position)
        bytes memory result = poolManager.unlock(
            abi.encode(
                CallbackData({
                    sender: owner,
                    key: key,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: int256(uint256(type(uint128).max)),
                    amount0: amount0,
                    amount1: amount1,
                    isAdd: true,
                    isRebalancing: true
                })
            )
        );

        uint128 liquidity = abi.decode(result, (uint128));

        // Update position state
        position.liquidity = liquidity;
        position.isInRange = true;
        position.amount0OnAave = 0;
        position.amount1OnAave = 0;

        emit PositionRebalancedToPool(owner, positionKey, liquidity);
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

        // Generate position key
        bytes32 positionKey = getPositionKey(params.sender, params.key.toId(), params.tickLower, params.tickUpper);
        PositionInfo storage position = positions[positionKey];

        // Check if position is in range (contains current tick)
        bool isInRange = (params.tickLower <= currentTick && currentTick <= params.tickUpper);

        if (isInRange) {
            // Calculate liquidity based on current price and desired amounts
            uint160 sqrtPriceX96Current = TickMath.getSqrtPriceAtTick(currentTick);
            uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(params.tickLower);
            uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(params.tickUpper);
            // Calculate actual liquidity amount
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
            // If delta is negative, user owes tokens to the pool
            if (params.isRebalancing) {
                // When rebalancing, hook provides the tokens (already withdrawn from Aave)
                params.key.currency0.settle(poolManager, address(this), uint256(uint128(-delta.amount0())), false);
                params.key.currency1.settle(poolManager, address(this), uint256(uint128(-delta.amount1())), false);
            } else {
                // Normal case: user provides the tokens
                params.key.currency0.settle(poolManager, params.sender, uint256(uint128(-delta.amount0())), false);
                params.key.currency1.settle(poolManager, params.sender, uint256(uint128(-delta.amount1())), false);
            }

            // Update or create position info
            if (position.owner == address(0)) {
                // New position
                position.owner = params.sender;
                position.poolId = params.key.toId();
                position.tickLower = params.tickLower;
                position.tickUpper = params.tickUpper;
                position.liquidity = liquidityAmount;
                position.isInRange = true;
                position.amount0OnAave = 0;
                position.amount1OnAave = 0;
            } else {
                // Existing position - accumulate liquidity
                position.liquidity += liquidityAmount;
            }

            emit PositionAdded(params.sender, positionKey, true, liquidityAmount);

            return abi.encode(liquidityAmount);
        } else {
            // Position is out of range: deposit to Aave
            if (params.amount0 > 0) {
                IERC20(Currency.unwrap(params.key.currency0)).transferFrom(params.sender, address(this), params.amount0);
                _aaveDeposit(params.key.currency0, params.amount0);
            }
            if (params.amount1 > 0) {
                IERC20(Currency.unwrap(params.key.currency1)).transferFrom(params.sender, address(this), params.amount1);
                _aaveDeposit(params.key.currency1, params.amount1);
            }

            // Update or create position info with amounts on Aave
            if (position.owner == address(0)) {
                // New position
                position.owner = params.sender;
                position.poolId = params.key.toId();
                position.tickLower = params.tickLower;
                position.tickUpper = params.tickUpper;
                position.liquidity = 0;
                position.isInRange = false;
                position.amount0OnAave = params.amount0;
                position.amount1OnAave = params.amount1;
            } else {
                // Existing position - accumulate amounts on Aave
                position.amount0OnAave += params.amount0;
                position.amount1OnAave += params.amount1;
            }

            emit PositionAdded(params.sender, positionKey, false, 0);

            // No liquidity is added to the pool when depositing to Aave
            return abi.encode(uint128(0));
        }
    }

    function _handleRemoveLiquidity(CallbackData memory params) internal returns (bytes memory) {
        bytes32 positionKey = getPositionKey(params.sender, params.key.toId(), params.tickLower, params.tickUpper);
        PositionInfo storage position = positions[positionKey];

        // Verify ownership (except during rebalancing where sender is already verified)
        if (!params.isRebalancing) {
            require(position.owner == params.sender, "Not position owner");
        }

        uint256 amount0;
        uint256 amount1;

        uint128 liquidityToRemove = uint128(uint256(-params.liquidityDelta));
        if (position.isInRange) {
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
            // Take the tokens and send to user (delta should be positive when removing liquidity)
            amount0 = uint256(uint128(delta.amount0()));
            amount1 = uint256(uint128(delta.amount1()));

            if (params.isRebalancing) {
                // When rebalancing, hook receives the tokens (will deposit to Aave)
                if (amount0 > 0) {
                    params.key.currency0.take(poolManager, address(this), amount0, false);
                }
                if (amount1 > 0) {
                    params.key.currency1.take(poolManager, address(this), amount1, false);
                }
            } else {
                // Normal case: send tokens to user
                if (amount0 > 0) {
                    params.key.currency0.take(poolManager, params.sender, amount0, false);
                }
                if (amount1 > 0) {
                    params.key.currency1.take(poolManager, params.sender, amount1, false);
                }
            }

            // Update position - subtract removed liquidity
            require(position.liquidity >= liquidityToRemove, "Insufficient liquidity");
            position.liquidity -= liquidityToRemove;
        } else {
            // Withdraw from Aave - position is out of range

            // Calculate total "virtual liquidity" that the current Aave amounts represent
            // Use the appropriate tick for calculation based on where current price is relative to range
            (, int24 currentTick,,) = poolManager.getSlot0(params.key.toId());
            uint160 sqrtPriceX96;

            if (currentTick < params.tickLower) {
                // Current tick below range - all liquidity in token0
                sqrtPriceX96 = TickMath.getSqrtPriceAtTick(params.tickLower);
            } else {
                // Current tick above range - all liquidity in token1
                sqrtPriceX96 = TickMath.getSqrtPriceAtTick(params.tickUpper);
            }

            uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(params.tickLower);
            uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(params.tickUpper);

            // Calculate total virtual liquidity from amounts on Aave
            uint128 totalVirtualLiquidity;
            if (position.amount0OnAave > 0 && position.amount1OnAave > 0) {
                // Both tokens on Aave - calculate liquidity for both and take the one that gives more liquidity
                // This should theoretically not happen in a properly managed position, but handle it safely
                uint128 liq0 = LiquidityAmounts.getLiquidityForAmount0(
                    sqrtPriceX96Lower, sqrtPriceX96Upper, position.amount0OnAave
                );
                uint128 liq1 = LiquidityAmounts.getLiquidityForAmount1(
                    sqrtPriceX96Lower, sqrtPriceX96Upper, position.amount1OnAave
                );
                totalVirtualLiquidity = liq0 > liq1 ? liq0 : liq1;
            } else if (position.amount0OnAave > 0) {
                totalVirtualLiquidity = LiquidityAmounts.getLiquidityForAmount0(
                    sqrtPriceX96Lower, sqrtPriceX96Upper, position.amount0OnAave
                );
            } else if (position.amount1OnAave > 0) {
                totalVirtualLiquidity = LiquidityAmounts.getLiquidityForAmount1(
                    sqrtPriceX96Lower, sqrtPriceX96Upper, position.amount1OnAave
                );
            }

            // Calculate proportional amounts to withdraw
            require(totalVirtualLiquidity > 0, "No liquidity on Aave");
            require(liquidityToRemove <= totalVirtualLiquidity, "Insufficient liquidity on Aave");

            if (liquidityToRemove >= totalVirtualLiquidity) {
                // Withdraw all
                amount0 = position.amount0OnAave;
                amount1 = position.amount1OnAave;
            } else {
                // Withdraw proportionally
                amount0 = position.amount0OnAave.mulDivDown(liquidityToRemove, totalVirtualLiquidity);
                amount1 = position.amount1OnAave.mulDivDown(liquidityToRemove, totalVirtualLiquidity);
            }

            if (amount0 > 0) {
                _aaveWithdraw(params.key.currency0, amount0);
                IERC20(Currency.unwrap(params.key.currency0)).transfer(params.sender, amount0);
                position.amount0OnAave -= amount0;
            }
            if (amount1 > 0) {
                _aaveWithdraw(params.key.currency1, amount1);
                IERC20(Currency.unwrap(params.key.currency1)).transfer(params.sender, amount1);
                position.amount1OnAave -= amount1;
            }
        }

        // If position is fully removed, delete it
        if (position.liquidity == 0 && position.amount0OnAave == 0 && position.amount1OnAave == 0) {
            delete positions[positionKey];
        }

        emit PositionRemoved(params.sender, positionKey, amount0, amount1);

        return abi.encode(amount0, amount1);
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
     */
    function _aaveWithdraw(Currency asset, uint256 amount) internal {
        AAVE_POOL.withdraw(Currency.unwrap(asset), amount, address(this));
    }
}
