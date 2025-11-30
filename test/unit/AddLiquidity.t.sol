// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
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
        uint256 amountToken0 = 50 ether;
        uint256 amountToken1 = 50 ether;

        // Add liquidity around current tick
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        // Record balances before
        uint256 token0BalanceBefore = token0.balanceOf(address(hook));
        uint256 token1BalanceBefore = token1.balanceOf(address(hook));
        uint256 aaveToken0Before = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));

        uint128 liquidity = hook.addLiquidity(key, tickLower, tickUpper, amountToken0, amountToken1);

        // Hook should not have received any tokens directly
        assertEq(token0.balanceOf(address(hook)), token0BalanceBefore, "Hook token0 balance should not change");
        assertEq(token1.balanceOf(address(hook)), token1BalanceBefore, "Hook token1 balance should not change");

        // Liquidity should stay in the pool manager (not deposited to Aave)
        assertEq(
            aavePool.getUserBalance(address(hook), address(token0)),
            aaveToken0Before,
            "No token0 should be deposited to Aave"
        );
        assertEq(
            aavePool.getUserBalance(address(hook), address(token1)),
            aaveToken1Before,
            "No token1 should be deposited to Aave"
        );

        // Verify liquidity was added
        assertGt(liquidity, 0, "Liquidity should be positive");

        {
            // Verify the position belongs to the HOOK (not the user directly)
            // but uses user-specific salt to differentiate positions
            bytes32 userSalt = bytes32(uint256(uint160(address(this))));
            bytes32 positionId = keccak256(abi.encodePacked(address(hook), tickLower, tickUpper, userSalt));
            uint128 positionLiquidity = manager.getPositionLiquidity(key.toId(), positionId);
            assertEq(positionLiquidity, liquidity, "Hook should own position with user-specific salt");
        }

        // Verify user does NOT own the position directly
        bytes32 userPositionId = keccak256(abi.encodePacked(address(this), tickLower, tickUpper, bytes32(0)));
        uint128 userDirectLiquidity = manager.getPositionLiquidity(key.toId(), userPositionId);
        assertEq(userDirectLiquidity, 0, "User should not own position directly");

        // Verify hook has no position with zero salt (default salt)
        bytes32 hookPositionId = keccak256(abi.encodePacked(address(hook), tickLower, tickUpper, bytes32(0)));
        uint128 hookLiquidity = manager.getPositionLiquidity(key.toId(), hookPositionId);
        assertEq(hookLiquidity, 0, "Hook should not have position with zero salt");
    }

    /**
     * @notice Test adding liquidity outside the current tick range (should deposit to Aave)
     * When liquidity is added outside the current tick range, it should be deposited to Aave
     */
    function test_addLiquidity_outsideCurrentTickRange_above() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());
        uint256 amountToken0 = 0;
        uint256 amountToken1 = 100 ether;

        // Add liquidity above current tick (only token1 should be deposited)
        int24 tickLower = currentTick + 120;
        int24 tickUpper = currentTick + 240;

        // Record balances before
        uint256 token0BalanceBefore = token0.balanceOf(address(hook));
        uint256 token1BalanceBefore = token1.balanceOf(address(hook));
        uint256 aaveToken0Before = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));
        uint256 userToken1Before = token1.balanceOf(address(this));

        uint128 liquidity = hook.addLiquidity(key, tickLower, tickUpper, amountToken0, amountToken1);

        // Hook should not hold tokens directly
        assertEq(token0.balanceOf(address(hook)), token0BalanceBefore, "Hook token0 balance should not change");
        assertEq(token1.balanceOf(address(hook)), token1BalanceBefore, "Hook token1 balance should not change");

        // Token1 should be deposited to Aave (token0 should not)
        assertEq(
            aavePool.getUserBalance(address(hook), address(token0)),
            aaveToken0Before,
            "No token0 should be deposited to Aave"
        );
        assertEq(
            aavePool.getUserBalance(address(hook), address(token1)),
            aaveToken1Before + amountToken1,
            "100 ether token1 should be deposited to Aave"
        );

        // Verify user paid token1
        assertEq(
            userToken1Before - token1.balanceOf(address(this)), amountToken1, "User should have paid 100 ether token1"
        );
        assertEq(liquidity, 0, "Liquidity should be 0 for Aave deposits");
    }

    /**
     * @notice Test adding liquidity below the current tick range
     * When liquidity is added below the current tick range, only token0 should be deposited to Aave
     */
    function test_addLiquidity_outsideCurrentTickRange_below() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());
        uint256 amountToken0 = 100 ether;
        uint256 amountToken1 = 0;

        // Add liquidity below current tick (only token0 should be deposited)
        int24 tickLower = currentTick - 240;
        int24 tickUpper = currentTick - 120;

        // Record balances before
        uint256 token0BalanceBefore = token0.balanceOf(address(hook));
        uint256 token1BalanceBefore = token1.balanceOf(address(hook));
        uint256 aaveToken0Before = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));
        uint256 userToken0Before = token0.balanceOf(address(this));

        uint128 liquidity = hook.addLiquidity(key, tickLower, tickUpper, amountToken0, amountToken1);

        // Hook should not hold tokens directly
        assertEq(token0.balanceOf(address(hook)), token0BalanceBefore, "Hook token0 balance should not change");
        assertEq(token1.balanceOf(address(hook)), token1BalanceBefore, "Hook token1 balance should not change");

        // Token0 should be deposited to Aave (token1 should not)
        assertEq(
            aavePool.getUserBalance(address(hook), address(token0)),
            amountToken0 + aaveToken0Before,
            "100 ether token0 should be deposited to Aave"
        );
        assertEq(
            aavePool.getUserBalance(address(hook), address(token1)),
            aaveToken1Before,
            "No token1 should be deposited to Aave"
        );

        // Verify user paid token0
        assertEq(
            userToken0Before - token0.balanceOf(address(this)), amountToken0, "User should have paid 100 ether token0"
        );
        assertEq(liquidity, 0, "Liquidity should be 0 for Aave deposits");
    }

    /**
     * @notice Test that liquidity can be added in multiple ranges
     * Add liquidity within range, then add more outside range
     */
    function test_liquidityMovesToAave_afterPriceCross() public {
        (, int24 currentTick,,) = manager.getSlot0(key.toId());
        uint256 amountToken0First = 50 ether;
        uint256 amountToken1First = 50 ether;

        // First add liquidity within range
        int24 tickLower = currentTick - 60;
        int24 tickUpper = currentTick + 60;

        uint256 aaveToken0Before = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1Before = aavePool.getUserBalance(address(hook), address(token1));

        uint128 liquidity1 = hook.addLiquidity(key, tickLower, tickUpper, amountToken0First, amountToken1First);

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

        uint256 amountToken0Second = 0;
        uint256 amountToken1Second = 100 ether;
        // Now add more liquidity in a different range (above current tick)
        int24 tickLowerAbove = currentTick + 120;
        int24 tickUpperAbove = currentTick + 240;

        uint128 liquidity2 =
            hook.addLiquidity(key, tickLowerAbove, tickUpperAbove, amountToken0Second, amountToken1Second);

        // Verify Aave deposits for out-of-range liquidity
        uint256 aaveToken0After = aavePool.getUserBalance(address(hook), address(token0));
        uint256 aaveToken1After = aavePool.getUserBalance(address(hook), address(token1));

        assertEq(aaveToken0After, aaveToken0Before, "No token0 should be deposited (above range)");
        assertEq(aaveToken1After - aaveToken1Before, amountToken1Second, "100 ether token1 should be deposited to Aave");

        // Verify liquidities
        assertGt(liquidity1, 0, "First liquidity should be positive (in-range)");
        assertEq(liquidity2, 0, "Second liquidity should be 0 for Aave deposits");

        // Verify the in-range position belongs to the HOOK with user-specific salt
        {
            bytes32 userSalt = bytes32(uint256(uint160(address(this))));
            bytes32 positionId = keccak256(abi.encodePacked(address(hook), tickLower, tickUpper, userSalt));
            uint128 positionLiquidity = manager.getPositionLiquidity(key.toId(), positionId);
            assertEq(positionLiquidity, liquidity1, "Hook should own position with user-specific salt");
        }

        // Verify user does NOT own the position directly
        bytes32 userPositionId = keccak256(abi.encodePacked(address(this), tickLower, tickUpper, bytes32(0)));
        uint128 userDirectLiquidity = manager.getPositionLiquidity(key.toId(), userPositionId);
        assertEq(userDirectLiquidity, 0, "User should not own position directly");

        // Verify hook has no position with zero salt
        bytes32 hookPositionId = keccak256(abi.encodePacked(address(hook), tickLower, tickUpper, bytes32(0)));
        uint128 hookLiquidity = manager.getPositionLiquidity(key.toId(), hookPositionId);
        assertEq(hookLiquidity, 0, "Hook should not have position with zero salt");
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
        assertEq(aaveToken0After - aaveToken0Before, 1000 ether, "1000 ether should be deposited");
        assertEq(liquidity, 0, "Liquidity should be 0 for Aave deposits");
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

        // Both deposits should be equal to 50 ether each
        assertEq(firstDeposit, 50 ether, "First deposit should be 50 ether");
        assertEq(secondDeposit, 50 ether, "Second deposit should be 50 ether");
        assertEq(liquidity1, 0, "First liquidity should be 0 for Aave deposits (out-of-range)");
        assertEq(liquidity2, 0, "Second liquidity should be 0 for Aave deposits (out-of-range)");
    }
}
