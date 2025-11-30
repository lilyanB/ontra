// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MockERC20} from "solady/test/utils/mocks/MockERC20.sol";

/**
 * @notice Mock Aave Pool for testing
 * Only implements the minimal functions needed for testing
 */
contract MockAavePool {
    mapping(address => mapping(address => uint256)) private userBalances;
    mapping(address => uint256) private totalSupply;

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        MockERC20(asset).transferFrom(msg.sender, address(this), amount);
        userBalances[onBehalfOf][asset] += amount;
        totalSupply[asset] += amount;
    }

    function getUserBalance(address user, address asset) external view returns (uint256) {
        return userBalances[user][asset];
    }

    /**
     * @notice Simulate yield/interest accrual on Aave
     * @param asset The asset to add yield to
     * @param yieldAmount The amount of yield to add
     */
    function simulateYield(address asset, uint256 yieldAmount) external {
        // Mint yield tokens to the pool (don't add to totalSupply, that's principal only)
        MockERC20(asset).mint(address(this), yieldAmount);
    }

    /**
     * @notice Withdraw with simulated yield - returns more than deposited
     * @dev This overrides the balance check to allow withdrawal of principal + yield
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(userBalances[msg.sender][asset] >= amount, "Insufficient balance");

        // Calculate proportional amount including yield
        // proportionalAmount = amount * (poolBalance / totalDeposits)
        uint256 poolBalance = MockERC20(asset).balanceOf(address(this));
        uint256 totalDeposits = totalSupply[asset];

        // This gives us principal + proportional share of yield
        uint256 proportionalAmount = (amount * poolBalance) / totalDeposits;

        // Update accounting (only decrease by principal amount)
        userBalances[msg.sender][asset] -= amount;
        totalSupply[asset] -= amount;

        // Transfer the proportional amount (includes yield)
        MockERC20(asset).transfer(to, proportionalAmount);
        return proportionalAmount;
    }
}
