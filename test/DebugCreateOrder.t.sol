// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OntraV2Hook} from "../src/OntraV2Hook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IOntraV2Hook} from "../src/interfaces/IOntraV2Hook.sol";

contract DebugCreateOrderTest is Test {
    address constant ONTRA_V2_HOOK = 0xb842CEB38B4eD22F5189ABcb774168187DEA5040;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant USER = 0x607A577659Cad2A2799120DfdEEde39De2D38706;

    PoolKey key;

    function setUp() public {
        vm.createSelectFork("https://ethereum-sepolia-rpc.publicnode.com");

        key = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(WETH),
            fee: 0,
            tickSpacing: 60,
            hooks: OntraV2Hook(ONTRA_V2_HOOK)
        });
    }

    function testCreateTrailingStop() public {
        vm.startPrank(USER);

        uint256 amount = 1_000_000; // 1 USDC

        console.log("User USDC balance:", IERC20(USDC).balanceOf(USER));
        console.log("User allowance:", IERC20(USDC).allowance(USER, ONTRA_V2_HOOK));
        console.log("Hook address:", address(ONTRA_V2_HOOK));

        // Try to create trailing stop
        try OntraV2Hook(ONTRA_V2_HOOK)
            .createTrailingStop(
                key,
                amount,
                true, // isLong
                IOntraV2Hook.TrailingStopTier.FIVE_PERCENT
            ) returns (
            uint256 shares
        ) {
            console.log("Success! Shares:", shares);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Low level error");
            console.logBytes(lowLevelData);
        }

        vm.stopPrank();
    }
}
