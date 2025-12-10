// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockAavePool
 * @notice Simple mock of Aave V3 Pool for testing
 * @dev Only implements supply/withdraw - just holds tokens like a vault
 */
contract MockAavePool {
    using SafeERC20 for IERC20;

    // user => token => balance
    mapping(address => mapping(address => uint256)) public balances;

    event Supply(address indexed asset, uint256 amount, address indexed onBehalfOf, uint16 referralCode);
    event Withdraw(address indexed asset, uint256 amount, address indexed to);

    /**
     * @notice Deposits tokens into the mock pool
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens
     * @param referralCode Code used to register the integrator (unused in mock)
     */
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        require(amount > 0, "Amount must be > 0");

        // Transfer tokens from sender to this contract
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Track balance
        balances[onBehalfOf][asset] += amount;

        emit Supply(asset, amount, onBehalfOf, referralCode);
    }

    /**
     * @notice Withdraws tokens from the mock pool
     * @param asset The address of the underlying asset to withdraw
     * @param amount The amount to be withdrawn (type(uint256).max for all)
     * @param to The address that will receive the underlying tokens
     * @return The final amount withdrawn
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        uint256 userBalance = balances[msg.sender][asset];
        require(userBalance > 0, "No balance");

        // Handle max withdrawal
        uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;
        require(amountToWithdraw <= userBalance, "Insufficient balance");

        // Update balance
        balances[msg.sender][asset] -= amountToWithdraw;

        // Transfer tokens
        IERC20(asset).safeTransfer(to, amountToWithdraw);

        emit Withdraw(asset, amountToWithdraw, to);

        return amountToWithdraw;
    }

    /**
     * @notice Returns the balance of a user for a specific asset
     * @param user The user address
     * @param asset The asset address
     * @return The balance
     */
    function getBalance(address user, address asset) external view returns (uint256) {
        return balances[user][asset];
    }

    /**
     * @notice Mock getReserveData - returns fake data to pass checks
     * @param asset The asset address
     * @return ReserveData struct with fake aToken address set to this contract
     */
    function getReserveData(address asset) external view returns (ReserveData memory) {
        // Return fake data with aTokenAddress set to indicate asset is "supported"
        return ReserveData({
            configuration: 0,
            liquidityIndex: 1e27,
            currentLiquidityRate: 0,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 0,
            aTokenAddress: address(this), // Set to non-zero to indicate "supported"
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(0),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
    }

    struct ReserveData {
        uint256 configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }
}
