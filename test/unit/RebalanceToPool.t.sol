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

contract TestRebalanceToPool is OntraHookFixture {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    /**
     * @notice Test rebalancing reverts when position doesn't exist
     */
    function test_revertsWhen_positionDoesNotExist() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        vm.expectRevert(IOntraHook.OntraNoPosition.selector);
        hook.rebalanceToPool(address(this), key, tickLower, tickUpper);
    }

    /**
     * @notice Test rebalancing reverts when position is already in pool
     */
    function test_revertsWhen_positionAlreadyInPool() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;
        uint256 amount0Desired = 50 ether;
        uint256 amount1Desired = 50 ether;

        hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        vm.expectRevert(IOntraHook.OntraPositionAlreadyInPool.selector);
        hook.rebalanceToPool(address(this), key, tickLower, tickUpper);
    }

    /**
     * @notice Test rebalancing reverts when price is not in range
     */
    function test_revertsWhen_priceNotInRange() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        int24 fullRangeLower = TickMath.minUsableTick(60);
        int24 fullRangeUpper = TickMath.maxUsableTick(60);
        hook.addLiquidity(key, fullRangeLower, fullRangeUpper, 1000 ether, 1000 ether);

        // Add a concentrated position
        int24 tickLower = (currentTick / 60) * 60;
        int24 tickUpper = tickLower + 60;
        uint256 amount0Desired = 10 ether;
        uint256 amount1Desired = 10 ether;

        hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        // Move price below the position's range
        // Swap to decrease tick
        swap(key, true, 100 ether, "");

        // Rebalance to Aave
        hook.rebalanceToAave(address(this), key, tickLower, tickUpper);

        // Try to rebalance back to pool while still out of range - should revert
        vm.expectRevert("Position not in range");
        hook.rebalanceToPool(address(this), key, tickLower, tickUpper);
    }

    /**
     * @notice Test rebalancing a position from Aave back to the pool when price moves into range
     * This is the classic case: position starts out of range on Aave, then price moves into range
     */
    function test_rebalanceToPool_classic() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());

        // First, add a large base liquidity across full range to enable swaps
        int24 fullRangeLower = TickMath.minUsableTick(60);
        int24 fullRangeUpper = TickMath.maxUsableTick(60);
        hook.addLiquidity(key, fullRangeLower, fullRangeUpper, 1000 ether, 1000 ether);

        // Add a concentrated position ABOVE current tick (out of range, will go to Aave)
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        uint256 amount0Desired = 0;
        uint256 amount1Desired = 100 ether;

        hook.addLiquidity(key, tickLower, tickUpper, amount0Desired, amount1Desired);

        // Verify position is on Aave initially (since it's out of range)
        bytes32 positionKey = hook.getPositionKey(address(this), key.toId(), tickLower, tickUpper);
        {
            (address owner,,,, uint128 liquidity, bool isInRange, uint256 amount0OnAave, uint256 amount1OnAave) =
                hook._positions(positionKey);

            assertEq(owner, address(this), "Position owner should be this contract");
            assertEq(liquidity, 0, "Liquidity should be 0 (funds on Aave)");
            assertEq(isInRange, false, "Position should not be in range");
            assertEq(amount0OnAave, 0, "Token0 should be 0 on Aave");
            assertEq(amount1OnAave, amount1Desired, "Token1 on Aave should match deposited amount");
        }

        // Now swap to move price UP into the position's range
        // We want to increase the tick to bring it into [tickLower, tickUpper]
        bool zeroForOne = false; // Swap token1 for token0 to INCREASE tick (move right/up)
        int256 amountSpecified = 10 ether; // Small amount to move price just into range

        swap(key, zeroForOne, amountSpecified, "");

        // Verify the price moved into the position's range
        (, int24 newTick,,) = manager.getSlot0(key.toId());
        assertGe(newTick, tickLower, "Current tick should be >= tickLower");
        assertLe(newTick, tickUpper, "Current tick should be <= tickUpper");

        // Record Aave balances before rebalancing
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));

        // Rebalance from Aave to Pool
        hook.rebalanceToPool(address(this), key, tickLower, tickUpper);

        // Verify position state after rebalancing
        {
            (address ownerAfter, PoolId poolIdAfter, int24 tickLowerAfter, int24 tickUpperAfter,,,,) =
                hook._positions(positionKey);
            assertEq(ownerAfter, address(this), "Owner should remain unchanged");
            assertEq(PoolId.unwrap(poolIdAfter), PoolId.unwrap(key.toId()), "PoolId should remain unchanged");
            assertEq(tickLowerAfter, tickLower, "tickLower should remain unchanged");
            assertEq(tickUpperAfter, tickUpper, "tickUpper should remain unchanged");
        }

        // Verify liquidity and range status
        {
            (,,,, uint128 liquidityAfter, bool isInRangeAfter,,) = hook._positions(positionKey);
            assertGt(liquidityAfter, 0, "Liquidity should be > 0 after rebalancing to pool");
            assertEq(isInRangeAfter, true, "Position should be in range after rebalancing");
        }

        // Verify Aave deposits are cleared
        {
            (,,,,,, uint256 amount0OnAaveAfter, uint256 amount1OnAaveAfter) = hook._positions(positionKey);
            assertEq(amount0OnAaveAfter, 0, "Token0 on Aave should be 0 after rebalancing");
            assertEq(amount1OnAaveAfter, 0, "Token1 on Aave should be 0 after rebalancing");

            // Verify hook's Aave balances decreased
            uint256 aaveToken1After = aavePool.getUserBalance(address(hook), address(token1));
            assertLt(aaveToken1After, aaveToken1Before, "Hook's token1 on Aave should have decreased");
        }
    }
}
