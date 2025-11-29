// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solady/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IPool} from "aave-v3/contracts/interfaces/IPool.sol";
import {IAToken} from "aave-v3/contracts/interfaces/IAToken.sol";
import {DataTypes} from "aave-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {console} from "forge-std/console.sol";

import {MockAavePool} from "./MockAavePool.sol";

import {OntraHook} from "../../../src/OntraHook.sol";

/// @dev Fixture for testing `OntraHook`
contract OntraHookFixture is Test, Deployers {
    OntraHook hook;
    MockAavePool aavePool;

    MockERC20 token0;
    MockERC20 token1;

    function setUp() public virtual {
        // Deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy two test tokens
        deployMintAndApprove2Currencies();

        // Mock Aave Pool
        MockAavePool mockAave = new MockAavePool();
        aavePool = mockAave;

        // Deploy our hook
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG);
        address hookAddress = address(flags);
        // Use deployCodeTo with exact same pattern as workshop tests
        deployCodeTo("OntraHook.sol", abi.encode(manager, address(aavePool)), hookAddress);
        hook = OntraHook(hookAddress);

        // Approve our hook address to spend these tokens as well
        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        // Initialize pool
        (key,) = initPool(
            currency0,
            currency1,
            hook,
            3000, // 0.3% fee
            SQRT_PRICE_1_1 // Initial price 1:1
        );
    }
}
