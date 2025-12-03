// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {OntraHookFixture} from "./utils/Fixtures.sol";

contract TestRemoveLiquidity is OntraHookFixture {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    /**
     * @notice Test removing liquidity within current tick range (liquidity is idle)
     * When liquidity is in range, it's not in Aave, so removal should work directly
     */
    function test_removeLiquidity_withinCurrentTickRange() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity within current tick range using the hook
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        uint256 amount0Desired = 10 ether;
        uint256 amount1Desired = 10 ether;

        uint256 token0BalanceBeforeDeposit = token0.balanceOf(address(this));
        uint256 token1BalanceBeforeDeposit = token1.balanceOf(address(this));

        uint128 liquidityAdded = hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        uint256 expectedAmount0;
        uint256 expectedAmount1;
        {
            // Calculate expected amounts based on liquidity added
            uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(tickLower);
            uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(tickUpper);
            (, int24 tick,,) = manager.getSlot0(key.toId());
            uint160 sqrtPriceX96Current = TickMath.getSqrtPriceAtTick(tick);

            // Calculate expected amounts for the liquidity added
            (expectedAmount0, expectedAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96Current, sqrtPriceX96Lower, sqrtPriceX96Upper, liquidityAdded
            );
        }

        uint256 token0BalanceBefore = token0.balanceOf(address(this));
        uint256 token1BalanceBefore = token1.balanceOf(address(this));

        (uint256 amount0Withdrawn, uint256 amount1Withdrawn) =
            hook.removeLiquidity(key, tickLower, tickUpper, liquidityAdded);

        // Verify exact amounts withdrawn match expected amounts
        assertEq(amount0Withdrawn, expectedAmount0, "Token0 withdrawn amount mismatch");
        assertEq(amount1Withdrawn, expectedAmount1, "Token1 withdrawn amount mismatch");

        // Verify balance changes match withdrawn amounts
        assertEq(
            token0.balanceOf(address(this)) - token0BalanceBefore, expectedAmount0, "Token0 balance change mismatch"
        );
        assertEq(
            token1.balanceOf(address(this)) - token1BalanceBefore, expectedAmount1, "Token1 balance change mismatch"
        );

        // Since tick hasn't moved, we should get back approximately the same amounts we deposited
        // Allow for small rounding errors (1-2 wei) due to liquidity calculations
        assertApproxEqAbs(
            token0.balanceOf(address(this)),
            token0BalanceBeforeDeposit,
            2,
            "Token0 final balance should match initial balance"
        );
        assertApproxEqAbs(
            token1.balanceOf(address(this)),
            token1BalanceBeforeDeposit,
            2,
            "Token1 final balance should match initial balance"
        );
    }

    /**
     * @notice Test removing partial liquidity from pool
     */
    function test_removeLiquidity_partial() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity within current tick range
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        uint256 amount0Desired = 100 ether;
        uint256 amount1Desired = 100 ether;

        uint128 liquidityAdded = hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        uint256 token0BalanceBefore = token0.balanceOf(address(this));
        uint256 token1BalanceBefore = token1.balanceOf(address(this));

        // Remove half the liquidity
        uint128 liquidityToRemove = liquidityAdded / 2;
        (uint256 amount0Withdrawn, uint256 amount1Withdrawn) =
            hook.removeLiquidity(key, tickLower, tickUpper, liquidityToRemove);

        // Verify amounts were withdrawn
        assertGt(amount0Withdrawn, 0, "Should withdraw some token0");
        assertGt(amount1Withdrawn, 0, "Should withdraw some token1");

        // Verify balance changes
        assertEq(
            token0.balanceOf(address(this)) - token0BalanceBefore, amount0Withdrawn, "Token0 balance should increase"
        );
        assertEq(
            token1.balanceOf(address(this)) - token1BalanceBefore, amount1Withdrawn, "Token1 balance should increase"
        );
    }

    /**
     * @notice Test that removing liquidity from Aave position reverts
     */
    function test_removeLiquidity_revertsIfOnAave() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick (goes to Aave)
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        hook.addLiquidity(key, tickLower, tickUpper, 0, 100 ether);

        // Try to remove liquidity - should revert because it's on Aave, not in pool
        vm.expectRevert();
        hook.removeLiquidity(key, tickLower, tickUpper, 1);
    }

    /**
     * @notice Test that removing more liquidity than available reverts
     */
    function test_removeLiquidity_revertsIfNotEnough() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity within current tick range
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        uint128 liquidityAdded = hook.addLiquidity(key, tickLower, tickUpper, 10 ether, 10 ether);

        // Try to remove more than available
        vm.expectRevert();
        hook.removeLiquidity(key, tickLower, tickUpper, liquidityAdded + 1);
    }

    /**
     * @notice Test that removing from non-existent position reverts
     */
    function test_removeLiquidity_revertsIfNoPosition() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        // Try to remove without adding first
        vm.expectRevert();
        hook.removeLiquidity(key, tickLower, tickUpper, 1);
    }
}
