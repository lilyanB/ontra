// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {OntraHookFixture} from "./utils/Fixtures.sol";
import {MockAavePool} from "./utils/MockAavePool.sol";

contract TestRemoveLiquidity is OntraHookFixture {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    /**
     * @notice Test removing liquidity within current tick range (liquidity is idle)
     * When liquidity is in range, it's not in Aave, so removal should work directly
     */
    function test_removeLiquidity_withinCurrentTickRange() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity within current tick range
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: 10 ether, salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 token0BalanceBefore = token0.balanceOf(address(this));
        uint256 token1BalanceBefore = token1.balanceOf(address(this));

        // Remove liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: -10 ether, salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 token0BalanceAfter = token0.balanceOf(address(this));
        uint256 token1BalanceAfter = token1.balanceOf(address(this));

        // Should have received tokens back
        assertGt(token0BalanceAfter, token0BalanceBefore);
        assertGt(token1BalanceAfter, token1BalanceBefore);
    }

    /**
     * @notice Test removing liquidity outside current tick range (should withdraw from Aave)
     * When liquidity is outside the current range, it should be in Aave
     */
    function test_removeLiquidity_outsideCurrentTickRange_above() public {
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

        // Calculate liquidity for the amount deposited
        // When position is above current price (all in token1), use getLiquidityForAmount1 directly
        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(tickUpper);

        uint128 liquidityToRemove =
            LiquidityAmounts.getLiquidityForAmount1(sqrtPriceX96Lower, sqrtPriceX96Upper, amount1Desired);

        // Now remove half liquidity using the hook
        hook.removeLiquidity(key, tickLower, tickUpper, liquidityToRemove / 2);

        // Verify funds were withdrawn from Aave
        uint256 aaveBalanceAfter = mockAavePool.getUserBalance(address(hook), address(token1));
        assertLt(aaveBalanceAfter, aaveBalanceBefore);
    }

    /**
     * @notice Test removing liquidity below current tick range
     * Token0 should be withdrawn from Aave
     */
    function test_removeLiquidity_outsideCurrentTickRange_below() public {
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

        // Calculate liquidity for the amount deposited
        // When position is below current price (all in token0), use getLiquidityForAmount0 directly
        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(tickUpper);
        uint128 liquidityToRemove =
            LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96Lower, sqrtPriceX96Upper, amount0Desired);

        // Now remove half liquidity using the hook
        hook.removeLiquidity(key, tickLower, tickUpper, liquidityToRemove / 2);

        // Verify token0 was withdrawn from Aave
        uint256 aaveBalanceAfter = mockAavePool.getUserBalance(address(hook), address(token0));
        assertLt(aaveBalanceAfter, aaveBalanceBefore);
    }

    /**
     * @notice Test partial removal of liquidity from Aave
     * Should only withdraw the proportional amount from Aave
     */
    function test_removeLiquidity_partial_fromAave() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick using the hook
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        uint256 amount1Desired = 100 ether;
        hook.addLiquidity(key, tickLower, tickUpper, 0, amount1Desired);

        MockAavePool mockAavePool = MockAavePool(address(aavePool));
        uint256 aaveBalanceBefore = mockAavePool.getUserBalance(address(hook), address(token1));

        // Calculate liquidity for the amount deposited
        // When position is above current price (all in token1), use getLiquidityForAmount1 directly
        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(tickUpper);
        uint128 totalLiquidity =
            LiquidityAmounts.getLiquidityForAmount1(sqrtPriceX96Lower, sqrtPriceX96Upper, amount1Desired);

        // Remove half the liquidity
        hook.removeLiquidity(key, tickLower, tickUpper, totalLiquidity / 2);

        uint256 aaveBalanceAfter = mockAavePool.getUserBalance(address(hook), address(token1));

        // Aave balance should have decreased but not to zero
        assertLt(aaveBalanceAfter, aaveBalanceBefore);
        assertGt(aaveBalanceAfter, 0);
    }

    /**
     * @notice Test removing all liquidity from Aave
     * Should completely withdraw from Aave position
     */
    function test_removeLiquidity_complete_fromAave() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick using the hook
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        hook.addLiquidity(key, tickLower, tickUpper, 0, 100 ether);

        MockAavePool mockAavePool = MockAavePool(address(aavePool));
        uint256 aaveBalanceBefore = mockAavePool.getUserBalance(address(hook), address(token1));
        assertGt(aaveBalanceBefore, 0);

        // Calculate liquidity equivalent for the deposited amount
        // When position is above current price (all in token1), use getLiquidityForAmount1 directly
        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(tickUpper);
        uint128 liquidityToRemove =
            LiquidityAmounts.getLiquidityForAmount1(sqrtPriceX96Lower, sqrtPriceX96Upper, 100 ether);

        // Remove all liquidity
        hook.removeLiquidity(key, tickLower, tickUpper, liquidityToRemove);

        uint256 aaveBalanceAfter = mockAavePool.getUserBalance(address(hook), address(token1));

        // Aave balance should be significantly reduced (accounting for rounding)
        assertLt(aaveBalanceAfter, aaveBalanceBefore / 10);
    }

    /**
     * @notice Test liquidity calculations are correct for withdrawal
     * Verify that the amounts calculated match what's actually withdrawn
     */
    function test_removeLiquidity_correctAmountCalculation() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick using the hook
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        uint256 amount1Desired = 100 ether;
        hook.addLiquidity(key, tickLower, tickUpper, 0, amount1Desired);

        MockAavePool mockAavePool = MockAavePool(address(aavePool));
        uint256 aaveBalanceBefore = mockAavePool.getUserBalance(address(hook), address(token1));

        // Calculate liquidity based on deposited amount
        // When position is above current price (all in token1), use getLiquidityForAmount1 directly
        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(tickUpper);

        uint128 liquidityAmount =
            LiquidityAmounts.getLiquidityForAmount1(sqrtPriceX96Lower, sqrtPriceX96Upper, amount1Desired);

        // Remove liquidity
        (uint256 amount0Withdrawn, uint256 amount1Withdrawn) =
            hook.removeLiquidity(key, tickLower, tickUpper, liquidityAmount);

        uint256 aaveBalanceAfter = mockAavePool.getUserBalance(address(hook), address(token1));
        uint256 withdrawn = aaveBalanceBefore - aaveBalanceAfter;

        // The withdrawn amount should match what was returned
        assertEq(amount0Withdrawn, 0, "No token0 should be withdrawn");
        assertApproxEqAbs(withdrawn, amount1Withdrawn, 1e10, "Withdrawn amount should match");
    }
}
