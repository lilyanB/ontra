// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Position} from "v4-core/libraries/Position.sol";

import {OntraHookFixture} from "./utils/Fixtures.sol";

contract TestAddLiquidity is OntraHookFixture {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    /**
     * @notice Test adding liquidity within the current tick range (liquidity stays idle)
     * When liquidity is added within the current tick range, it should NOT be deposited to Aave
     */
    function test_addLiquidity_withinCurrentTickRange() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity around current tick
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        // Record balances before
        uint256 token0BalanceBefore = token0.balanceOf(address(hook));
        uint256 token1BalanceBefore = token1.balanceOf(address(hook));
        uint256 aaveToken0Before = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));

        uint128 liquidity = hook.addLiquidity(key, tickLower, tickUpper, 50 ether, 50 ether);

        // Verify balances after
        uint256 token0BalanceAfter = token0.balanceOf(address(hook));
        uint256 token1BalanceAfter = token1.balanceOf(address(hook));
        uint256 aaveToken0After = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1After = aavePool.getUserBalance(address(hook), address(token1));

        // Hook should not have received any tokens directly
        assertEq(token0BalanceAfter, token0BalanceBefore, "Hook token0 balance should not change");
        assertEq(token1BalanceAfter, token1BalanceBefore, "Hook token1 balance should not change");

        // Liquidity should stay in the pool manager (not deposited to Aave)
        assertEq(aaveToken0After, aaveToken0Before, "No token0 should be deposited to Aave");
        assertEq(aaveToken1After, aaveToken1Before, "No token1 should be deposited to Aave");

        // Verify liquidity was added
        assertGt(liquidity, 0, "Liquidity should be positive");
    }

    /**
     * @notice Test adding liquidity outside the current tick range (should deposit to Aave)
     * When liquidity is added outside the current tick range, it should be deposited to Aave
     */
    function test_addLiquidity_outsideCurrentTickRange_above() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity above current tick (only token1 should be deposited)
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        // Record balances before
        uint256 token0BalanceBefore = token0.balanceOf(address(hook));
        uint256 token1BalanceBefore = token1.balanceOf(address(hook));
        uint256 aaveToken0Before = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));
        uint256 userToken1Before = token1.balanceOf(address(this));

        uint128 liquidity = hook.addLiquidity(key, tickLower, tickUpper, 0, 100 ether);

        // Verify balances after
        uint256 token0BalanceAfter = token0.balanceOf(address(hook));
        uint256 token1BalanceAfter = token1.balanceOf(address(hook));
        uint256 aaveToken0After = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1After = aavePool.getUserBalance(address(hook), address(token1));
        uint256 userToken1After = token1.balanceOf(address(this));

        // Hook should not hold tokens directly
        assertEq(token0BalanceAfter, token0BalanceBefore, "Hook token0 balance should not change");
        assertEq(token1BalanceAfter, token1BalanceBefore, "Hook token1 balance should not change");

        // Token1 should be deposited to Aave (token0 should not)
        assertEq(aaveToken0After, aaveToken0Before, "No token0 should be deposited to Aave");
        assertTrue(aaveToken1After > aaveToken1Before, "Token1 should be deposited to Aave");

        // Verify user paid token1
        assertTrue(userToken1After < userToken1Before, "User should have paid token1");
        assertGt(liquidity, 0, "Liquidity should be positive");
    }

    /**
     * @notice Test adding liquidity below the current tick range
     * When liquidity is added below the current tick range, only token0 should be deposited to Aave
     */
    function test_addLiquidity_outsideCurrentTickRange_below() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity below current tick (only token0 should be deposited)
        int24 tickLower = currentTick - 240;
        int24 tickUpper = currentTick - 120;

        // Record balances before
        uint256 token0BalanceBefore = token0.balanceOf(address(hook));
        uint256 token1BalanceBefore = token1.balanceOf(address(hook));
        uint256 aaveToken0Before = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));
        uint256 userToken0Before = token0.balanceOf(address(this));

        uint128 liquidity = hook.addLiquidity(key, tickLower, tickUpper, 100 ether, 0);

        // Verify balances after
        uint256 token0BalanceAfter = token0.balanceOf(address(hook));
        uint256 token1BalanceAfter = token1.balanceOf(address(hook));
        uint256 aaveToken0After = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1After = aavePool.getUserBalance(address(hook), address(token1));
        uint256 userToken0After = token0.balanceOf(address(this));

        // Hook should not hold tokens directly
        assertEq(token0BalanceAfter, token0BalanceBefore, "Hook token0 balance should not change");
        assertEq(token1BalanceAfter, token1BalanceBefore, "Hook token1 balance should not change");

        // Token0 should be deposited to Aave (token1 should not)
        assertTrue(aaveToken0After > aaveToken0Before, "Token0 should be deposited to Aave");
        assertEq(aaveToken1After, aaveToken1Before, "No token1 should be deposited to Aave");

        // Verify user paid token0
        assertTrue(userToken0After < userToken0Before, "User should have paid token0");
        assertGt(liquidity, 0, "Liquidity should be positive");
    }

    /**
     * @notice Test that liquidity can be added in multiple ranges
     * Add liquidity within range, then add more outside range
     */
    function test_liquidityMovesToAave_afterPriceCross() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // First add liquidity within range
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        uint256 aaveToken0Before = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));

        uint128 liquidity1 = hook.addLiquidity(key, tickLower, tickUpper, 50 ether, 50 ether);

        // Verify no Aave deposits for in-range liquidity
        assertEq(
            aavePool.getUserBalance(address(hook), address(token0)),
            aaveToken0Before,
            "No token0 should be in Aave for in-range liquidity"
        );
        assertEq(
            aavePool.getUserBalance(address(hook), address(token1)),
            aaveToken1Before,
            "No token1 should be in Aave for in-range liquidity"
        );

        // Now add more liquidity in a different range (above current tick)
        int24 tickLowerAbove = currentTick + 120;
        int24 tickUpperAbove = currentTick + 240;

        uint128 liquidity2 = hook.addLiquidity(key, tickLowerAbove, tickUpperAbove, 0, 100 ether);

        // Verify Aave deposits for out-of-range liquidity
        uint256 aaveToken0After = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1After = aavePool.getUserBalance(address(hook), address(token1));

        assertEq(aaveToken0After, aaveToken0Before, "No token0 should be deposited (above range)");
        assertTrue(aaveToken1After > aaveToken1Before, "Token1 should be deposited to Aave");

        // Verify liquidities
        assertGt(liquidity1, 0, "First liquidity should be positive");
        assertGt(liquidity2, 0, "Second liquidity should be positive");
    }

    /**
     * @notice Test adding large amounts of liquidity
     */
    function test_addLiquidity_largeAmount() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        int24 tickLower = currentTick - 600;
        int24 tickUpper = currentTick - 300;

        uint256 aaveToken0Before = aavePool.getUserBalance(address(hook), address(token0));

        uint128 liquidity = hook.addLiquidity(key, tickLower, tickUpper, 1000 ether, 0);

        uint256 aaveToken0After = aavePool.getUserBalance(address(hook), address(token0));

        // Verify large deposit
        assertTrue(aaveToken0After > aaveToken0Before, "Large amount should be deposited");
        assertGt(liquidity, 0, "Liquidity should be positive");
    }

    /**
     * @notice Test multiple sequential liquidity additions
     */
    function test_addLiquidity_multiple() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        int24 tickLower = currentTick + 60;
        int24 tickUpper = currentTick + 120;

        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));

        // First addition
        uint128 liquidity1 = hook.addLiquidity(key, tickLower, tickUpper, 0, 50 ether);

        uint256 aaveToken1After1 = aavePool.getUserBalance(address(hook), address(token1));
        uint256 firstDeposit = aaveToken1After1 - aaveToken1Before;

        // Second addition (same position)
        uint128 liquidity2 = hook.addLiquidity(key, tickLower, tickUpper, 0, 50 ether);

        uint256 aaveToken1After2 = aavePool.getUserBalance(address(hook), address(token1));
        uint256 secondDeposit = aaveToken1After2 - aaveToken1After1;

        // Both deposits should be positive
        assertGt(firstDeposit, 0, "First deposit should be positive");
        assertGt(secondDeposit, 0, "Second deposit should be positive");
        assertGt(liquidity1, 0, "First liquidity should be positive");
        assertGt(liquidity2, 0, "Second liquidity should be positive");
    }
}
