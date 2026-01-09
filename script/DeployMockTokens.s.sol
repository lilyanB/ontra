// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

// Unichain
// forge script script/DeployMockTokens.s.sol:DeployMockTokensScript --rpc-url https://unichain-sepolia-rpc.publicnode.com --sender 0x607A577659Cad2A2799120DfdEEde39De2D38706 -i 1 --broadcast

// Sepolia
// forge script script/DeployMockTokens.s.sol:DeployMockTokensScript --rpc-url https://ethereum-sepolia-rpc.publicnode.com --sender 0x607A577659Cad2A2799120DfdEEde39De2D38706 -i 1 --broadcast

contract DeployMockTokensScript is Script {
    function run() external returns (MockERC20 usdc, MockERC20 weth) {
        (, address sender,) = vm.readCallers();

        vm.startBroadcast(sender);

        usdc = new MockERC20("Mock USDC", "USDC", 6);
        console.log("Mock USDC deployed at:", address(usdc));
        weth = new MockERC20("Mock WETH", "WETH", 18);
        console.log("Mock WETH deployed at:", address(weth));

        // USDC: 1,000,000 USDC (with 6 decimals)
        uint256 usdcAmount = 1_000_000 * 10 ** 6;
        usdc.mint(sender, usdcAmount);
        console.log("Minted", usdcAmount / 10 ** 6, "USDC to:", sender);
        // WETH: 1,000 WETH (with 18 decimals)
        uint256 wethAmount = 1_000 * 10 ** 18;
        weth.mint(sender, wethAmount);
        console.log("Minted", wethAmount / 10 ** 18, "WETH to:", sender);

        vm.stopBroadcast();

        return (usdc, weth);
    }
}
