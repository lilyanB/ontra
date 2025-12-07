// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPool} from "aave-v3/contracts/interfaces/IPool.sol";

import {OntraV2Hook} from "../src/OntraV2Hook.sol";
import {SwapRouterWithLocker} from "../test/unit/utils/SwapRouterWithLocker.sol";

// Base Mainnet
// forge script script/OntraV2Hook.s.sol:OntraV2HookScript --sig "run(address)" $AAVE_POOL_ADDRESS --rpc-url https://mainnet.base.org -i 1 --broadcast

// Sepolia
// forge script script/OntraV2Hook.s.sol:OntraV2HookScript --sig "run(address)" 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951 --rpc-url wss://ethereum-sepolia-rpc.publicnode.com -i 1 --broadcast

contract OntraV2HookScript is Script {
    // https://getfoundry.sh/guides/deterministic-deployments-using-create2/#getting-started
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    // https://docs.uniswap.org/contracts/v4/deployments#sepolia-11155111
    address internal constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;

    function run(address aavePool) external returns (OntraV2Hook ontraV2Hook_, SwapRouterWithLocker swapRouter_) {
        vm.startBroadcast();

        // Deploy SwapRouterWithLocker first
        swapRouter_ = new SwapRouterWithLocker(IPoolManager(POOL_MANAGER));

        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOL_MANAGER, aavePool);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(OntraV2Hook).creationCode, constructorArgs);

        // Deploy the hook using Create2
        ontraV2Hook_ = new OntraV2Hook{salt: salt}(IPoolManager(POOL_MANAGER), aavePool);
        require(address(ontraV2Hook_) == hookAddress, "OntraV2HookScript: hook address mismatch");

        vm.stopBroadcast();
    }
}
