// Contract addresses on Sepolia
export const CONTRACTS = {
  OntraV2Hook: "0xb842CEB38B4eD22F5189ABcb774168187DEA5040" as `0x${string}`,
  SwapRouterWithLocker:
    "0xe15D86D762A71c44E4559D98f9C44B1e45c7709E" as `0x${string}`,
  PoolManager: "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543" as `0x${string}`,
} as const;

// Pool Key configuration
export const POOL_KEY = {
  currency0: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" as `0x${string}`, // USDC
  currency1: "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9" as `0x${string}`, // WETH
  fee: 0,
  tickSpacing: 60,
  hooks: "0xb842CEB38B4eD22F5189ABcb774168187DEA5040" as `0x${string}`,
} as const;

// Token information
export const TOKENS = {
  USDC: {
    address: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" as `0x${string}`,
    symbol: "USDC",
    decimals: 6,
    icon: "🟢",
  },
  WETH: {
    address: "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9" as `0x${string}`,
    symbol: "WETH",
    decimals: 18,
    icon: "🔵",
  },
} as const;

// Trailing stop tier mapping
export const TRAILING_STOP_TIERS = {
  "5": 0, // FIVE_PERCENT
  "10": 1, // TEN_PERCENT
  "15": 2, // FIFTEEN_PERCENT
} as const;
