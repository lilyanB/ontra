// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

/// @title Ontra Interface
interface IOntraHook {
    /**
     * @notice Struct used to pass data to callbacks during pool operations.
     * @param sender The address initiating the pool operation.
     * @param key The PoolKey of the pool involved in the operation.
     * @param tickLower The lower tick of the position being modified.
     * @param tickUpper The upper tick of the position being modified.
     * @param liquidityDelta The change in liquidity for the position.
     * @param amount0 The amount of token0 involved in the operation.
     * @param amount1 The amount of token1 involved in the operation.
     * @param isAdd A boolean indicating if liquidity is being added (true) or removed (false).
     * @param isRebalancing A boolean indicating if the callback is triggered during a rebalance operation.
     */
    struct CallbackData {
        address sender;
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        uint256 amount0;
        uint256 amount1;
        bool isAdd;
        bool isRebalancing;
    }

    /**
     * @notice Struct representing a liquidity position managed by Ontra.
     * @param owner The user owner of the position.
     * @param poolId The PoolId of the Uniswap V4 pool where the position is held.
     * @param tickLower The lower tick of the position.
     * @param tickUpper The upper tick of the position.
     * @param liquidity The amount of liquidity in the position.
     * @param isInRange Whether the position is currently in range (true) or out of range (false).
     * @param amount0OnAave The amount of token0 deposited on Aave when the position is out of range.
     * @param amount1OnAave The amount of token1 deposited on Aave when the position is out of range.
     */
    struct PositionInfo {
        address owner;
        PoolId poolId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        bool isInRange;
        uint256 amount0OnAave; // Amount on Aave when out of range
        uint256 amount1OnAave; // Amount on Aave when out of range
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when a position is added.
     * @param owner Owner of the position.
     * @param positionKey Unique key of the position.
     * @param isInPool Whether the position is added to the pool (true) or Aave (false).
     * @param liquidity Amount of liquidity added.
     * @param amount0 Amount of token0 added.
     * @param amount1 Amount of token1 added.
     */
    event OntraPositionAdded(
        address indexed owner,
        bytes32 indexed positionKey,
        bool isInPool,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /**
     * @notice Emitted when a position is removed.
     * @param owner Owner of the position.
     * @param positionKey Unique key of the position.
     * @param amount0 Amount of token0 withdrawn.
     * @param amount1 Amount of token1 withdrawn.
     */
    event OntraPositionRemoved(address indexed owner, bytes32 indexed positionKey, uint256 amount0, uint256 amount1);

    /**
     * @notice Emitted when a position is rebalanced to Aave.
     * @param owner Owner of the position.
     * @param positionKey Unique key of the position.
     * @param amount0 Amount of token0 moved to Aave.
     * @param amount1 Amount of token1 moved to Aave.
     */
    event OntraPositionRebalancedToAave(
        address indexed owner, bytes32 indexed positionKey, uint256 amount0, uint256 amount1
    );
    /**
     * @notice Emitted when a position is rebalanced to the pool.
     * @param owner Owner of the position.
     * @param positionKey Unique key of the position.
     * @param liquidity Amount of liquidity moved to the pool.
     */
    event OntraPositionRebalancedToPool(address indexed owner, bytes32 indexed positionKey, uint128 liquidity);

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Address cannot be the zero address.
    error OntraZeroAddress();

    /// @notice Position does not exist.
    error OntraNoPosition();

    /// @notice Position has no liquidity.
    error OntraNoLiquidity();

    /// @notice Not enough liquidity to remove.
    error OntraNotEnoughLiquidity();

    /// @notice Position is already in Aave.
    error OntraPositionAlreadyInAave();

    /// @notice Position is already in the pool.
    error OntraPositionAlreadyInPool();

    /// @notice Position is not in Aave.
    error OntraPositionNotInAave();

    /// @notice Not enough tokens deposited on Aave.
    error OntraNotEnoughOnAave();

    /* -------------------------------------------------------------------------- */
    /*                                  Functions                                 */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                                   Public                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get the position key for a user's position.
     * @param owner Owner of the position.
     * @param poolId Pool ID.
     * @param tickLower Lower tick.
     * @param tickUpper Upper tick.
     * @return key_ The unique key for this position.
     */
    function getPositionKey(address owner, PoolId poolId, int24 tickLower, int24 tickUpper)
        external
        pure
        returns (bytes32 key_);

    /* -------------------------------------------------------------------------- */
    /*                                  External                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Add liquidity through the hook - tokens are deposited to Aave.
     * @dev Should be called from a contract that makes safety checks, like the {OntraRouter}.
     * @param key PoolKey of the pool.
     * @param tickLower Lower tick of the position.
     * @param tickUpper Upper tick of the position.
     * @param amount0Desired Desired amount of token0 to add.
     * @param amount1Desired Desired amount of token1 to add.
     * @return liquidity_ Amount of liquidity added.
     */
    function addLiquidity(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint128 liquidity_);

    /**
     * @notice Remove liquidity through the hook - tokens are withdrawn from the pool.
     * @param key PoolKey of the pool.
     * @param tickLower Lower tick of the position.
     * @param tickUpper Upper tick of the position.
     * @param liquidityToRemove Amount of liquidity to remove.
     * @return amount0_ Amount of token0 withdrawn.
     * @return amount1_ Amount of token1 withdrawn.
     */
    function removeLiquidity(PoolKey calldata key, int24 tickLower, int24 tickUpper, uint128 liquidityToRemove)
        external
        returns (uint256 amount0_, uint256 amount1_);

    /**
     * @notice Remove tokens from Aave for a position that is out of range.
     * @param key PoolKey of the pool.
     * @param tickLower Lower tick of the position.
     * @param tickUpper Upper tick of the position.
     * @param amount0ToRemove Amount of token0 to remove.
     * @param amount1ToRemove Amount of token1 to remove.
     * @return amount0_ Amount of token0 withdrawn.
     * @return amount1_ Amount of token1 withdrawn.
     */
    function removeTokensFromAave(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0ToRemove,
        uint256 amount1ToRemove
    ) external returns (uint256 amount0_, uint256 amount1_);

    /**
     * @notice Unlock callback to handle add/remove liquidity.
     * @dev Can be called only by the pool manager.
     * @param data Encoded CallbackData.
     * @return result_ Encoded result depending on add/remove liquidity.
     */
    function unlockCallback(bytes calldata data) external returns (bytes memory result_);

    /**
     * @notice Rebalance a position from the pool to Aave when out of range.
     * @dev Can be called by anyone to move an out-of-range position to Aave.
     * @param owner Owner of the position.
     * @param key PoolKey of the pool.
     * @param tickLower Lower tick of the position.
     * @param tickUpper Upper tick of the position.
     */
    function rebalanceToAave(address owner, PoolKey calldata key, int24 tickLower, int24 tickUpper) external;
}
