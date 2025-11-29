// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes} from "aave-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IPool} from "aave-v3/contracts/interfaces/IPool.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
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

    mapping(PoolId poolId => int24 lastTick) public _lastTicks;

    mapping(IERC20 => AssetData) _assets;
    mapping(bytes32 => uint256) _loanShares; // loanHash => shares
    mapping(bytes32 => uint256) _tickShares; // tickHash => shares

    // Track user positions managed by the hook
    struct Position {
        uint128 liquidity;
        uint256 token0Deposited;
        uint256 token1Deposited;
        bool isInRange; // true if liquidity is in PoolManager, false if in Aave
    }

    mapping(bytes32 => Position) public positions; // positionId => Position

    struct CallbackData {
        address sender;
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        uint256 amount0;
        uint256 amount1;
        bool isAdd;
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
                    liquidityDelta: int256(uint256(type(uint128).max)), // Calculate actual liquidity in callback
                    amount0: amount0Desired,
                    amount1: amount1Desired,
                    isAdd: true
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
                    isAdd: false
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

        // Check if position is in range (contains current tick)
        bool isInRange = (params.tickLower <= currentTick && currentTick < params.tickUpper);

        if (isInRange) {
            // Calculate liquidity based on current price and desired amounts
            uint160 sqrtPriceX96Current = TickMath.getSqrtPriceAtTick(currentTick);
            uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(params.tickLower);
            uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(params.tickUpper);
            // Add liquidity to the pool via modifyLiquidity
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
                    salt: bytes32(0)
                }),
                ""
            );
            // If delta is negative, user owes tokens to the pool
            if (delta.amount0() < 0) {
                params.key.currency0.settle(poolManager, params.sender, uint256(uint128(-delta.amount0())), false);
            }
            if (delta.amount1() < 0) {
                params.key.currency1.settle(poolManager, params.sender, uint256(uint128(-delta.amount1())), false);
            }
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
        }

        // Calculate and store position
        uint128 liquidity = uint128(params.amount0 + params.amount1); // Simplified
        bytes32 positionId =
            keccak256(abi.encodePacked(params.sender, params.key.toId(), params.tickLower, params.tickUpper));

        positions[positionId] = Position({
            liquidity: positions[positionId].liquidity + liquidity,
            token0Deposited: positions[positionId].token0Deposited + params.amount0,
            token1Deposited: positions[positionId].token1Deposited + params.amount1,
            isInRange: isInRange
        });

        return abi.encode(liquidity);
    }

    function _handleRemoveLiquidity(CallbackData memory params) internal returns (bytes memory) {
        uint128 liquidityToRemove = uint128(uint256(-params.liquidityDelta));
        bytes32 positionId =
            keccak256(abi.encodePacked(params.sender, params.key.toId(), params.tickLower, params.tickUpper));

        Position storage position = positions[positionId];
        require(position.liquidity >= liquidityToRemove, "Insufficient liquidity");

        // Calculate proportional amounts
        uint256 amount0 = (position.token0Deposited * liquidityToRemove) / position.liquidity;
        uint256 amount1 = (position.token1Deposited * liquidityToRemove) / position.liquidity;

        if (position.isInRange) {
            // Remove liquidity from PoolManager
            (, int24 currentTick,,) = poolManager.getSlot0(params.key.toId());
            uint128 liquidityAmount = LiquidityAmounts.getLiquidityForAmounts(
                TickMath.getSqrtPriceAtTick(currentTick),
                TickMath.getSqrtPriceAtTick(params.tickLower),
                TickMath.getSqrtPriceAtTick(params.tickUpper),
                amount0,
                amount1
            );

            // Remove liquidity from pool
            (BalanceDelta delta,) = poolManager.modifyLiquidity(
                params.key,
                ModifyLiquidityParams({
                    tickLower: params.tickLower,
                    tickUpper: params.tickUpper,
                    liquidityDelta: -int256(uint256(liquidityAmount)),
                    salt: bytes32(0)
                }),
                ""
            );
            // Take the tokens and send to user (delta should be positive when removing liquidity)
            if (delta.amount0() > 0) {
                params.key.currency0.take(poolManager, params.sender, uint256(uint128(delta.amount0())), false);
            }
            if (delta.amount1() > 0) {
                params.key.currency1.take(poolManager, params.sender, uint256(uint128(delta.amount1())), false);
            }
        } else {
            // Withdraw from Aave and send to user
            if (amount0 > 0) {
                _aaveWithdraw(params.key.currency0, amount0);
                IERC20(Currency.unwrap(params.key.currency0)).transfer(params.sender, amount0);
            }
            if (amount1 > 0) {
                _aaveWithdraw(params.key.currency1, amount1);
                IERC20(Currency.unwrap(params.key.currency1)).transfer(params.sender, amount1);
            }
        }

        // Update position
        position.liquidity -= liquidityToRemove;
        position.token0Deposited -= amount0;
        position.token1Deposited -= amount1;

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
