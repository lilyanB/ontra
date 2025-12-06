// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {OntraV2HookFixture} from "./utils/FixturesV2.sol";
import {IOntraV2Hook} from "../../src/interfaces/IOntraV2Hook.sol";

/**
 * @title TestSwapTriggerTrailingStop
 * @notice Test suite for creating trailing stops and triggering them via large swaps
 */
contract TestSwapTriggerTrailingStop is OntraV2HookFixture {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    /* -------------------------------------------------------------------------- */
    /*                          Long Position Tests                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Test creating a long trailing stop (token0 -> token1) with 5% tier,
     *         then executing a large downward swap to trigger it
     */
    function test_longTrailingStop_triggerWithDownwardSwap_fivePercent() public {
        // Add liquidity first so the pool has depth for swaps
        // Use concentrated liquidity around current price to allow controlled price movements
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -1200, // Very wide range to handle large swaps
                tickUpper: 1200,
                liquidityDelta: int256(5000 ether), // Increased liquidity
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 depositAmount = 10 ether;

        // Get initial state
        (, int24 tickBefore,,) = manager.getSlot0(key.toId());
        uint256 epochBefore = hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, true);

        // Create long trailing stop position
        uint256 shares = hookV2.createTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT);
        assertEq(shares, depositAmount, "Shares should equal deposit amount");

        // Verify position was created
        IOntraV2Hook.TrailingStopPool memory poolBefore =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, epochBefore);
        assertEq(poolBefore.totalToken0Long, depositAmount, "Pool should have token0");
        assertEq(poolBefore.executedToken1, 0, "Pool should not be executed yet");
        // Note: highestTickEver can be 0 if current tick is 0 (pool initialized at 1:1 price)
        assertTrue(poolBefore.highestTickEver != type(int24).min, "Highest tick should be set");

        // Store initial trigger tick
        int24 triggerTick = poolBefore.triggerTickLong;
        assertTrue(triggerTick <= tickBefore, "Trigger tick should be at or below current tick");

        // Execute a downward swap (sell token0, price drops) large enough to cross trigger
        // Need to move price down by ~500 ticks (5%) from current tick
        // With more liquidity across wider range, can handle larger swaps
        swap(key, true, -300 ether, ZERO_BYTES);

        // Get tick after swap
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());

        // Verify price dropped significantly
        assertLt(tickAfter, triggerTick, "Price should have dropped below trigger");

        // Verify the trailing stop was executed
        IOntraV2Hook.TrailingStopPool memory poolAfter =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, epochBefore);
        assertEq(poolAfter.totalToken0Long, 0, "Pool token0 should be zero after execution");
        assertGt(poolAfter.executedToken1, 0, "Pool should have received token1");

        // Verify epoch was incremented
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, true),
            epochBefore + 1,
            "Epoch should be incremented"
        );

        // Verify user can withdraw token1
        uint256 token1Before = token1.balanceOf(address(this));
        uint256 amountWithdrawn =
            hookV2.withdrawTrailingStop(key, shares, true, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, epochBefore);

        assertGt(amountWithdrawn, 0, "Should withdraw token1");
        assertEq(token1.balanceOf(address(this)) - token1Before, amountWithdrawn, "Should receive token1");

        // User shares should be cleared
        assertEq(
            hookV2.getUserShares(
                address(this), key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, true, epochBefore
            ),
            0,
            "User shares should be zero"
        );
    }

    /**
     * @notice Test creating a long trailing stop (token0 -> token1) with 10% tier,
     *         then executing a large downward swap to trigger it
     */
    function test_longTrailingStop_triggerWithDownwardSwap_tenPercent() public {
        // Add liquidity first so the pool has depth for swaps
        // Need more liquidity to handle 10% price movement
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -1980, // Aligned with tickSpacing of 60 (1980 = 33 * 60)
                tickUpper: 1980,
                liquidityDelta: int256(10000 ether), // Increased liquidity
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 depositAmount = 10 ether;

        // Get initial state
        (, int24 tickBefore,,) = manager.getSlot0(key.toId());
        uint256 epochBefore = hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, true);

        // Create long trailing stop position with 10% tier
        uint256 shares = hookV2.createTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.TEN_PERCENT);
        assertEq(shares, depositAmount, "Shares should equal deposit amount");

        // Verify position was created
        IOntraV2Hook.TrailingStopPool memory poolBefore =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, epochBefore);
        assertEq(poolBefore.totalToken0Long, depositAmount, "Pool should have token0");
        assertEq(poolBefore.executedToken1, 0, "Pool should not be executed yet");
        assertTrue(poolBefore.highestTickEver != type(int24).min, "Highest tick should be set");

        // Store initial trigger tick (should be ~1000 ticks below current for 10%)
        int24 triggerTick = poolBefore.triggerTickLong;
        assertTrue(triggerTick <= tickBefore, "Trigger tick should be at or below current tick");
        assertEq(triggerTick, tickBefore - 1000, "Trigger should be 1000 ticks below (10%)");

        // Execute a downward swap large enough to cross the 10% trigger
        // Need to move price down by ~1000 ticks (10%)
        // With increased liquidity, can handle larger swaps
        swap(key, true, -800 ether, ZERO_BYTES);

        // Get tick after swap
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());

        // Verify price dropped below trigger
        assertLt(tickAfter, triggerTick, "Price should have dropped below 10% trigger");

        // Verify the trailing stop was executed
        IOntraV2Hook.TrailingStopPool memory poolAfter =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, epochBefore);
        assertEq(poolAfter.totalToken0Long, 0, "Pool token0 should be zero after execution");
        assertGt(poolAfter.executedToken1, 0, "Pool should have received token1");

        // Verify epoch was incremented
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, true),
            epochBefore + 1,
            "Epoch should be incremented"
        );

        // Verify user can withdraw token1
        uint256 token1Before = token1.balanceOf(address(this));
        uint256 amountWithdrawn =
            hookV2.withdrawTrailingStop(key, shares, true, IOntraV2Hook.TrailingStopTier.TEN_PERCENT, epochBefore);

        assertGt(amountWithdrawn, 0, "Should withdraw token1");
        assertEq(token1.balanceOf(address(this)) - token1Before, amountWithdrawn, "Should receive token1");

        // User shares should be cleared
        assertEq(
            hookV2.getUserShares(
                address(this), key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, true, epochBefore
            ),
            0,
            "User shares should be zero"
        );
    }

    /**
     * @notice Test creating multiple trailing stops (5%, 10%, 15%) and triggering all of them
     *         with a single large downward swap
     */
    function test_multipleTrailingStops_triggerAll() public {
        // Add liquidity with very wide range to handle 15% price movement
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -2940, // Aligned with tickSpacing of 60 (2940 = 49 * 60)
                tickUpper: 2940,
                liquidityDelta: int256(15000 ether), // Large liquidity for 15% move
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 depositAmount = 10 ether;

        // Get initial tick
        (, int24 tickBefore,,) = manager.getSlot0(key.toId());

        // Create trailing stop positions for all three tiers
        hookV2.createTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT);
        hookV2.createTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.TEN_PERCENT);
        hookV2.createTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT);

        // Verify all positions were created
        IOntraV2Hook.TrailingStopPool memory pool5 =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool10 =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool15 =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);

        assertEq(pool5.totalToken0Long, depositAmount, "Pool 5% should have token0");
        assertEq(pool10.totalToken0Long, depositAmount, "Pool 10% should have token0");
        assertEq(pool15.totalToken0Long, depositAmount, "Pool 15% should have token0");

        // Verify trigger ticks
        assertEq(pool5.triggerTickLong, tickBefore - 500, "5% trigger should be 500 ticks below");
        assertEq(pool10.triggerTickLong, tickBefore - 1000, "10% trigger should be 1000 ticks below");
        assertEq(pool15.triggerTickLong, tickBefore - 1500, "15% trigger should be 1500 ticks below");

        // Execute a very large downward swap to trigger all three stops
        swap(key, true, -1200 ether, ZERO_BYTES);

        // Get tick after swap
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());

        // Verify price dropped below all triggers
        assertLt(tickAfter, pool5.triggerTickLong, "Price should be below 5% trigger");
        assertLt(tickAfter, pool10.triggerTickLong, "Price should be below 10% trigger");
        assertLt(tickAfter, pool15.triggerTickLong, "Price should be below 15% trigger");

        // Verify all three trailing stops were executed
        pool5 = hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        pool10 = hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0);
        pool15 = hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);

        assertEq(pool5.totalToken0Long, 0, "Pool 5% token0 should be zero");
        assertEq(pool10.totalToken0Long, 0, "Pool 10% token0 should be zero");
        assertEq(pool15.totalToken0Long, 0, "Pool 15% token0 should be zero");

        assertGt(pool5.executedToken1, 0, "Pool 5% should have received token1");
        assertGt(pool10.executedToken1, 0, "Pool 10% should have received token1");
        assertGt(pool15.executedToken1, 0, "Pool 15% should have received token1");

        // Verify all epochs were incremented
        assertEq(hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, true), 1, "Epoch 5%");
        assertEq(hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, true), 1, "Epoch 10%");
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, true), 1, "Epoch 15%"
        );

        // Withdraw swapped token1 from all three tiers
        uint256 token1BalanceBefore = token1.balanceOf(address(this));

        hookV2.withdrawTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        uint256 withdrawn5 = token1.balanceOf(address(this)) - token1BalanceBefore;

        hookV2.withdrawTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0);
        uint256 withdrawn10 = token1.balanceOf(address(this)) - token1BalanceBefore - withdrawn5;

        hookV2.withdrawTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);
        uint256 totalWithdrawn = token1.balanceOf(address(this)) - token1BalanceBefore;

        // Verify total withdrawn matches sum of executed amounts
        assertEq(
            totalWithdrawn,
            pool5.executedToken1 + pool10.executedToken1 + pool15.executedToken1,
            "Total withdrawn should match"
        );
        assertEq(withdrawn5, pool5.executedToken1, "5% withdrawn should match executed");
        assertEq(withdrawn10, pool10.executedToken1, "10% withdrawn should match executed");
        assertEq(
            totalWithdrawn - withdrawn5 - withdrawn10, pool15.executedToken1, "15% withdrawn should match executed"
        );

        // Verify shares are cleared
        assertEq(
            hookV2.getUserShares(address(this), key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, true, 0),
            0,
            "Shares 5% should be zero"
        );
        assertEq(
            hookV2.getUserShares(address(this), key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, true, 0),
            0,
            "Shares 10% should be zero"
        );
        assertEq(
            hookV2.getUserShares(address(this), key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, true, 0),
            0,
            "Shares 15% should be zero"
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                            Short Position Tests                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Test creating a short trailing stop (token1 -> token0) with 5% tier,
     *         then executing a large upward swap to trigger it
     */
    function test_shortTrailingStop_triggerWithUpwardSwap_fivePercent() public {
        // Add liquidity first so the pool has depth for swaps
        // Use concentrated liquidity around current price to allow controlled price movements
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -1200, // Very wide range to handle large swaps
                tickUpper: 1200,
                liquidityDelta: int256(5000 ether), // Increased liquidity
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 depositAmount = 10 ether;

        uint256 epochBefore = hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, false);

        // Create short trailing stop position
        uint256 shares =
            hookV2.createTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT);
        assertEq(shares, depositAmount, "Shares should equal deposit amount");

        // Verify position was created
        IOntraV2Hook.TrailingStopPool memory poolBefore =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, epochBefore);
        assertEq(poolBefore.totalToken1Short, depositAmount, "Pool should have token1");
        assertEq(poolBefore.executedToken0, 0, "Pool should not be executed yet");
        assertTrue(poolBefore.lowestTickEver != type(int24).max, "Lowest tick should be set");

        // Store initial trigger tick (will be based on lowestTickEver)
        int24 triggerTick = poolBefore.triggerTickShort;

        // Execute an upward swap (sell token1, price rises) large enough to cross trigger
        // Need to move price up by ~500 ticks (5%) from current tick
        swap(key, false, -300 ether, ZERO_BYTES);

        // Get tick after swap
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());

        // Verify price rose significantly
        assertGt(tickAfter, triggerTick, "Price should have risen above trigger");

        // Verify the trailing stop was executed
        IOntraV2Hook.TrailingStopPool memory poolAfter =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, epochBefore);
        assertEq(poolAfter.totalToken1Short, 0, "Pool token1 should be zero after execution");
        assertGt(poolAfter.executedToken0, 0, "Pool should have received token0");

        // Verify epoch was incremented
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, false),
            epochBefore + 1,
            "Epoch should be incremented"
        );

        // Verify user can withdraw token0
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 amountWithdrawn =
            hookV2.withdrawTrailingStop(key, shares, false, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, epochBefore);

        assertGt(amountWithdrawn, 0, "Should withdraw token0");
        assertEq(token0.balanceOf(address(this)) - token0Before, amountWithdrawn, "Should receive token0");

        // User shares should be cleared
        assertEq(
            hookV2.getUserShares(
                address(this), key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, false, epochBefore
            ),
            0,
            "User shares should be zero"
        );
    }

    /**
     * @notice Test creating a short trailing stop (token1 -> token0) with 10% tier,
     *         then executing a large upward swap to trigger it
     */
    function test_shortTrailingStop_triggerWithUpwardSwap_tenPercent() public {
        // Add liquidity first so the pool has depth for swaps
        // Need more liquidity to handle 10% price movement
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -1980, // Aligned with tickSpacing of 60 (1980 = 33 * 60)
                tickUpper: 1980,
                liquidityDelta: int256(10000 ether), // Increased liquidity
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 depositAmount = 10 ether;

        uint256 epochBefore = hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, false);

        // Create short trailing stop position with 10% tier
        uint256 shares = hookV2.createTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.TEN_PERCENT);
        assertEq(shares, depositAmount, "Shares should equal deposit amount");

        // Verify position was created
        IOntraV2Hook.TrailingStopPool memory poolBefore =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, epochBefore);
        assertEq(poolBefore.totalToken1Short, depositAmount, "Pool should have token1");
        assertEq(poolBefore.executedToken0, 0, "Pool should not be executed yet");
        assertTrue(poolBefore.lowestTickEver != type(int24).max, "Lowest tick should be set");

        // Store initial trigger tick (will be based on lowestTickEver)
        int24 triggerTick = poolBefore.triggerTickShort;

        // Execute an upward swap large enough to cross the 10% trigger
        // Need to move price up by ~1000 ticks (10%)
        swap(key, false, -800 ether, ZERO_BYTES);

        // Get tick after swap
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());

        // Verify price rose above trigger
        assertGt(tickAfter, triggerTick, "Price should have risen above 10% trigger");

        // Verify the trailing stop was executed
        IOntraV2Hook.TrailingStopPool memory poolAfter =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, epochBefore);
        assertEq(poolAfter.totalToken1Short, 0, "Pool token1 should be zero after execution");
        assertGt(poolAfter.executedToken0, 0, "Pool should have received token0");

        // Verify epoch was incremented
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, false),
            epochBefore + 1,
            "Epoch should be incremented"
        );

        // Verify user can withdraw token0
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 amountWithdrawn =
            hookV2.withdrawTrailingStop(key, shares, false, IOntraV2Hook.TrailingStopTier.TEN_PERCENT, epochBefore);

        assertGt(amountWithdrawn, 0, "Should withdraw token0");
        assertEq(token0.balanceOf(address(this)) - token0Before, amountWithdrawn, "Should receive token0");

        // User shares should be cleared
        assertEq(
            hookV2.getUserShares(
                address(this), key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, false, epochBefore
            ),
            0,
            "User shares should be zero"
        );
    }

    /**
     * @notice Test creating multiple short trailing stops (5%, 10%, 15%) and triggering all of them
     *         with a single large upward swap
     */
    function test_multipleShortTrailingStops_triggerAll() public {
        // Add liquidity with very wide range to handle 15% price movement
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -2940, // Aligned with tickSpacing of 60 (2940 = 49 * 60)
                tickUpper: 2940,
                liquidityDelta: int256(15000 ether), // Large liquidity for 15% move
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 depositAmount = 10 ether;

        // Create trailing stop positions for all three tiers
        hookV2.createTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT);
        hookV2.createTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.TEN_PERCENT);
        hookV2.createTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT);

        // Verify all positions were created
        IOntraV2Hook.TrailingStopPool memory pool5 =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool10 =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool15 =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);

        assertEq(pool5.totalToken1Short, depositAmount, "Pool 5% should have token1");
        assertEq(pool10.totalToken1Short, depositAmount, "Pool 10% should have token1");
        assertEq(pool15.totalToken1Short, depositAmount, "Pool 15% should have token1");

        // Store trigger ticks (will be based on lowestTickEver)
        int24 trigger5 = pool5.triggerTickShort;
        int24 trigger10 = pool10.triggerTickShort;
        int24 trigger15 = pool15.triggerTickShort;

        // Execute a very large upward swap to trigger all three stops
        swap(key, false, -1200 ether, ZERO_BYTES);

        // Get tick after swap
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());

        // Verify price rose above all triggers
        assertGt(tickAfter, trigger5, "Price should be above 5% trigger");
        assertGt(tickAfter, trigger10, "Price should be above 10% trigger");
        assertGt(tickAfter, trigger15, "Price should be above 15% trigger");

        // Verify all three trailing stops were executed
        pool5 = hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        pool10 = hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0);
        pool15 = hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);

        assertEq(pool5.totalToken1Short, 0, "Pool 5% token1 should be zero");
        assertEq(pool10.totalToken1Short, 0, "Pool 10% token1 should be zero");
        assertEq(pool15.totalToken1Short, 0, "Pool 15% token1 should be zero");

        assertGt(pool5.executedToken0, 0, "Pool 5% should have received token0");
        assertGt(pool10.executedToken0, 0, "Pool 10% should have received token0");
        assertGt(pool15.executedToken0, 0, "Pool 15% should have received token0");

        // Verify all epochs were incremented
        assertEq(hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, false), 1, "Epoch 5%");
        assertEq(hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, false), 1, "Epoch 10%");
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, false), 1, "Epoch 15%"
        );

        // Withdraw swapped token0 from all three tiers
        uint256 token0BalanceBefore = token0.balanceOf(address(this));

        hookV2.withdrawTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        uint256 withdrawn5 = token0.balanceOf(address(this)) - token0BalanceBefore;

        hookV2.withdrawTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0);
        uint256 withdrawn10 = token0.balanceOf(address(this)) - token0BalanceBefore - withdrawn5;

        hookV2.withdrawTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);
        uint256 totalWithdrawn = token0.balanceOf(address(this)) - token0BalanceBefore;

        // Verify total withdrawn matches sum of executed amounts
        assertEq(
            totalWithdrawn,
            pool5.executedToken0 + pool10.executedToken0 + pool15.executedToken0,
            "Total withdrawn should match"
        );
        assertEq(withdrawn5, pool5.executedToken0, "5% withdrawn should match executed");
        assertEq(withdrawn10, pool10.executedToken0, "10% withdrawn should match executed");
        assertEq(
            totalWithdrawn - withdrawn5 - withdrawn10, pool15.executedToken0, "15% withdrawn should match executed"
        );

        // Verify shares are cleared
        assertEq(
            hookV2.getUserShares(address(this), key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, false, 0),
            0,
            "Shares 5% should be zero"
        );
        assertEq(
            hookV2.getUserShares(address(this), key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, false, 0),
            0,
            "Shares 10% should be zero"
        );
        assertEq(
            hookV2.getUserShares(address(this), key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, false, 0),
            0,
            "Shares 15% should be zero"
        );
    }
}
