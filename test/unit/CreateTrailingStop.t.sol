// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";

import {OntraV2HookFixture} from "./utils/FixturesV2.sol";
import {IOntraV2Hook} from "../../src/interfaces/IOntraV2Hook.sol";

contract TestCreateTrailingStop is OntraV2HookFixture {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    /* -------------------------------------------------------------------------- */
    /*                           Classic Test Cases                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Test creating a long trailing stop (token0 -> token1) with 5% tier
     * Classic case: first deposit in an empty pool
     */
    function test_createTrailingStop_longPosition_fivePercent_firstDeposit() public {
        uint256 depositAmount = 10 ether;
        IOntraV2Hook.TrailingStopTier tier = IOntraV2Hook.TrailingStopTier.FIVE_PERCENT;

        // Get current tick
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Get balances before
        uint256 userToken0Before = token0.balanceOf(address(this));
        uint256 hookAaveToken0Before = aavePool.getUserBalance(address(hookV2), address(token0));

        // Get epoch before
        uint256 epochBefore = hookV2.getCurrentEpoch(key.toId(), tier, true);

        // Create trailing stop
        vm.expectEmit(true, true, false, true);
        emit IOntraV2Hook.TrailingStopCreated(
            address(this), key.toId(), depositAmount, depositAmount, true, tier, epochBefore
        );

        uint256 shares = hookV2.createTrailingStop(key, depositAmount, true, tier);

        // Verify shares (first deposit = 1:1)
        assertEq(shares, depositAmount, "First deposit should get 1:1 shares");

        // Verify token transfer
        assertEq(
            token0.balanceOf(address(this)),
            userToken0Before - depositAmount,
            "User token0 should decrease by deposit amount"
        );

        // Verify Aave deposit
        assertEq(
            aavePool.getUserBalance(address(hookV2), address(token0)),
            hookAaveToken0Before + depositAmount,
            "Hook should have deposited tokens to Aave"
        );

        // Verify user shares
        uint256 userShares = hookV2.getUserShares(address(this), key.toId(), tier, true, epochBefore);
        assertEq(userShares, shares, "User shares should be recorded");

        // Verify pool state
        IOntraV2Hook.TrailingStopPool memory pool = hookV2.trailingPools(key.toId(), tier, epochBefore);
        assertEq(pool.totalToken0Long, depositAmount, "Pool should have correct totalToken0Long");
        assertEq(pool.totalSharesLong, shares, "Pool should have correct totalSharesLong");
        assertEq(pool.highestTickEver, currentTick, "Highest tick should be set to current tick");
        // Trigger tick should be below current tick (allowing for negative values)
        assertLe(pool.triggerTickLong, currentTick, "Trigger tick should be below or equal to current tick for 5%");
    }

    /**
     * @notice Test creating a long trailing stop with second deposit (proportional share calculation)
     */
    function test_createTrailingStop_longPosition_secondDeposit() public {
        uint256 firstDeposit = 10 ether;
        uint256 secondDeposit = 5 ether;
        IOntraV2Hook.TrailingStopTier tier = IOntraV2Hook.TrailingStopTier.TEN_PERCENT;

        // First deposit
        uint256 firstShares = hookV2.createTrailingStop(key, firstDeposit, true, tier);

        // Second deposit from another user
        address user2 = address(0x123);
        token0.mint(user2, secondDeposit);
        vm.startPrank(user2);
        token0.approve(address(hookV2), secondDeposit);

        uint256 secondShares = hookV2.createTrailingStop(key, secondDeposit, true, tier);
        vm.stopPrank();

        // Verify proportional shares
        // Second deposit should get: (5 * 10) / 10 = 5 shares
        assertEq(secondShares, (secondDeposit * firstShares) / firstDeposit, "Shares should be proportional");

        // Verify pool totals
        uint256 epoch = hookV2.getCurrentEpoch(key.toId(), tier, true);
        IOntraV2Hook.TrailingStopPool memory pool = hookV2.trailingPools(key.toId(), tier, epoch);
        assertEq(pool.totalToken0Long, firstDeposit + secondDeposit, "Total deposits should sum");
        assertEq(pool.totalSharesLong, firstShares + secondShares, "Total shares should sum");
    }

    /* -------------------------------------------------------------------------- */
    /*                        Tests with Other Token                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Test creating a short trailing stop (token1 -> token0) with 10% tier
     */
    function test_createTrailingStop_shortPosition_tenPercent_firstDeposit() public {
        uint256 depositAmount = 20 ether;
        IOntraV2Hook.TrailingStopTier tier = IOntraV2Hook.TrailingStopTier.TEN_PERCENT;

        // Get current tick
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Get balances before
        uint256 userToken1Before = token1.balanceOf(address(this));
        uint256 hookAaveToken1Before = aavePool.getUserBalance(address(hookV2), address(token1));

        // Get epoch before
        uint256 epochBefore = hookV2.getCurrentEpoch(key.toId(), tier, false);

        // Create trailing stop
        vm.expectEmit(true, true, false, true);
        emit IOntraV2Hook.TrailingStopCreated(
            address(this), key.toId(), depositAmount, depositAmount, false, tier, epochBefore
        );

        uint256 shares = hookV2.createTrailingStop(key, depositAmount, false, tier);

        // Verify shares (first deposit = 1:1)
        assertEq(shares, depositAmount, "First deposit should get 1:1 shares");

        // Verify token transfer
        assertEq(
            token1.balanceOf(address(this)),
            userToken1Before - depositAmount,
            "User token1 should decrease by deposit amount"
        );

        // Verify Aave deposit
        assertEq(
            aavePool.getUserBalance(address(hookV2), address(token1)),
            hookAaveToken1Before + depositAmount,
            "Hook should have deposited tokens to Aave"
        );

        // Verify user shares
        uint256 userShares = hookV2.getUserShares(address(this), key.toId(), tier, false, epochBefore);
        assertEq(userShares, shares, "User shares should be recorded");

        // Verify pool state for SHORT
        IOntraV2Hook.TrailingStopPool memory pool = hookV2.trailingPools(key.toId(), tier, epochBefore);
        assertEq(pool.totalToken1Short, depositAmount, "Pool should have correct totalToken1Short");
        assertEq(pool.totalSharesShort, shares, "Pool should have correct totalSharesShort");
        assertEq(pool.lowestTickEver, currentTick, "Lowest tick should be set to current tick");
        assertGe(pool.triggerTickShort, currentTick, "Trigger tick should be above or equal to current tick for shorts");
    }

    /**
     * @notice Test creating a short trailing stop with 15% tier
     */
    function test_createTrailingStop_shortPosition_fifteenPercent() public {
        uint256 depositAmount = 15 ether;
        IOntraV2Hook.TrailingStopTier tier = IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT;

        // Get current tick
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        uint256 shares = hookV2.createTrailingStop(key, depositAmount, false, tier);

        // Verify shares
        assertEq(shares, depositAmount, "First deposit should get 1:1 shares");

        // Verify pool state
        uint256 epoch = hookV2.getCurrentEpoch(key.toId(), tier, false);
        IOntraV2Hook.TrailingStopPool memory pool = hookV2.trailingPools(key.toId(), tier, epoch);
        assertEq(pool.totalToken1Short, depositAmount, "Pool should have correct totalToken1Short");
        assertEq(pool.lowestTickEver, currentTick, "Lowest tick should be initialized");

        // For 15% tier, trigger should be calculated (150 ticks above for short)
        assertGe(pool.triggerTickShort, currentTick, "Trigger tick should be above or equal to current tick for 15%");
    }

    /**
     * @notice Test mixed creation: long and short in the same pool with different tiers
     */
    function test_createTrailingStop_mixedPositions() public {
        uint256 longAmount = 10 ether;
        uint256 shortAmount = 8 ether;
        IOntraV2Hook.TrailingStopTier tier = IOntraV2Hook.TrailingStopTier.FIVE_PERCENT;

        // Create long position
        uint256 longShares = hookV2.createTrailingStop(key, longAmount, true, tier);

        // Create short position
        uint256 shortShares = hookV2.createTrailingStop(key, shortAmount, false, tier);

        // Verify independent pool states
        uint256 epoch = hookV2.getCurrentEpoch(key.toId(), tier, true);
        IOntraV2Hook.TrailingStopPool memory pool = hookV2.trailingPools(key.toId(), tier, epoch);

        assertEq(pool.totalToken0Long, longAmount, "Long pool should have token0");
        assertEq(pool.totalSharesLong, longShares, "Long shares tracked");
        assertEq(pool.totalToken1Short, shortAmount, "Short pool should have token1");
        assertEq(pool.totalSharesShort, shortShares, "Short shares tracked");
    }

    /* -------------------------------------------------------------------------- */
    /*                        Tests with expectRevert                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Test revert when amount is 0
     */
    function test_createTrailingStop_revert_zeroAmount() public {
        IOntraV2Hook.TrailingStopTier tier = IOntraV2Hook.TrailingStopTier.FIVE_PERCENT;

        vm.expectRevert("Amount must be > 0");
        hookV2.createTrailingStop(key, 0, true, tier);
    }

    /**
     * @notice Test revert when user doesn't have enough tokens
     */
    function test_createTrailingStop_revert_insufficientBalance() public {
        uint256 depositAmount = 1000 ether; // More than we have
        IOntraV2Hook.TrailingStopTier tier = IOntraV2Hook.TrailingStopTier.TEN_PERCENT;

        address poorUser = address(0x999);
        vm.startPrank(poorUser);

        // poorUser has no tokens
        vm.expectRevert();
        hookV2.createTrailingStop(key, depositAmount, true, tier);

        vm.stopPrank();
    }

    /**
     * @notice Test revert when user hasn't approved the hook
     */
    function test_createTrailingStop_revert_noApproval() public {
        uint256 depositAmount = 5 ether;
        IOntraV2Hook.TrailingStopTier tier = IOntraV2Hook.TrailingStopTier.FIVE_PERCENT;

        address user = address(0x456);
        token0.mint(user, depositAmount);

        vm.startPrank(user);
        // No approval -> should revert

        vm.expectRevert();
        hookV2.createTrailingStop(key, depositAmount, true, tier);

        vm.stopPrank();
    }

    /**
     * @notice Test revert with insufficient approval
     */
    function test_createTrailingStop_revert_insufficientApproval() public {
        uint256 depositAmount = 10 ether;
        IOntraV2Hook.TrailingStopTier tier = IOntraV2Hook.TrailingStopTier.TEN_PERCENT;

        address user = address(0x789);
        token1.mint(user, depositAmount);

        vm.startPrank(user);
        // Approve less than required amount
        token1.approve(address(hookV2), depositAmount - 1);

        vm.expectRevert();
        hookV2.createTrailingStop(key, depositAmount, false, tier);

        vm.stopPrank();
    }

    /**
     * @notice Test revert with very small amount (edge case)
     */
    function test_createTrailingStop_revert_tinyAmount() public {
        IOntraV2Hook.TrailingStopTier tier = IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT;

        // 1 wei = 0
        vm.expectRevert("Amount must be > 0");
        hookV2.createTrailingStop(key, 0, false, tier);
    }

    /* -------------------------------------------------------------------------- */
    /*                         Multiple Tiers Tests                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Test that different tiers are independent
     */
    function test_createTrailingStop_multipleTiers() public {
        uint256 amount = 10 ether;

        // Create positions in all 3 tiers
        uint256 shares5 = hookV2.createTrailingStop(key, amount, true, IOntraV2Hook.TrailingStopTier.FIVE_PERCENT);
        uint256 shares10 = hookV2.createTrailingStop(key, amount, true, IOntraV2Hook.TrailingStopTier.TEN_PERCENT);
        uint256 shares15 = hookV2.createTrailingStop(key, amount, true, IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT);

        // All should get same shares (1:1 for first deposit)
        assertEq(shares5, amount, "5% tier shares");
        assertEq(shares10, amount, "10% tier shares");
        assertEq(shares15, amount, "15% tier shares");

        // Verify each tier has independent state
        uint256 epoch = 0;
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        IOntraV2Hook.TrailingStopPool memory pool5 =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIVE_PERCENT, epoch);
        IOntraV2Hook.TrailingStopPool memory pool10 =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.TEN_PERCENT, epoch);
        IOntraV2Hook.TrailingStopPool memory pool15 =
            hookV2.trailingPools(key.toId(), IOntraV2Hook.TrailingStopTier.FIFTEEN_PERCENT, epoch);

        // Each pool should have same highestTick but different trigger ticks
        assertEq(pool5.highestTickEver, currentTick, "5% highest tick");
        assertEq(pool10.highestTickEver, currentTick, "10% highest tick");
        assertEq(pool15.highestTickEver, currentTick, "15% highest tick");

        // Trigger ticks should be progressively lower (more tolerance)
        assertLt(pool5.triggerTickLong, currentTick, "5% trigger below current");
        assertLt(pool10.triggerTickLong, pool5.triggerTickLong, "10% trigger lower than 5%");
        assertLt(pool15.triggerTickLong, pool10.triggerTickLong, "15% trigger lower than 10%");
    }
}
