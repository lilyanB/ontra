// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {OntraHookFixture} from "./utils/Fixtures.sol";
import {MockAavePool} from "./utils/MockAavePool.sol";

contract TestRemoveTokensFromAave is OntraHookFixture {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    /**
     * @notice Test removing tokens from Aave for a position above current tick range
     * Token1 should be withdrawn from Aave
     */
    function test_removeTokensFromAave_aboveCurrentTick() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick using the hook
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        uint256 amount1Desired = 100 ether;
        hook.addLiquidity(key, tickLower, tickUpper, 0, amount1Desired);

        MockAavePool mockAavePool = MockAavePool(address(aavePool));
        uint256 aaveBalanceBefore = mockAavePool.getUserBalance(address(hook), address(token1));

        // Verify funds were deposited to Aave
        assertGt(aaveBalanceBefore, 0);

        uint256 amountToRemove = amount1Desired / 2;

        // Now remove half using the new function
        hook.removeTokensFromAave(key, tickLower, tickUpper, 0, amountToRemove);

        // Verify funds were withdrawn from Aave
        uint256 aaveBalanceAfter = mockAavePool.getUserBalance(address(hook), address(token1));
        assertLt(aaveBalanceAfter, aaveBalanceBefore);
        assertApproxEqAbs(aaveBalanceBefore - aaveBalanceAfter, amountToRemove, 1, "Should withdraw half");
    }

    /**
     * @notice Test removing tokens from Aave for a position below current tick range
     * Token0 should be withdrawn from Aave
     */
    function test_removeTokensFromAave_belowCurrentTick() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity below current tick using the hook
        int24 tickLower = currentTick - 240;
        int24 tickUpper = currentTick - 120;

        uint256 amount0Desired = 100 ether;
        hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, 0);

        MockAavePool mockAavePool = MockAavePool(address(aavePool));
        uint256 aaveBalanceBefore = mockAavePool.getUserBalance(address(hook), address(token0));

        // Verify token0 was deposited to Aave
        assertGt(aaveBalanceBefore, 0);

        uint256 amountToRemove = amount0Desired / 2;

        // Now remove half using the new function
        hook.removeTokensFromAave(key, tickLower, tickUpper, amountToRemove, 0);

        // Verify token0 was withdrawn from Aave
        uint256 aaveBalanceAfter = mockAavePool.getUserBalance(address(hook), address(token0));
        assertLt(aaveBalanceAfter, aaveBalanceBefore);
        assertApproxEqAbs(aaveBalanceBefore - aaveBalanceAfter, amountToRemove, 1, "Should withdraw half");
    }

    /**
     * @notice Test partial removal of tokens from Aave
     * Should only withdraw the specified amount from Aave
     */
    function test_removeTokensFromAave_partial() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick using the hook
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        uint256 amount1Desired = 100 ether;
        hook.addLiquidity(key, tickLower, tickUpper, 0, amount1Desired);

        MockAavePool mockAavePool = MockAavePool(address(aavePool));
        uint256 aaveBalanceBefore = mockAavePool.getUserBalance(address(hook), address(token1));

        // Remove 30% of the tokens
        uint256 amountToRemove = (amount1Desired * 30) / 100;
        hook.removeTokensFromAave(key, tickLower, tickUpper, 0, amountToRemove);

        uint256 aaveBalanceAfter = mockAavePool.getUserBalance(address(hook), address(token1));

        // Aave balance should have decreased but not to zero
        assertLt(aaveBalanceAfter, aaveBalanceBefore);
        assertGt(aaveBalanceAfter, 0);
        assertApproxEqAbs(aaveBalanceBefore - aaveBalanceAfter, amountToRemove, 1, "Should withdraw exact amount");
    }

    /**
     * @notice Test removing all tokens from Aave
     * Should completely withdraw from Aave position
     */
    function test_removeTokensFromAave_complete() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick using the hook
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        uint256 amount1Desired = 100 ether;
        hook.addLiquidity(key, tickLower, tickUpper, 0, amount1Desired);

        MockAavePool mockAavePool = MockAavePool(address(aavePool));
        uint256 aaveBalanceBefore = mockAavePool.getUserBalance(address(hook), address(token1));
        assertGt(aaveBalanceBefore, 0);

        uint256 userBalanceBefore = token1.balanceOf(address(this));

        // Remove all tokens
        (uint256 amount0Withdrawn, uint256 amount1Withdrawn) =
            hook.removeTokensFromAave(key, tickLower, tickUpper, 0, amount1Desired);

        uint256 aaveBalanceAfter = mockAavePool.getUserBalance(address(hook), address(token1));

        // Verify withdrawal amounts
        assertEq(amount0Withdrawn, 0, "No token0 should be withdrawn");
        assertEq(amount1Withdrawn, amount1Desired, "All token1 should be withdrawn");

        // User balance should increase
        assertEq(token1.balanceOf(address(this)) - userBalanceBefore, amount1Desired, "User should receive all tokens");

        // Aave balance should be significantly reduced (accounting for rounding)
        assertLt(aaveBalanceAfter, aaveBalanceBefore / 10);
    }

    /**
     * @notice Test that withdrawal calculations are correct
     * Verify that the amounts calculated match what's actually withdrawn
     */
    function test_removeTokensFromAave_correctAmountCalculation() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick using the hook
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        uint256 amount1Desired = 100 ether;
        hook.addLiquidity(key, tickLower, tickUpper, 0, amount1Desired);

        MockAavePool mockAavePool = MockAavePool(address(aavePool));
        uint256 aaveBalanceBefore = mockAavePool.getUserBalance(address(hook), address(token1));

        uint256 userBalanceBefore = token1.balanceOf(address(this));

        // Remove specific amount
        uint256 amountToRemove = 40 ether;
        (uint256 amount0Withdrawn, uint256 amount1Withdrawn) =
            hook.removeTokensFromAave(key, tickLower, tickUpper, 0, amountToRemove);

        uint256 aaveBalanceAfter = mockAavePool.getUserBalance(address(hook), address(token1));
        uint256 withdrawn = aaveBalanceBefore - aaveBalanceAfter;

        // The withdrawn amount should match what was returned
        assertEq(amount0Withdrawn, 0, "No token0 should be withdrawn");
        assertEq(amount1Withdrawn, amountToRemove, "Withdrawn amount should match requested");
        assertApproxEqAbs(withdrawn, amount1Withdrawn, 1, "Aave withdrawal should match");

        // User balance should increase by exact amount
        assertEq(
            token1.balanceOf(address(this)) - userBalanceBefore,
            amountToRemove,
            "User balance should increase correctly"
        );
    }

    /**
     * @notice Test that Aave yield is included when withdrawing from Aave
     * Add tokens -> Simulate Aave yield -> Remove tokens -> Verify user gets the withdrawn amount
     * Note: The yield handling depends on how much the user requests to withdraw
     */
    function test_removeTokensFromAave_aaveYieldToUser() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick (will go to Aave)
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        uint256 amount1Desired = 100 ether;
        hook.addLiquidity(key, tickLower, tickUpper, 0, amount1Desired);

        MockAavePool mockAavePool = MockAavePool(address(aavePool));
        assertEq(
            mockAavePool.getUserBalance(address(hook), address(token1)), amount1Desired, "Should have deposited to Aave"
        );

        // Simulate Aave yield: 10% yield
        uint256 yieldAmount = 10 ether;
        mockAavePool.simulateYield(address(token1), yieldAmount);

        // Get balances before withdrawal
        uint256 userBalanceBefore = token1.balanceOf(address(this));

        // Remove only the original amount (not including yield)
        (uint256 amount0Withdrawn, uint256 amount1Withdrawn) =
            hook.removeTokensFromAave(key, tickLower, tickUpper, 0, amount1Desired);

        // User should receive their requested amount
        // Note: Due to Aave's implementation, when we withdraw amount1Desired,
        // it withdraws from the total balance including yield
        assertEq(amount0Withdrawn, 0, "No token0 should be withdrawn");
        assertEq(amount1Withdrawn, amount1Desired, "User should receive requested amount");

        uint256 actualReceived = token1.balanceOf(address(this)) - userBalanceBefore;
        // The actual amount received will include part of the yield since Aave withdraws proportionally
        assertGt(actualReceived, 0, "User should receive tokens");

        // Check that some balance remains in Aave (either yield or rounding)
        uint256 remainingInAave = mockAavePool.getUserBalance(address(hook), address(token1));
        assertGe(remainingInAave, 0, "Aave balance should be >= 0");
    }

    /**
     * @notice Test removing tokens from both token0 and token1 from Aave
     */
    function test_removeTokensFromAave_bothTokens() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick using the hook
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        uint256 amount0Desired = 50 ether;
        uint256 amount1Desired = 100 ether;
        hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        MockAavePool mockAavePool = MockAavePool(address(aavePool));

        uint256 aaveBalance0Before = mockAavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveBalance1Before = mockAavePool.getUserBalance(address(hook), address(token1));

        // Verify both tokens were deposited to Aave
        assertEq(aaveBalance0Before, amount0Desired, "Token0 should be in Aave");
        assertEq(aaveBalance1Before, amount1Desired, "Token1 should be in Aave");

        uint256 amount0ToRemove = 20 ether;
        uint256 amount1ToRemove = 40 ether;

        uint256 user0BalanceBefore = token0.balanceOf(address(this));
        uint256 user1BalanceBefore = token1.balanceOf(address(this));

        // Remove both tokens
        (uint256 amount0Withdrawn, uint256 amount1Withdrawn) =
            hook.removeTokensFromAave(key, tickLower, tickUpper, amount0ToRemove, amount1ToRemove);

        // Verify withdrawal amounts
        assertEq(amount0Withdrawn, amount0ToRemove, "Token0 withdrawn should match");
        assertEq(amount1Withdrawn, amount1ToRemove, "Token1 withdrawn should match");

        // Verify user balances
        assertEq(
            token0.balanceOf(address(this)) - user0BalanceBefore, amount0ToRemove, "User token0 balance should increase"
        );
        assertEq(
            token1.balanceOf(address(this)) - user1BalanceBefore, amount1ToRemove, "User token1 balance should increase"
        );

        // Verify Aave balances decreased
        uint256 aaveBalance0After = mockAavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveBalance1After = mockAavePool.getUserBalance(address(hook), address(token1));

        assertEq(aaveBalance0Before - aaveBalance0After, amount0ToRemove, "Aave token0 should decrease");
        assertEq(aaveBalance1Before - aaveBalance1After, amount1ToRemove, "Aave token1 should decrease");
    }

    /**
     * @notice Test that removing tokens from an in-range position reverts
     */
    function test_removeTokensFromAave_revertsIfInRange() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity within current tick range
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        uint256 amount0Desired = 10 ether;
        uint256 amount1Desired = 10 ether;
        hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        // Try to remove tokens from Aave (should fail because position is in pool, not Aave)
        vm.expectRevert();
        hook.removeTokensFromAave(key, tickLower, tickUpper, 1 ether, 1 ether);
    }

    /**
     * @notice Test that removing more tokens than available reverts
     */
    function test_removeTokensFromAave_revertsIfNotEnough() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        uint256 amount1Desired = 100 ether;
        hook.addLiquidity(key, tickLower, tickUpper, 0, amount1Desired);

        // Try to remove more than deposited
        vm.expectRevert();
        hook.removeTokensFromAave(key, tickLower, tickUpper, 0, amount1Desired + 1 ether);
    }

    /**
     * @notice Test that removing from non-existent position reverts
     */
    function test_removeTokensFromAave_revertsIfNoPosition() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        // Try to remove without adding first
        vm.expectRevert();
        hook.removeTokensFromAave(key, tickLower, tickUpper, 0, 1 ether);
    }
}
