// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockAavePool} from "../src/workshop/MockAavePool.sol";

// Unichain Sepolia
// forge script script/DeployMockAave.s.sol:DeployMockAaveScript --rpc-url https://unichain-sepolia-rpc.publicnode.com --sender 0x607A577659Cad2A2799120DfdEEde39De2D38706 -i 1 --broadcast

contract DeployMockAaveScript is Script {
    function run() external returns (MockAavePool mockAave) {
        // Get the actual caller address
        (, address sender,) = vm.readCallers();

        vm.startBroadcast(sender);

        mockAave = new MockAavePool();

        console.log("MockAavePool deployed at:", address(mockAave));

        vm.stopBroadcast();

        return mockAave;
    }
}
