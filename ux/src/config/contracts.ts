// Contract addresses on Sepolia
export const CONTRACTS = {
  OntraV2Hook: "0xf31816Eeb789f4A1C13e8982E85426A9E1e59040" as `0x${string}`,
  SwapRouterWithLocker:
    "0xBD4C0Bea25557683EECCb2c5b7Bb50E3b806896a" as `0x${string}`,
  PoolManager: "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543" as `0x${string}`,
  MockAavePool: "0xfcAEE36D3df9d2eBf114cfcD0A628a0bbeBA2fBC" as `0x${string}`,
} as const;

// Pool Key configuration
export const POOL_KEY = {
  currency0: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" as `0x${string}`, // USDC
  currency1: "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9" as `0x${string}`, // WETH
  fee: 0,
  tickSpacing: 60,
  hooks: "0xf31816Eeb789f4A1C13e8982E85426A9E1e59040" as `0x${string}`,
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

import { keccak256, encodeAbiParameters } from "viem";

// Helper to compute PoolId (keccak256 of PoolKey)
export function getPoolId(): `0x${string}` {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "address", name: "currency0" },
        { type: "address", name: "currency1" },
        { type: "uint24", name: "fee" },
        { type: "int24", name: "tickSpacing" },
        { type: "address", name: "hooks" },
      ],
      [
        POOL_KEY.currency0,
        POOL_KEY.currency1,
        POOL_KEY.fee,
        POOL_KEY.tickSpacing,
        POOL_KEY.hooks,
      ]
    )
  ) as `0x${string}`;
}
