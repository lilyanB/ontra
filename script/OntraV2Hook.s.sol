// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPool} from "aave-v3/contracts/interfaces/IPool.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {OntraV2Hook} from "../src/OntraV2Hook.sol";
import {SwapRouterWithLocker} from "../test/unit/utils/SwapRouterWithLocker.sol";

// Base Mainnet
// forge script script/OntraV2Hook.s.sol:OntraV2HookScript --sig "run(address)" $AAVE_POOL_ADDRESS --rpc-url https://mainnet.base.org -i 1 --broadcast

// Sepolia
// forge script script/OntraV2Hook.s.sol:OntraV2HookScript --sig "run(address,address,address)" 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9 --rpc-url wss://ethereum-sepolia-rpc.publicnode.com -i 1 --broadcast

contract OntraV2HookScript is Script {
    // https://getfoundry.sh/guides/deterministic-deployments-using-create2/#getting-started
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    // https://docs.uniswap.org/contracts/v4/deployments#sepolia-11155111
    address internal constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    // SQRT_PRICE_1_1 = sqrt(1) * 2^96 = 79228162514264337593543950336
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    bytes internal constant ZERO_BYTES = "";

    function run(address aavePool, address usdc, address weth)
        external
        returns (OntraV2Hook ontraV2Hook_, SwapRouterWithLocker swapRouter_, PoolKey memory key_)
    {
        // Get the actual caller address
        (, address sender,) = vm.readCallers();

        vm.startBroadcast(sender);

        // Deploy SwapRouterWithLocker first
        swapRouter_ = new SwapRouterWithLocker(IPoolManager(POOL_MANAGER));

        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOL_MANAGER, aavePool, sender);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(OntraV2Hook).creationCode, constructorArgs);

        // Deploy the hook using Create2
        ontraV2Hook_ = new OntraV2Hook{salt: salt}(IPoolManager(POOL_MANAGER), aavePool, sender);
        require(address(ontraV2Hook_) == hookAddress, "OntraV2HookScript: hook address mismatch");

        // Set router as verified
        ontraV2Hook_.setRouter(address(swapRouter_), true);

        // Setup tokens - ensure currency0 < currency1
        Currency currency0;
        Currency currency1;
        if (usdc < weth) {
            currency0 = Currency.wrap(usdc);
            currency1 = Currency.wrap(weth);
        } else {
            currency0 = Currency.wrap(weth);
            currency1 = Currency.wrap(usdc);
        }

        // Approve tokens for hook, swap router, and pool manager
        IERC20(usdc).approve(address(ontraV2Hook_), type(uint256).max);
        IERC20(weth).approve(address(ontraV2Hook_), type(uint256).max);
        IERC20(usdc).approve(address(swapRouter_), type(uint256).max);
        IERC20(weth).approve(address(swapRouter_), type(uint256).max);
        IERC20(usdc).approve(address(POOL_MANAGER), type(uint256).max);
        IERC20(weth).approve(address(POOL_MANAGER), type(uint256).max);

        // Initialize the pool
        key_ = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 0, // 0% fee
            tickSpacing: 60,
            hooks: IHooks(address(ontraV2Hook_))
        });

        IPoolManager(POOL_MANAGER).initialize(key_, SQRT_PRICE_1_1);

        // Deploy PoolModifyLiquidityTest router for adding liquidity
        PoolModifyLiquidityTest modifyLiquidityRouter = new PoolModifyLiquidityTest(IPoolManager(POOL_MANAGER));

        // Approve tokens for the modify liquidity router
        IERC20(usdc).approve(address(modifyLiquidityRouter), type(uint256).max);
        IERC20(weth).approve(address(modifyLiquidityRouter), type(uint256).max);

        // Add minimal liquidity just to enable swaps
        // Range of ±1200 ticks (~12% movement) should be sufficient for testing
        modifyLiquidityRouter.modifyLiquidity(
            key_,
            ModifyLiquidityParams({
                tickLower: -1200, // ~1% below current price
                tickUpper: 1200, // ~1% above current price
                liquidityDelta: 10000, // Minimal liquidity
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        vm.stopBroadcast();
    }
}
