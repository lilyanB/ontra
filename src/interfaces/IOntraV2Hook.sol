// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IPool} from "aave-v3/contracts/interfaces/IPool.sol";

/// @title OntraV2 Interface - Trailing Stop Orders with Pooled Shares
interface IOntraV2Hook {
    /* -------------------------------------------------------------------------- */
    /*                                   Enums                                    */
    /* -------------------------------------------------------------------------- */

    enum TrailingStopTier {
        FIVE_PERCENT, // 500 basis points
        TEN_PERCENT, // 1000 basis points
        FIFTEEN_PERCENT // 1500 basis points
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Structs                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Represents a pooled trailing stop for a specific tier and epoch
     * @param highestTickEver The highest tick reached (for long positions)
     * @param lowestTickEver The lowest tick reached (for short positions)
     * @param triggerTickLong The tick that triggers execution for long positions
     * @param triggerTickShort The tick that triggers execution for short positions
     * @param totalToken0Long Total token0 deposited for long positions (token0->token1)
     * @param totalToken1Short Total token1 deposited for short positions (token1->token0)
     * @param totalSharesLong Total shares issued for long positions
     * @param totalSharesShort Total shares issued for short positions
     * @param executedToken1 Amount of token1 received after long execution
     * @param executedToken0 Amount of token0 received after short execution
     */
    struct TrailingStopPool {
        int24 highestTickEver;
        int24 lowestTickEver;
        int24 triggerTickLong;
        int24 triggerTickShort;
        uint256 totalToken0Long;
        uint256 totalToken1Short;
        uint256 totalSharesLong;
        uint256 totalSharesShort;
        uint256 executedToken1;
        uint256 executedToken0;
    }

    /**
     * @notice Data passed to swap callback
     * @param key The pool key
     * @param zeroForOne Direction of the swap
     * @param amountSpecified Amount to swap
     */
    struct SwapCallbackData {
        PoolKey key;
        bool zeroForOne;
        int256 amountSpecified;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when a user adds to a trailing stop pool
     * @param user The user adding funds
     * @param poolId The pool ID
     * @param amount Amount of tokens deposited
     * @param shares Number of shares received
     * @param isLong Whether it's a long (true) or short (false) position
     * @param tier The trailing stop tier
     */
    event TrailingStopCreated(
        address indexed user,
        PoolId indexed poolId,
        uint256 amount,
        uint256 shares,
        bool isLong,
        TrailingStopTier tier,
        uint256 epoch
    );

    /**
     * @notice Emitted when long trailing stops are executed
     * @param poolId The pool ID
     * @param tier The tier that was executed
     * @param epoch The epoch that was executed
     * @param amount0In Amount of token0 swapped
     * @param amount1Out Amount of token1 received
     * @param executionTick The tick at execution
     */
    event TrailingStopExecutedLong(
        PoolId indexed poolId,
        TrailingStopTier indexed tier,
        uint256 epoch,
        uint256 amount0In,
        uint256 amount1Out,
        int24 executionTick
    );

    /**
     * @notice Emitted when short trailing stops are executed
     * @param poolId The pool ID
     * @param tier The tier that was executed
     * @param epoch The epoch that was executed
     * @param amount1In Amount of token1 swapped
     * @param amount0Out Amount of token0 received
     * @param executionTick The tick at execution
     */
    event TrailingStopExecutedShort(
        PoolId indexed poolId,
        TrailingStopTier indexed tier,
        uint256 epoch,
        uint256 amount1In,
        uint256 amount0Out,
        int24 executionTick
    );

    /**
     * @notice Emitted when a user withdraws from their trailing stop shares
     * @param user The user withdrawing
     * @param poolId The pool ID
     * @param shares Number of shares withdrawn
     * @param amountWithdrawn Amount withdrawn
     * @param isLong Whether withdrawing from long or short
     * @param tier The tier
     * @param epoch The epoch ID
     */
    event TrailingStopWithdrawn(
        address indexed user,
        PoolId indexed poolId,
        uint256 shares,
        uint256 amountWithdrawn,
        bool isLong,
        TrailingStopTier tier,
        uint256 epoch
    );

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */

    error NoShares();
    error NoTokens();
    error InvalidTier();
    error AlreadyExecuted();

    /* -------------------------------------------------------------------------- */
    /*                              Public Functions                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Adds to a trailing stop pool and receives shares
     * @param key The pool key
     * @param amount Amount of tokens to deposit
     * @param isLong true = long position (token0->token1), false = short position (token1->token0)
     * @param tier The trailing stop tier (5%, 10%, or 15%)
     * @return shares Number of shares received
     */
    function createTrailingStop(PoolKey calldata key, uint256 amount, bool isLong, TrailingStopTier tier)
        external
        returns (uint256 shares);

    /**
     * @notice Withdraws proportional share from a trailing stop pool
     * @param key The pool key
     * @param shares Number of shares to withdraw
     * @param isLong Whether to withdraw from long or short pool
     * @param tier The tier of the pool
     * @param epoch The epoch to withdraw from
     * @return amountWithdrawn Amount withdrawn
     */
    function withdrawTrailingStop(
        PoolKey calldata key,
        uint256 shares,
        bool isLong,
        TrailingStopTier tier,
        uint256 epoch
    ) external returns (uint256 amountWithdrawn);

    /**
     * @notice Manual execution function (can be called by anyone)
     * @param key The pool key
     * @param tier The tier to check and execute
     */
    function executeTrailingStops(PoolKey calldata key, TrailingStopTier tier) external;

    /**
     * @notice Callback function for pool manager unlocks
     * @param data Encoded callback data
     * @return result Encoded result data
     */
    function unlockCallback(bytes calldata data) external returns (bytes memory result);

    /* -------------------------------------------------------------------------- */
    /*                               View Functions                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Returns the Aave pool address
     * @return The Aave pool contract
     */
    function AAVE_POOL() external view returns (IPool);

    /**
     * @notice Returns the last recorded tick for a pool
     * @param poolId The pool ID
     * @return The last tick
     */
    function lastTicks(PoolId poolId) external view returns (int24);

    /**
     * @notice Returns trailing stop pool data
     * @param poolId The pool ID
     * @param tier The tier
     * @param epoch The epoch
     * @return pool The trailing stop pool data
     */
    function trailingPools(PoolId poolId, TrailingStopTier tier, uint256 epoch)
        external
        view
        returns (TrailingStopPool memory pool);

    /**
     * @notice Returns a user's shares for a specific pool, tier, direction and epoch
     * @param user The user address
     * @param poolId The pool ID
     * @param tier The tier
     * @param isLong Whether to get long or short shares
     * @param epoch The epoch
     * @return shares The user's shares
     */
    function getUserShares(address user, PoolId poolId, TrailingStopTier tier, bool isLong, uint256 epoch)
        external
        view
        returns (uint256 shares);

    /**
     * @notice Returns the current active epoch for a pool/tier/direction
     * @param poolId The pool ID
     * @param tier The tier
     * @param isLong Whether to get long or short epoch
     * @return epoch The current epoch ID
     */
    function getCurrentEpoch(PoolId poolId, TrailingStopTier tier, bool isLong) external view returns (uint256 epoch);
}
