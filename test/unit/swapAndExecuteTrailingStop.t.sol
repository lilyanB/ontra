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
        // Much larger liquidity to prevent extreme price movements
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -600, // Wider range
                tickUpper: 600,
                liquidityDelta: int256(10000 ether),
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
        // With the liquidity we added, need significant amount to move price
        // Larger amount to cross the -50 tick trigger
        swap(key, true, -100 ether, ZERO_BYTES);

        // Get tick after swap
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());

        // Verify price dropped significantly
        assertLt(tickAfter, triggerTick, "Price should have dropped below trigger");

        // // Manually execute trailing stop (no longer automatic)
        // hookV2.executeTrailingStops(key, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT);

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
}
