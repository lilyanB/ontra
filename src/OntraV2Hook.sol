// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IPool} from "aave-v3/contracts/interfaces/IPool.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IOntraV2Hook} from "./interfaces/IOntraV2Hook.sol";

/**
 * @title OntraV2Hook
 * @notice Trailing Stop Order Hook for Uniswap V4 with Aave integration
 * @dev Implements 3 tiers of trailing stops (5%, 10%, 15%) with pooled execution
 */
contract OntraV2Hook is BaseHook, IOntraV2Hook {
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;

    /* -------------------------------------------------------------------------- */
    /*                                  Storage                                   */
    /* -------------------------------------------------------------------------- */

    IPool public immutable override AAVE_POOL;

    mapping(PoolId poolId => int24 lastTick) public lastTicks;

    // poolId => tier => epoch => pool data
    mapping(PoolId => mapping(TrailingStopTier => mapping(uint256 => TrailingStopPool))) internal _trailingPools;

    // poolId => tier => isLong => current epoch
    mapping(PoolId => mapping(TrailingStopTier => mapping(bool => uint256))) public currentEpoch;

    // user => poolId => tier => isLong => epoch => shares
    mapping(
        address => mapping(PoolId => mapping(TrailingStopTier => mapping(bool => mapping(uint256 => uint256))))
    ) public userShares;

    /// @inheritdoc IOntraV2Hook
    function trailingPools(PoolId poolId, TrailingStopTier tier, uint256 epoch)
        external
        view
        override
        returns (TrailingStopPool memory pool)
    {
        return _trailingPools[poolId][tier][epoch];
    }

    /// @inheritdoc IOntraV2Hook
    function getUserShares(address user, PoolId poolId, TrailingStopTier tier, bool isLong, uint256 epoch)
        external
        view
        override
        returns (uint256 shares)
    {
        return userShares[user][poolId][tier][isLong][epoch];
    }

    /// @inheritdoc IOntraV2Hook
    function getCurrentEpoch(PoolId poolId, TrailingStopTier tier, bool isLong)
        external
        view
        override
        returns (uint256 epoch)
    {
        return currentEpoch[poolId][tier][isLong];
    }

    /* -------------------------------------------------------------------------- */
    /*                                Constructor                                 */
    /* -------------------------------------------------------------------------- */

    constructor(IPoolManager manager, IPool aavePool) BaseHook(manager) {
        AAVE_POOL = aavePool;
    }

    /* -------------------------------------------------------------------------- */
    /*                              Hook Permissions                              */
    /* -------------------------------------------------------------------------- */

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

    /* -------------------------------------------------------------------------- */
    /*                              Public Functions                              */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IOntraV2Hook
    function createTrailingStop(PoolKey calldata key, uint256 amount, bool isLong, TrailingStopTier tier)
        external
        returns (uint256 shares)
    {
        require(amount > 0, "Amount must be > 0");

        Currency depositToken = isLong ? key.currency0 : key.currency1;

        // Transfer tokens from user and deposit to Aave
        IERC20(Currency.unwrap(depositToken)).safeTransferFrom(msg.sender, address(this), amount);
        _aaveDeposit(depositToken, amount);

        (, int24 currentTick,,) = poolManager.getSlot0(key.toId());

        // Get current epoch for this direction
        uint256 epoch = currentEpoch[key.toId()][tier][isLong];

        // Update pool
        TrailingStopPool storage pool = _trailingPools[key.toId()][tier][epoch];

        // Calculate shares: first depositor gets 1:1, others get proportional
        if (isLong) {
            if (pool.totalSharesLong == 0) {
                shares = amount; // First depositor
            } else {
                // Proportional to existing pool
                shares = (amount * pool.totalSharesLong) / pool.totalToken0Long;
            }

            pool.totalToken0Long += amount;
            pool.totalSharesLong += shares;

            // Initialize or update highest tick
            if (pool.highestTickEver == 0 || currentTick > pool.highestTickEver) {
                pool.highestTickEver = currentTick;
                pool.triggerTickLong = _calculateTriggerTickLong(currentTick, tier);
            }
        } else {
            if (pool.totalSharesShort == 0) {
                shares = amount; // First depositor
            } else {
                // Proportional to existing pool
                shares = (amount * pool.totalSharesShort) / pool.totalToken1Short;
            }

            pool.totalToken1Short += amount;
            pool.totalSharesShort += shares;

            // Initialize or update lowest tick
            if (pool.lowestTickEver == type(int24).max || currentTick < pool.lowestTickEver) {
                pool.lowestTickEver = currentTick;
                pool.triggerTickShort = _calculateTriggerTickShort(currentTick, tier);
            }
        }

        // Store user shares for this epoch
        userShares[msg.sender][key.toId()][tier][isLong][epoch] += shares;

        emit TrailingStopCreated(msg.sender, key.toId(), amount, shares, isLong, tier, epoch);

        return shares;
    }

    /// @inheritdoc IOntraV2Hook
    function withdrawTrailingStop(
        PoolKey calldata key,
        uint256 shares,
        bool isLong,
        TrailingStopTier tier,
        uint256 epoch
    ) external returns (uint256 amountWithdrawn) {
        if (shares == 0) revert NoShares();

        uint256 userSharesAmount = userShares[msg.sender][key.toId()][tier][isLong][epoch];
        if (userSharesAmount < shares) revert NoShares();

        TrailingStopPool storage pool = _trailingPools[key.toId()][tier][epoch];

        if (isLong) {
            // Check if pool has been executed (executedToken1 > 0 means executed)
            if (pool.executedToken1 > 0) {
                // Pool was executed, withdraw proportional token1
                amountWithdrawn = (shares * pool.executedToken1) / pool.totalSharesLong;

                _withdrawFromAave(key.currency1, amountWithdrawn, msg.sender);
            } else {
                // Pool not executed yet, withdraw proportional token0
                if (pool.totalToken0Long == 0) revert NoTokens();
                amountWithdrawn = (shares * pool.totalToken0Long) / pool.totalSharesLong;

                _withdrawFromAave(key.currency0, amountWithdrawn, msg.sender);

                // Update pool state
                pool.totalToken0Long -= amountWithdrawn;
                pool.totalSharesLong -= shares;
            }
        } else {
            // Check if pool has been executed (executedToken0 > 0 means executed)
            if (pool.executedToken0 > 0) {
                // Pool was executed, withdraw proportional token0
                amountWithdrawn = (shares * pool.executedToken0) / pool.totalSharesShort;

                _withdrawFromAave(key.currency0, amountWithdrawn, msg.sender);
            } else {
                // Pool not executed yet, withdraw proportional token1
                if (pool.totalToken1Short == 0) revert NoTokens();
                amountWithdrawn = (shares * pool.totalToken1Short) / pool.totalSharesShort;

                _withdrawFromAave(key.currency1, amountWithdrawn, msg.sender);

                // Update pool state
                pool.totalToken1Short -= amountWithdrawn;
                pool.totalSharesShort -= shares;
            }
        }

        // Update user shares
        userShares[msg.sender][key.toId()][tier][isLong][epoch] -= shares;

        emit TrailingStopWithdrawn(msg.sender, key.toId(), shares, amountWithdrawn, isLong, tier, epoch);

        return amountWithdrawn;
    }

    /// @inheritdoc IOntraV2Hook
    function executeTrailingStops(PoolKey calldata key, TrailingStopTier tier) external {
        (, int24 currentTick,,) = poolManager.getSlot0(key.toId());

        // Check and execute longs
        uint256 longEpoch = currentEpoch[key.toId()][tier][true];
        TrailingStopPool storage longPool = _trailingPools[key.toId()][tier][longEpoch];
        if (longPool.executedToken1 == 0 && longPool.totalSharesLong > 0 && currentTick <= longPool.triggerTickLong) {
            _executePoolTrailingStopLong(key, tier, longEpoch, currentTick);
        }

        // Check and execute shorts
        uint256 shortEpoch = currentEpoch[key.toId()][tier][false];
        TrailingStopPool storage shortPool = _trailingPools[key.toId()][tier][shortEpoch];
        if (
            shortPool.executedToken0 == 0 && shortPool.totalSharesShort > 0 && currentTick >= shortPool.triggerTickShort
        ) {
            _executePoolTrailingStopShort(key, tier, shortEpoch, currentTick);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              Hook Callbacks                                */
    /* -------------------------------------------------------------------------- */

    function _afterInitialize(address, PoolKey calldata key, uint160, int24 tick) internal override returns (bytes4) {
        lastTicks[key.toId()] = tick;
        return this.afterInitialize.selector;
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        (, int24 currentTick,,) = poolManager.getSlot0(key.toId());
        int24 previousTick = lastTicks[key.toId()];
        lastTicks[key.toId()] = currentTick;

        // Price went up -> update longs and check shorts
        if (currentTick > previousTick) {
            _updateLongTrailingStops(key, currentTick);
            _checkAndExecuteShortTrailingStops(key, currentTick);
        }

        // Price went down -> update shorts and check longs
        if (currentTick < previousTick) {
            _updateShortTrailingStops(key, currentTick);
            _checkAndExecuteLongTrailingStops(key, currentTick);
        }

        return (this.afterSwap.selector, 0);
    }

    /// @inheritdoc IOntraV2Hook
    function unlockCallback(bytes calldata data) external override onlyPoolManager returns (bytes memory) {
        SwapCallbackData memory params = abi.decode(data, (SwapCallbackData));
        return _handleSwap(params);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal Functions                             */
    /* -------------------------------------------------------------------------- */

    function _updateLongTrailingStops(PoolKey calldata key, int24 currentTick) internal {
        for (uint256 i = 0; i < 3; i++) {
            TrailingStopTier tier = TrailingStopTier(i);
            uint256 epoch = currentEpoch[key.toId()][tier][true];
            TrailingStopPool storage pool = _trailingPools[key.toId()][tier][epoch];

            if (pool.executedToken1 > 0 || pool.totalSharesLong == 0) continue;

            if (currentTick > pool.highestTickEver) {
                pool.highestTickEver = currentTick;
                pool.triggerTickLong = _calculateTriggerTickLong(currentTick, tier);
            }
        }
    }

    function _updateShortTrailingStops(PoolKey calldata key, int24 currentTick) internal {
        for (uint256 i = 0; i < 3; i++) {
            TrailingStopTier tier = TrailingStopTier(i);
            uint256 epoch = currentEpoch[key.toId()][tier][false];
            TrailingStopPool storage pool = _trailingPools[key.toId()][tier][epoch];

            if (pool.executedToken0 > 0 || pool.totalSharesShort == 0) continue;

            if (currentTick < pool.lowestTickEver) {
                pool.lowestTickEver = currentTick;
                pool.triggerTickShort = _calculateTriggerTickShort(currentTick, tier);
            }
        }
    }

    function _checkAndExecuteLongTrailingStops(PoolKey calldata key, int24 currentTick) internal {
        for (uint256 i = 0; i < 3; i++) {
            TrailingStopTier tier = TrailingStopTier(i);
            uint256 epoch = currentEpoch[key.toId()][tier][true];
            TrailingStopPool storage pool = _trailingPools[key.toId()][tier][epoch];

            if (pool.executedToken1 > 0 || pool.totalSharesLong == 0) continue;

            // Price dropped below trigger -> execute
            if (currentTick <= pool.triggerTickLong) {
                _executePoolTrailingStopLong(key, tier, epoch, currentTick);
            }
        }
    }

    function _checkAndExecuteShortTrailingStops(PoolKey calldata key, int24 currentTick) internal {
        for (uint256 i = 0; i < 3; i++) {
            TrailingStopTier tier = TrailingStopTier(i);
            uint256 epoch = currentEpoch[key.toId()][tier][false];
            TrailingStopPool storage pool = _trailingPools[key.toId()][tier][epoch];

            if (pool.executedToken0 > 0 || pool.totalSharesShort == 0) continue;

            // Price went above trigger -> execute
            if (currentTick >= pool.triggerTickShort) {
                _executePoolTrailingStopShort(key, tier, epoch, currentTick);
            }
        }
    }

    function _executePoolTrailingStopLong(
        PoolKey calldata key,
        TrailingStopTier tier,
        uint256 epoch,
        int24 executionTick
    ) internal {
        TrailingStopPool storage pool = _trailingPools[key.toId()][tier][epoch];

        if (pool.totalToken0Long == 0) return;

        uint256 amount0 = pool.totalToken0Long;

        // Withdraw all token0 from Aave
        uint256 withdrawn0 = _aaveWithdraw(key.currency0, amount0);

        // Execute swap: token0 -> token1
        uint256 amount1Received = _executeSwap(key, true, int256(withdrawn0));

        // Deposit token1 back to Aave for users to claim
        _aaveDeposit(key.currency1, amount1Received);

        // Mark as executed and store the received amount
        pool.executedToken1 = amount1Received;
        pool.totalToken0Long = 0;

        // Increment epoch for new deposits
        currentEpoch[key.toId()][tier][true]++;

        emit TrailingStopExecutedLong(key.toId(), tier, epoch, withdrawn0, amount1Received, executionTick);
    }

    function _executePoolTrailingStopShort(
        PoolKey calldata key,
        TrailingStopTier tier,
        uint256 epoch,
        int24 executionTick
    ) internal {
        TrailingStopPool storage pool = _trailingPools[key.toId()][tier][epoch];

        if (pool.totalToken1Short == 0) return;

        uint256 amount1 = pool.totalToken1Short;

        // Withdraw all token1 from Aave
        uint256 withdrawn1 = _aaveWithdraw(key.currency1, amount1);

        // Execute swap: token1 -> token0
        uint256 amount0Received = _executeSwap(key, false, int256(withdrawn1));

        // Deposit token0 back to Aave for users to claim
        _aaveDeposit(key.currency0, amount0Received);

        // Mark as executed and store the received amount
        pool.executedToken0 = amount0Received;
        pool.totalToken1Short = 0;

        // Increment epoch for new deposits
        currentEpoch[key.toId()][tier][false]++;

        emit TrailingStopExecutedShort(key.toId(), tier, epoch, withdrawn1, amount0Received, executionTick);
    }

    function _executeSwap(PoolKey calldata key, bool zeroForOne, int256 amountSpecified)
        internal
        returns (uint256 amountOut)
    {
        bytes memory result = poolManager.unlock(
            abi.encode(SwapCallbackData({key: key, zeroForOne: zeroForOne, amountSpecified: amountSpecified}))
        );

        amountOut = abi.decode(result, (uint256));
    }

    function _handleSwap(SwapCallbackData memory params) internal returns (bytes memory) {
        BalanceDelta delta = poolManager.swap(
            params.key,
            SwapParams({
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341
            }),
            ""
        );

        // Settle input currency
        if (params.zeroForOne) {
            _settleCurrency(params.key.currency0, uint256(int256(-delta.amount0())));
            _takeCurrency(params.key.currency1, uint256(int256(delta.amount1())));
            return abi.encode(uint256(int256(delta.amount1())));
        } else {
            _settleCurrency(params.key.currency1, uint256(int256(-delta.amount1())));
            _takeCurrency(params.key.currency0, uint256(int256(delta.amount0())));
            return abi.encode(uint256(int256(delta.amount0())));
        }
    }

    function _calculateTriggerTickLong(int24 highestTick, TrailingStopTier tier) internal pure returns (int24) {
        uint256 basisPoints = _getTierBasisPoints(tier);

        // Approximate: 1% ≈ 100 ticks (depends on tick spacing)
        int24 tickDelta = int24(int256(basisPoints / 10));

        return highestTick - tickDelta;
    }

    function _calculateTriggerTickShort(int24 lowestTick, TrailingStopTier tier) internal pure returns (int24) {
        uint256 basisPoints = _getTierBasisPoints(tier);

        // For shorts, trigger is above the lowest tick
        int24 tickDelta = int24(int256(basisPoints / 10));

        return lowestTick + tickDelta;
    }

    function _getTierBasisPoints(TrailingStopTier tier) internal pure returns (uint256) {
        if (tier == TrailingStopTier.FIVE_PERCENT) return 500;
        if (tier == TrailingStopTier.TEN_PERCENT) return 1000;
        if (tier == TrailingStopTier.FIFTEEN_PERCENT) return 1500;
        revert InvalidTier();
    }

    /* -------------------------------------------------------------------------- */
    /*                              Aave Helpers                                  */
    /* -------------------------------------------------------------------------- */

    function _aaveDeposit(Currency asset, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(Currency.unwrap(asset)).forceApprove(address(AAVE_POOL), amount);
        AAVE_POOL.supply(Currency.unwrap(asset), amount, address(this), 0);
    }

    function _aaveWithdraw(Currency asset, uint256 amount) internal returns (uint256 amountWithdrawn) {
        if (amount == 0) return 0;
        amountWithdrawn = AAVE_POOL.withdraw(Currency.unwrap(asset), amount, address(this));
    }

    function _withdrawFromAave(Currency currency, uint256 amount, address recipient) internal {
        if (amount == 0) return;
        uint256 withdrawn = _aaveWithdraw(currency, amount);
        IERC20(Currency.unwrap(currency)).safeTransfer(recipient, withdrawn);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Currency Helpers                                */
    /* -------------------------------------------------------------------------- */

    function _settleCurrency(Currency currency, uint256 amount) internal {
        if (amount > 0) {
            currency.settle(poolManager, address(this), amount, false);
        }
    }

    function _takeCurrency(Currency currency, uint256 amount) internal {
        if (amount > 0) {
            currency.take(poolManager, address(this), amount, false);
        }
    }
}
