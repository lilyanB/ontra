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

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(userBalances[msg.sender][asset] >= amount, "Insufficient balance");
        userBalances[msg.sender][asset] -= amount;
        totalSupply[asset] -= amount;
        MockERC20(asset).transfer(to, amount);
        return amount;
    }

    function getUserBalance(address user, address asset) external view returns (uint256) {
        return userBalances[user][asset];
    }
}
