// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPool} from "aave-v3/contracts/interfaces/IPool.sol";

import {OntraV2Hook} from "../src/OntraV2Hook.sol";

// Live run: forge script script/OntraV2Hook.s.sol:OntraV2HookScript --sig "run(address)" $AAVE_POOL_ADDRESS --rpc-url https://mainnet.base.org -i 1 --broadcast
// Test run: forge script script/OntraV2Hook.s.sol:OntraV2HookScript --sig "run(address)" $AAVE_POOL_ADDRESS --rpc-url https://mainnet.base.org -i 1 --broadcast

contract OntraV2HookScript is Script {
    // https://getfoundry.sh/guides/deterministic-deployments-using-create2/#getting-started
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    // https://docs.uniswap.org/contracts/v4/deployments#base-sepolia-84532
    address internal constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;

    function run(address aavePool) external {
        (, address sender,) = vm.readCallers();
        vm.startBroadcast(sender);

        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOL_MANAGER, aavePool);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(OntraV2Hook).creationCode, constructorArgs);

        // Deploy the hook using Create2
        OntraV2Hook ontraV2Hook = new OntraV2Hook{salt: salt}(IPoolManager(POOL_MANAGER), aavePool);
        require(address(ontraV2Hook) == hookAddress, "OntraV2HookScript: hook address mismatch");
        vm.stopBroadcast();
    }
}
