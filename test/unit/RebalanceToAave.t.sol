// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {Vm} from "forge-std/Vm.sol";

import {OntraHookFixture} from "./utils/Fixtures.sol";
import {IOntraHook} from "../../src/interfaces/IOntraHook.sol";

contract TestRebalanceToAave is OntraHookFixture {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    /**
     * @notice Test rebalancing a position to Aave when price moves out of range (above)
     * When the current tick moves above the position's tick range, the position should be rebalanced to Aave
     */
    function test_rebalanceToAave_positionBelowCurrentTick() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity below current tick
        int24 tickLower = currentTick - 240;
        int24 tickUpper = currentTick - 120;

        uint256 amount0Desired = 100 ether;
        uint256 amount1Desired = 0;

        // Add liquidity (should be active initially since we set up the position below)
        // We need to make the position in range first, then move the price
        hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        // Verify position is on Aave initially (since it's out of range)
        bytes32 positionKey = hook.getPositionKey(address(this), key.toId(), tickLower, tickUpper);
        (address owner,,,, uint128 liquidity, bool isInRange, uint256 amount0OnAave, uint256 amount1OnAave) =
            hook._positions(positionKey);

        assertEq(owner, address(this), "Position owner should be this contract");
        assertEq(liquidity, 0, "Liquidity should be 0 (funds on Aave)");
        assertEq(isInRange, false, "Position should not be in range");
        assertEq(amount0OnAave, amount0Desired, "Token0 on Aave should match deposited amount");
        assertEq(amount1OnAave, 0, "Token1 should be 0 on Aave");

        // Position is already out of range and on Aave, so rebalanceToAave should revert
        vm.expectRevert(IOntraHook.OntraPositionAlreadyInAave.selector);
        hook.rebalanceToAave(address(this), key, tickLower, tickUpper);
    }

    /**
     * @notice Test rebalancing a position to Aave when price moves out of range (below)
     * When the current tick moves below the position's tick range, the position should be rebalanced to Aave
     */
    function test_rebalanceToAave_positionAboveCurrentTick() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // First, add a large base liquidity across full range to enable swaps
        int24 fullRangeLower = TickMath.minUsableTick(60);
        int24 fullRangeUpper = TickMath.maxUsableTick(60);
        hook.addLiquidity(key, fullRangeLower, fullRangeUpper, 1000 ether, 1000 ether);

        // Add a very small concentrated position (just 60 ticks = 1 tickSpacing)
        // This makes it very easy to move price out of range
        // Position at current tick exactly
        int24 tickLower = (currentTick / 60) * 60; // Align to current
        int24 tickUpper = tickLower + 60; // Just one tick spacing wide

        uint256 amount0Desired = 10 ether;
        uint256 amount1Desired = 10 ether;

        uint128 liquidityAdded = hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        // Verify position is in pool
        bytes32 positionKey = hook.getPositionKey(address(this), key.toId(), tickLower, tickUpper);
        {
            (address owner,,,, uint128 liquidity, bool isInRange,,) = hook._positions(positionKey);

            assertEq(owner, address(this), "Position owner should be this contract");
            assertEq(liquidity, liquidityAdded, "Liquidity should match added amount");
            assertEq(isInRange, true, "Position should be in range");
        }

        // Now swap to move price below the position's range
        // Small swap is enough for such a narrow range
        bool zeroForOne = true; // Swap token0 for token1 to DECREASE tick (move left/down)
        int256 amountSpecified = 100 ether; // Moderate amount

        swap(key, zeroForOne, amountSpecified, "");

        // Verify the price moved below the position
        (, int24 newTick,,) = manager.getSlot0(key.toId());
        assertLt(newTick, tickLower, "Current tick should be below tickLower");

        // Record balances before rebalancing
        uint256 aaveToken0Before = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));

        // Rebalance to Aave
        hook.rebalanceToAave(address(this), key, tickLower, tickUpper);

        // Verify position state after rebalancing - check owner and poolId
        {
            (address ownerAfter, PoolId poolIdAfter,,,,,,) = hook._positions(positionKey);
            assertEq(ownerAfter, address(this), "Owner should remain unchanged");
            assertEq(PoolId.unwrap(poolIdAfter), PoolId.unwrap(key.toId()), "PoolId should remain unchanged");
        }

        // Verify liquidity and range status
        {
            (,,,, uint128 liquidityAfter, bool isInRangeAfter,,) = hook._positions(positionKey);
            assertEq(liquidityAfter, 0, "Liquidity should be 0 after rebalancing");
            assertEq(isInRangeAfter, false, "Position should not be in range after rebalancing");
        }

        // Verify Aave deposits
        {
            (,,,,,, uint256 amount0OnAaveAfter, uint256 amount1OnAaveAfter) = hook._positions(positionKey);
            uint256 expectedAmount0 = aavePool.getUserBalance(address(hook), address(token0)) - aaveToken0Before;
            uint256 expectedAmount1 = aavePool.getUserBalance(address(hook), address(token1)) - aaveToken1Before;

            assertEq(amount0OnAaveAfter, expectedAmount0, "Token0 on Aave should match deposit");
            assertEq(amount1OnAaveAfter, expectedAmount1, "Token1 on Aave should match deposit");
            assertEq(amount0OnAaveAfter, expectedAmount0, "Should have exact token0 amount on Aave");
            // When price moves below, token1 should be minimal or zero
            assertEq(amount1OnAaveAfter, 0, "Should have no token1 on Aave when price is below range");
        }
    }

    /**
     * @notice Test rebalancing reverts when position is still in range
     */
    function test_rebalanceToAave_revertsWhenStillInRange() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // Add liquidity around current tick
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        uint256 amount0Desired = 50 ether;
        uint256 amount1Desired = 50 ether;

        hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        // Try to rebalance while still in range - should revert
        vm.expectRevert("Position still in range");
        hook.rebalanceToAave(address(this), key, tickLower, tickUpper);
    }

    /**
     * @notice Test rebalancing reverts when position doesn't exist
     */
    function test_rebalanceToAave_revertsWhenNoPosition() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        // Try to rebalance non-existent position
        vm.expectRevert(IOntraHook.OntraNoPosition.selector);
        hook.rebalanceToAave(address(this), key, tickLower, tickUpper);
    }

    /**
     * @notice Test rebalancing reverts when position has no liquidity
     */
    function test_rebalanceToAave_revertsWhenNoLiquidity() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // First, add base liquidity for swaps
        int24 fullRangeLower = TickMath.minUsableTick(60);
        int24 fullRangeUpper = TickMath.maxUsableTick(60);
        hook.addLiquidity(key, fullRangeLower, fullRangeUpper, 1000 ether, 1000 ether);

        // Add a very small concentrated position (just 60 ticks wide)
        int24 tickLower = (currentTick / 60) * 60;
        int24 tickUpper = tickLower + 60;

        uint256 amount0Desired = 10 ether;
        uint256 amount1Desired = 10 ether;

        uint128 liquidityAdded = hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        // Remove all liquidity
        hook.removeLiquidity(key, tickLower, tickUpper, liquidityAdded);

        // Move price below the position's range
        bool zeroForOne = true; // Swap to decrease tick
        int256 amountSpecified = 100 ether;
        swap(key, zeroForOne, amountSpecified, "");

        // Verify the price moved
        (, int24 newTick,,) = manager.getSlot0(key.toId());
        assertLt(newTick, tickLower, "Current tick should be below tickLower");

        // Position should have been deleted, so rebalancing should revert
        vm.expectRevert(IOntraHook.OntraNoPosition.selector);
        hook.rebalanceToAave(address(this), key, tickLower, tickUpper);
    }

    /**
     * @notice Test rebalancing can be called by anyone (not just position owner)
     */
    function test_rebalanceToAave_canBeCalledByAnyone() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // First, add base liquidity for swaps
        int24 fullRangeLower = TickMath.minUsableTick(60);
        int24 fullRangeUpper = TickMath.maxUsableTick(60);
        hook.addLiquidity(key, fullRangeLower, fullRangeUpper, 1000 ether, 1000 ether);

        // Add a very small concentrated position (just 60 ticks wide)
        int24 tickLower = (currentTick / 60) * 60;
        int24 tickUpper = tickLower + 60;

        uint256 amount0Desired = 10 ether;
        uint256 amount1Desired = 10 ether;

        hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        // Move price out of range with small swap
        bool zeroForOne = true; // Swap to decrease tick
        int256 amountSpecified = 100 ether;
        swap(key, zeroForOne, amountSpecified, "");

        // Verify the price moved
        (, int24 newTick,,) = manager.getSlot0(key.toId());
        assertLt(newTick, tickLower, "Current tick should be below tickLower");

        // Rebalance from a different address
        address otherUser = address(0x1234);
        vm.prank(otherUser);
        hook.rebalanceToAave(address(this), key, tickLower, tickUpper);

        // Verify position was rebalanced - check owner and poolId
        bytes32 positionKey = hook.getPositionKey(address(this), key.toId(), tickLower, tickUpper);
        {
            (address ownerAfter, PoolId poolIdAfter,,,,,,) = hook._positions(positionKey);
            assertEq(ownerAfter, address(this), "Owner should remain unchanged");
            assertEq(PoolId.unwrap(poolIdAfter), PoolId.unwrap(key.toId()), "PoolId should remain unchanged");
        }

        // Verify liquidity and range status
        {
            (,,,, uint128 liquidityAfter, bool isInRangeAfter,,) = hook._positions(positionKey);
            assertEq(liquidityAfter, 0, "Liquidity should be 0 after rebalancing");
            assertEq(isInRangeAfter, false, "Position should not be in range after rebalancing");
        }

        // Verify Aave deposits
        {
            (,,,,,, uint256 amount0OnAaveAfter, uint256 amount1OnAaveAfter) = hook._positions(positionKey);
            uint256 expectedAmount0 = aavePool.getUserBalance(address(hook), address(token0));

            assertEq(amount0OnAaveAfter, expectedAmount0, "Should have exact token0 amount on Aave");
            // When price moves below, token1 should be zero
            assertEq(amount1OnAaveAfter, 0, "Should have no token1 on Aave when price is below range");
        }
    }

    /**
     * @notice Test rebalancing a position that moves above current tick (only token1)
     */
    function test_rebalanceToAave_positionMovesAbove() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // First, add base liquidity for swaps
        int24 fullRangeLower = TickMath.minUsableTick(60);
        int24 fullRangeUpper = TickMath.maxUsableTick(60);
        hook.addLiquidity(key, fullRangeLower, fullRangeUpper, 1000 ether, 1000 ether);

        // Add a very small concentrated position (just 60 ticks wide)
        int24 tickLower = (currentTick / 60) * 60;
        int24 tickUpper = tickLower + 60;

        uint256 amount0Desired = 10 ether;
        uint256 amount1Desired = 10 ether;

        hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        // Move price above the position's range with small swap
        bool zeroForOne = false; // Swap to increase tick
        int256 amountSpecified = 100 ether;

        swap(key, zeroForOne, amountSpecified, "");

        // Verify the price moved above the position
        (, int24 newTick,,) = manager.getSlot0(key.toId());
        assertGt(newTick, tickUpper, "Current tick should be above tickUpper");

        // Record balances before rebalancing
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));

        // Rebalance to Aave
        hook.rebalanceToAave(address(this), key, tickLower, tickUpper);

        // Verify position state after rebalancing - check owner and poolId
        bytes32 positionKey = hook.getPositionKey(address(this), key.toId(), tickLower, tickUpper);
        {
            (address ownerAfter, PoolId poolIdAfter,,,,,,) = hook._positions(positionKey);
            assertEq(ownerAfter, address(this), "Owner should remain unchanged");
            assertEq(PoolId.unwrap(poolIdAfter), PoolId.unwrap(key.toId()), "PoolId should remain unchanged");
        }

        // Verify liquidity and range status
        {
            (,,,, uint128 liquidityAfter, bool isInRangeAfter,,) = hook._positions(positionKey);
            assertEq(liquidityAfter, 0, "Liquidity should be 0 after rebalancing");
            assertEq(isInRangeAfter, false, "Position should not be in range after rebalancing");
        }

        // Verify Aave deposits - when price moves above, should have mostly token1
        {
            (,,,,,, uint256 amount0OnAaveAfter, uint256 amount1OnAaveAfter) = hook._positions(positionKey);
            uint256 expectedAmount1 = aavePool.getUserBalance(address(hook), address(token1)) - aaveToken1Before;

            assertEq(amount1OnAaveAfter, expectedAmount1, "Token1 on Aave should match deposit");
            assertEq(amount1OnAaveAfter, expectedAmount1, "Should have exact token1 amount on Aave");
            assertEq(amount0OnAaveAfter, 0, "Should have no token0 on Aave when price is above range");
        }
    }
}
