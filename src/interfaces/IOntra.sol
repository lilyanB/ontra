// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title Ontra Interface
interface IOntra {
    /**
     * @notice Struct representing the collateral state and Aave investment status for a collateral vault asset.
     * @param totalBalance The total number of deposited assets. For non-idle assets, this is the scaled balance deposited
     * in Aave.
     * @param totalShares The total number of minted shares for that asset.
     * @param isIdle Whether the assets remain in the vault (true) or are invested in Aave (false).
     * @param forceIdle Flag to disable Aave integration, true to force collateral in vault, false otherwise.
     */
    struct AssetData {
        uint256 totalBalance;
        uint256 totalShares;
        bool isIdle;
        bool forceIdle;
    }

    /**
     * @notice Struct containing Aave support, reserve status flags, and migration requirement.
     * @param supported True if the token is supported on Aave, false otherwise.
     * @param frozen True if the token reserve is frozen on Aave, false otherwise.
     * @param paused True if the token reserve is paused on Aave, false otherwise.
     * @param migrateAsset True if the token should be migrated between the vault and Aave based on current support.
     */
    struct AaveAssetSupport {
        bool supported;
        bool frozen;
        bool paused;
        bool migrateAsset;
    }
}
