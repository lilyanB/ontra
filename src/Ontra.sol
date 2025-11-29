// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes} from "aave-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
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

contract Ontra is BaseHook, IOntra {
    using StateLibrary for IPoolManager;
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    /// @dev The bit position of the frozen boolean in the `ReserveConfigurationMap` data.
    uint8 internal constant RESERVE_FROZEN_BIT = 57;

    /// @dev The bit position of the paused boolean in the `ReserveConfigurationMap` data.
    uint8 internal constant RESERVE_PAUSED_BIT = 60;

    IPool public immutable AAVE_POOL;

    mapping(PoolId poolId => int24 lastTick) public _lastTicks;

    mapping(IERC20 => AssetData) _assets;
    mapping(bytes32 => uint256) _loanShares; // loanHash => shares
    mapping(bytes32 => uint256) _tickShares; // tickHash => shares

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
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
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

    function _afterInitialize(address, PoolKey calldata key, uint160, int24 tick) internal override returns (bytes4) {
        _lastTicks[key.toId()] = tick;
        return this.afterInitialize.selector;
    }

    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        (, int24 currentTick,,) = poolManager.getSlot0(key.toId());

        if (params.tickLower <= currentTick && currentTick <= params.tickUpper) {
            // position is in the current tick range, liquidity is idle, nothing to do
            return (this.afterAddLiquidity.selector);
        }
        // position is out of the current tick range, liquidity is in Aave, need to withdraw

        uint128 liquidityToRemove = uint128(uint256(-params.liquidityDelta));
        // calculate corresponding amounts for each token based on tick range
        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(params.tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(params.tickUpper);
        // calculate amounts for each token based on liquidity being removed and current tick
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtPriceAtTick(currentTick), sqrtPriceX96Lower, sqrtPriceX96Upper, liquidityToRemove
        );

        // Withdraw funds from Aave (negative amounts = withdrawal)
        _aaveMigrate(key.currency0, -int256(amount0));
        _aaveMigrate(key.currency1, -int256(amount1));

        return (this.beforeRemoveLiquidity.selector);
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        (, int24 currentTick,,) = poolManager.getSlot0(key.toId());
        int24 lastTick = _lastTicks[key.toId()];

        if (params.tickLower <= currentTick && currentTick <= params.tickUpper) {
            // position is in the current tick range, liquidity must stay idle
            return (this.afterAddLiquidity.selector, delta);
        }
        // position is out of the current tick range, liquidity can be invested in Aave
        _aaveMigrate(key.currency0, delta.amount0());
        _aaveMigrate(key.currency1, delta.amount1());

        return (this.afterAddLiquidity.selector, delta);
    }

    function _afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        (, int24 currentTick,,) = poolManager.getSlot0(key.toId());
        int24 lastTick = _lastTicks[key.toId()];

        if (currentTick == lastTick) {
            // no tick change, nothing to do
            return (this.afterSwap.selector, 0);
        }
        // TODO: modify Aave investments based on tick movement and liquidity ranges

        // New last known tick for this pool is the tick value
        // after our orders are executed
        _lastTicks[key.toId()] = currentTick;
        return (this.afterSwap.selector, 0);
    }

    /**
     * @notice Migrates assets between the vault and Aave based on the specified amount.
     * @param asset The asset to migrate.
     * @param amount The amount to migrate. Positive values indicate deposits to Aave, negative values indicate withdrawals.
     */
    function _aaveMigrate(Currency asset, int256 amount) internal {
        if (amount > 0) {
            _aaveDeposit(asset, uint256(amount));
        } else if (amount < 0) {
            _aaveWithdraw(asset, uint256(-amount));
        }
    }

    /**
     * @notice Deposits tokens into Aave.
     * @param asset The asset being deposited.
     * @param amount Amount to deposit.
     */
    function _aaveDeposit(Currency asset, uint256 amount) internal {
        IERC20(Currency.unwrap(asset)).forceApprove(address(AAVE_POOL), amount);
        AAVE_POOL.supply(Currency.unwrap(asset), amount, address(this), 0); // referral supply is currently inactive
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
