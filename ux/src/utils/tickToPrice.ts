/**
 * Convert a tick to a price
 * Formula: price = 1.0001^tick
 *
 * For USDC/WETH pool:
 * - tick represents the price of WETH in terms of USDC
 * - Higher tick = higher WETH price
 *
 * @param tick The tick value from the pool
 * @returns The price as a number
 */
export function tickToPrice(tick: number): number {
  return Math.pow(1.0001, tick);
}

/**
 * Format a tick as a readable price for display
 *
 * @param tick The tick value
 * @param isLong Whether this is a long position (USDC -> WETH)
 * @returns Formatted price string with currency pair
 */
export function formatTickAsPrice(tick: number, isLong: boolean): string {
  const price = tickToPrice(tick); // WETH price in USDC

  if (isLong) {
    // Long: deposited USDC, will receive WETH at execution
    // Show "1 USDC = X WETH" at execution price
    const usdcToWeth = 1 / price;
    return `${usdcToWeth.toFixed(6)} WETH per USDC`;
  } else {
    // Short: deposited WETH, will receive USDC at execution
    // Show "1 WETH = X USDC" at execution price
    return `${price.toFixed(2)} USDC per WETH`;
  }
}

/**
 * Calculate trigger tick from current tick and trailing percentage
 *
 * @param currentTick The current tick of the pool
 * @param trailingPercent The trailing percentage (5, 10, or 15)
 * @param isLong Whether this is a long position
 * @returns The calculated trigger tick
 */
export function calculateTriggerTick(
  currentTick: number,
  trailingPercent: 5 | 10 | 15,
  isLong: boolean
): number {
  // Calculate tick offset for percentage
  // log(1 - percent/100) / log(1.0001)
  const percentMap = {
    5: -513, // log(0.95) / log(1.0001) ≈ -513
    10: -1054, // log(0.90) / log(1.0001) ≈ -1054
    15: -1625, // log(0.85) / log(1.0001) ≈ -1625
  };

  const tickOffset = percentMap[trailingPercent];

  if (isLong) {
    // Long: trigger when price drops by X%
    return currentTick + tickOffset;
  } else {
    // Short: trigger when price rises by X%
    return currentTick - tickOffset;
  }
}

/**
 * Get the execution price from pool data, or simulate if pool is empty
 *
 * @param poolData The pool data containing trigger ticks (null if pool is empty)
 * @param isLong Whether this is a long position
 * @param currentTick The current tick (used for simulation if pool is empty)
 * @param trailingPercent The trailing percentage (used for simulation if pool is empty)
 * @returns The execution price as a formatted string
 */
export function getExecutionPrice(
  poolData: { triggerTickLong: number; triggerTickShort: number } | null,
  isLong: boolean,
  currentTick?: number,
  trailingPercent?: 5 | 10 | 15
): string {
  // Check if pool has a valid trigger tick for this direction
  if (poolData) {
    const tick = isLong ? poolData.triggerTickLong : poolData.triggerTickShort;
    // If the specific tick for this direction is not 0, use it
    // (tick could be negative, so we check if it's exactly 0 which means uninitialized)
    if (tick !== 0) {
      return formatTickAsPrice(tick, isLong);
    }
  }

  // If pool doesn't exist or specific trigger tick is 0, simulate based on current tick
  if (currentTick !== undefined && trailingPercent !== undefined) {
    const simulatedTick = calculateTriggerTick(
      currentTick,
      trailingPercent,
      isLong
    );
    return formatTickAsPrice(simulatedTick, isLong);
  }

  return "N/A";
}

/**
 * Format current pool price for display
 *
 * @param currentTick The current tick of the pool
 * @param tokenSymbol The token symbol being deposited (USDC or WETH)
 * @returns Formatted price string
 */
export function formatCurrentPrice(
  currentTick: number | undefined,
  tokenSymbol: "USDC" | "WETH"
): string {
  if (currentTick === undefined) return "Loading...";

  const price = tickToPrice(currentTick);

  // The tick always represents WETH price in USDC
  // So we display differently based on which token is selected
  if (tokenSymbol === "USDC") {
    // User selected USDC, show how much WETH they can get per USDC
    // price = WETH in USDC, so 1 USDC = 1/price WETH
    const usdcToWeth = 1 / price;
    return `${usdcToWeth.toFixed(8)} WETH`;
  } else {
    // User selected WETH, show WETH price in USDC
    return `${price.toFixed(2)} USDC`;
  }
}
