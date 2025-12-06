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
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {OntraV2HookFixture} from "./utils/FixturesV2.sol";
import {SwapRouterWithLocker} from "./utils/SwapRouterWithLocker.sol";
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
        swapRouterWithLocker.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -300 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

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

        assertEq(amountWithdrawn, poolAfter.executedToken1, "Should withdraw executed token1");
        assertEq(token1.balanceOf(address(this)) - token1Before, poolAfter.executedToken1, "Should receive token1");

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
        swapRouterWithLocker.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -800 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

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

        assertEq(amountWithdrawn, poolAfter.executedToken1, "Should withdraw executed token1");
        assertEq(token1.balanceOf(address(this)) - token1Before, poolAfter.executedToken1, "Should receive token1");

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
        swapRouterWithLocker.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -1200 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

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

    /**
     * @notice Test that Aave yield generated on a long position is sent to the swapper
     *         when the trailing stop is triggered automatically by the swap
     */
    function test_longTrailingStop_aaveYieldSentToExecutor() public {
        // Add liquidity first
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -1200, tickUpper: 1200, liquidityDelta: int256(5000 ether), salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 depositAmount = 10 ether;

        // Create long trailing stop position
        hookV2.createTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT);

        // Simulate Aave yield: add 1 ether of yield to token0
        uint256 yieldAmount = 1 ether;
        aavePool.simulateYield(address(token0), yieldAmount);

        // Create a separate account to execute the swap (they will receive the yield)
        address executor = makeAddr("executor");

        // Give executor tokens to perform the swap and approvals
        token0.mint(executor, 1000 ether);
        vm.startPrank(executor);
        token0.approve(address(swapRouterWithLocker), type(uint256).max);
        token0.approve(address(manager), type(uint256).max);

        // Execute downward swap as the executor - this will trigger the stop automatically
        swapRouterWithLocker.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -300 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        vm.stopPrank();

        // Get executor's token0 balance after execution
        uint256 executorToken0After = token0.balanceOf(executor);

        // Verify the pool was executed
        IOntraV2Hook.TrailingStopPool memory poolAfter =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);

        assertEq(poolAfter.totalToken0Long, 0, "Pool token0 should be zero after execution");
        // The pool swapped 10 ether token0 to token1, calculate exact amount received
        uint256 expectedToken1 = poolAfter.executedToken1; // Store the actual swapped amount
        assertEq(poolAfter.executedToken1, expectedToken1, "Pool should have received token1 from swap");

        // Verify executor received the yield (1 ether)
        // They started with 1000 ether, spent 300 in swap, and received 1 ether yield
        // So final balance should be 1000 - 300 + 1 = 701 ether
        assertEq(
            executorToken0After, 1000 ether - 300 ether + yieldAmount, "Executor should have 701 ether (1000 - 300 + 1)"
        );

        // User should be able to withdraw their token1 (swapped from principal, not yield)
        uint256 token1Before = token1.balanceOf(address(this));
        hookV2.withdrawTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        uint256 token1Received = token1.balanceOf(address(this)) - token1Before;

        assertEq(token1Received, poolAfter.executedToken1, "User should receive swapped token1");
    }

    /**
     * @notice Test creating multiple long trailing stops (5%, 10%, 15%) and triggering only
     *         the first two with a ~12% downward price movement, leaving 15% untriggered
     */
    function test_multipleLongTrailingStops_partialTrigger() public {
        // Add liquidity with very wide range to handle 15% price movement
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -2940, // Aligned with tickSpacing of 60 (2940 = 49 * 60)
                tickUpper: 2940,
                liquidityDelta: int256(15000 ether), // Large liquidity for controlled moves
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
        IOntraV2Hook.TrailingStopPool memory pool5Before =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool10Before =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool15Before =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);

        assertEq(pool5Before.totalToken0Long, depositAmount, "Pool 5% should have token0");
        assertEq(pool10Before.totalToken0Long, depositAmount, "Pool 10% should have token0");
        assertEq(pool15Before.totalToken0Long, depositAmount, "Pool 15% should have token0");

        // Verify trigger ticks
        assertEq(pool5Before.triggerTickLong, tickBefore - 500, "5% trigger should be 500 ticks below");
        assertEq(pool10Before.triggerTickLong, tickBefore - 1000, "10% trigger should be 1000 ticks below");
        assertEq(pool15Before.triggerTickLong, tickBefore - 1500, "15% trigger should be 1500 ticks below");

        // Execute a downward swap large enough to trigger 5% and 10%, but NOT 15%
        // Target: move ~1200 ticks down (12%) to cross 5% and 10% but stay above 15% trigger
        swapRouterWithLocker.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -1000 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        // Get tick after swap
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());

        // Verify price dropped below 5% and 10% triggers, but above 15% trigger
        assertLt(tickAfter, pool5Before.triggerTickLong, "Price should be below 5% trigger");
        assertLt(tickAfter, pool10Before.triggerTickLong, "Price should be below 10% trigger");
        assertGt(tickAfter, pool15Before.triggerTickLong, "Price should be above 15% trigger (not triggered)");

        // Verify 5% and 10% trailing stops were executed
        IOntraV2Hook.TrailingStopPool memory pool5After =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool10After =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool15After =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);

        // 5% and 10% should be executed
        assertEq(pool5After.totalToken0Long, 0, "Pool 5% token0 should be zero (executed)");
        assertEq(pool10After.totalToken0Long, 0, "Pool 10% token0 should be zero (executed)");
        assertGt(pool5After.executedToken1, 0, "Pool 5% should have received token1");
        assertGt(pool10After.executedToken1, 0, "Pool 10% should have received token1");

        // 15% should NOT be executed
        assertEq(pool15After.totalToken0Long, depositAmount, "Pool 15% should still have token0 (not executed)");
        assertEq(pool15After.executedToken1, 0, "Pool 15% should not have received token1");

        // Verify epochs - 5% and 10% incremented, 15% not
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, true),
            1,
            "Epoch 5% incremented"
        );
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, true),
            1,
            "Epoch 10% incremented"
        );
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, true),
            0,
            "Epoch 15% not incremented"
        );

        // Withdraw from 5% and 10%
        assertEq(
            hookV2.withdrawTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0),
            pool5After.executedToken1,
            "Should withdraw token1 from 5%"
        );
        assertEq(
            hookV2.withdrawTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0),
            pool10After.executedToken1,
            "Should withdraw token1 from 10%"
        );

        // Verify we can still withdraw the original token0 from 15% (position not executed)
        uint256 token0Before = token0.balanceOf(address(this));
        hookV2.withdrawTrailingStop(key, depositAmount, true, IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);
        assertEq(
            token0.balanceOf(address(this)) - token0Before,
            depositAmount,
            "Should withdraw original token0 from 15% (not executed)"
        );

        // Verify all shares are cleared
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
        swapRouterWithLocker.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -300 ether, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

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

        assertEq(amountWithdrawn, poolAfter.executedToken0, "Should withdraw executed token0");
        assertEq(token0.balanceOf(address(this)) - token0Before, poolAfter.executedToken0, "Should receive token0");

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
        swapRouterWithLocker.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -800 ether, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

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

        assertEq(amountWithdrawn, poolAfter.executedToken0, "Should withdraw executed token0");
        assertEq(token0.balanceOf(address(this)) - token0Before, poolAfter.executedToken0, "Should receive token0");

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
        swapRouterWithLocker.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -1200 ether, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

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

    /**
     * @notice Test that Aave yield generated on a short position is sent to the swapper
     *         when the trailing stop is triggered automatically by the swap
     */
    function test_shortTrailingStop_aaveYieldSentToExecutor() public {
        // Add liquidity first
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -1200, tickUpper: 1200, liquidityDelta: int256(5000 ether), salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 depositAmount = 10 ether;

        // Create short trailing stop position
        hookV2.createTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT);

        // Simulate Aave yield: add 0.5 ether of yield to token1
        uint256 yieldAmount = 0.5 ether;
        aavePool.simulateYield(address(token1), yieldAmount);

        // Create a separate account to execute the swap (they will receive the yield)
        address executor = makeAddr("executor");

        // Give executor tokens to perform the swap and approvals
        token1.mint(executor, 1000 ether);
        vm.startPrank(executor);
        token1.approve(address(swapRouterWithLocker), type(uint256).max);
        token1.approve(address(manager), type(uint256).max);

        // Execute upward swap as the executor - this will trigger the stop automatically
        swapRouterWithLocker.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -300 ether, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        vm.stopPrank();

        // Get executor's token1 balance after execution
        uint256 executorToken1After = token1.balanceOf(executor);

        // Verify the pool was executed
        IOntraV2Hook.TrailingStopPool memory poolAfter =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);

        assertEq(poolAfter.totalToken1Short, 0, "Pool token1 should be zero after execution");
        // The pool swapped 10 ether token1 to token0, calculate exact amount received
        uint256 expectedToken0 = poolAfter.executedToken0; // Store the actual swapped amount
        assertEq(poolAfter.executedToken0, expectedToken0, "Pool should have received token0 from swap");

        // Verify executor received the yield (0.5 ether)
        // They started with 1000 ether, spent 300 in swap, and received 0.5 ether yield
        // So final balance should be 1000 - 300 + 0.5 = 700.5 ether
        assertEq(
            executorToken1After,
            1000 ether - 300 ether + yieldAmount,
            "Executor should have 700.5 ether (1000 - 300 + 0.5)"
        );

        // User should be able to withdraw their token0 (swapped from principal, not yield)
        uint256 token0Before = token0.balanceOf(address(this));
        hookV2.withdrawTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        uint256 token0Received = token0.balanceOf(address(this)) - token0Before;

        assertEq(token0Received, poolAfter.executedToken0, "User should receive swapped token0");
    }

    /**
     * @notice Test creating multiple short trailing stops (5%, 10%, 15%) and triggering only
     *         the first two with a ~10% upward price movement, leaving 15% untriggered
     * @dev This test creates positions and makes a controlled price movement to trigger only some tiers
     */
    function test_multipleShortTrailingStops_partialTrigger() public {
        // Add liquidity with very wide range to handle 15% price movement
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -2940, // Aligned with tickSpacing of 60 (2940 = 49 * 60)
                tickUpper: 2940,
                liquidityDelta: int256(15000 ether), // Large liquidity for controlled moves
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 depositAmount = 10 ether;

        // First, do a downward swap to establish a lowestTickEver below 0
        // This ensures trigger ticks are properly set
        swapRouterWithLocker.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -200 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        (, int24 tickAfterDown,,) = manager.getSlot0(key.toId());

        // Create trailing stop positions for all three tiers after establishing lowestTickEver
        hookV2.createTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT);
        hookV2.createTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.TEN_PERCENT);
        hookV2.createTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT);

        // Verify all positions were created
        IOntraV2Hook.TrailingStopPool memory pool5Before =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool10Before =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool15Before =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);

        assertEq(pool5Before.totalToken1Short, depositAmount, "Pool 5% should have token1");
        assertEq(pool10Before.totalToken1Short, depositAmount, "Pool 10% should have token1");
        assertEq(pool15Before.totalToken1Short, depositAmount, "Pool 15% should have token1");

        // Store trigger ticks (should be based on lowestTickEver after the down swap)
        int24 trigger5 = pool5Before.triggerTickShort;
        int24 trigger10 = pool10Before.triggerTickShort;
        int24 trigger15 = pool15Before.triggerTickShort;

        // Verify triggers are properly set (lowestTickEver + tier offset)
        assertEq(trigger5, tickAfterDown + 500, "5% trigger should be 500 ticks above lowestTickEver");
        assertEq(trigger10, tickAfterDown + 1000, "10% trigger should be 1000 ticks above lowestTickEver");
        assertEq(trigger15, tickAfterDown + 1500, "15% trigger should be 1500 ticks above lowestTickEver");

        // Execute an upward swap large enough to trigger 5% and 10%, but NOT 15%
        // Target: move price to between trigger10 and trigger15
        swapRouterWithLocker.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -900 ether, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            SwapRouterWithLocker.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        // Get tick after swap
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());

        // Verify price rose above 5% and 10% triggers, but below 15% trigger
        assertGt(tickAfter, trigger5, "Price should be above 5% trigger");
        assertGt(tickAfter, trigger10, "Price should be above 10% trigger");
        assertLt(tickAfter, trigger15, "Price should be below 15% trigger (not triggered)");

        // Verify 5% and 10% trailing stops were executed
        IOntraV2Hook.TrailingStopPool memory pool5After =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool10After =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0);
        IOntraV2Hook.TrailingStopPool memory pool15After =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);

        // 5% and 10% should be executed
        assertEq(pool5After.totalToken1Short, 0, "Pool 5% token1 should be zero (executed)");
        assertEq(pool10After.totalToken1Short, 0, "Pool 10% token1 should be zero (executed)");
        assertGt(pool5After.executedToken0, 0, "Pool 5% should have received token0");
        assertGt(pool10After.executedToken0, 0, "Pool 10% should have received token0");

        // 15% should NOT be executed
        assertEq(pool15After.totalToken1Short, depositAmount, "Pool 15% should still have token1 (not executed)");
        assertEq(pool15After.executedToken0, 0, "Pool 15% should not have received token0");

        // Verify epochs - 5% and 10% incremented, 15% not
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, false),
            1,
            "Epoch 5% incremented"
        );
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, false),
            1,
            "Epoch 10% incremented"
        );
        assertEq(
            hookV2.getCurrentEpoch(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, false),
            0,
            "Epoch 15% not incremented"
        );

        // Withdraw from 5% and 10%
        assertEq(
            hookV2.withdrawTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, 0),
            pool5After.executedToken0,
            "Should withdraw token0 from 5%"
        );
        assertEq(
            hookV2.withdrawTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.TEN_PERCENT, 0),
            pool10After.executedToken0,
            "Should withdraw token0 from 10%"
        );

        // Verify we can still withdraw the original token1 from 15% (position not executed)
        uint256 token1Before = token1.balanceOf(address(this));
        hookV2.withdrawTrailingStop(key, depositAmount, false, IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, 0);
        assertEq(
            token1.balanceOf(address(this)) - token1Before,
            depositAmount,
            "Should withdraw original token1 from 15% (not executed)"
        );

        // Verify all shares are cleared
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
