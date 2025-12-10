// Minimal OntraV2Hook ABI - only the functions we need
export const ONTRA_V2_HOOK_ABI = [
  {
    inputs: [
      {
        components: [
          { internalType: "Currency", name: "currency0", type: "address" },
          { internalType: "Currency", name: "currency1", type: "address" },
          { internalType: "uint24", name: "fee", type: "uint24" },
          { internalType: "int24", name: "tickSpacing", type: "int24" },
          { internalType: "contract IHooks", name: "hooks", type: "address" },
        ],
        internalType: "struct PoolKey",
        name: "key",
        type: "tuple",
      },
      { internalType: "uint256", name: "amount", type: "uint256" },
      { internalType: "bool", name: "isLong", type: "bool" },
      {
        internalType: "enum IOntraV2Hook.TrailingStopTier",
        name: "tier",
        type: "uint8",
      },
    ],
    name: "createTrailingStop",
    outputs: [{ internalType: "uint256", name: "shares", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        components: [
          { internalType: "Currency", name: "currency0", type: "address" },
          { internalType: "Currency", name: "currency1", type: "address" },
          { internalType: "uint24", name: "fee", type: "uint24" },
          { internalType: "int24", name: "tickSpacing", type: "int24" },
          { internalType: "contract IHooks", name: "hooks", type: "address" },
        ],
        internalType: "struct PoolKey",
        name: "key",
        type: "tuple",
      },
      { internalType: "uint256", name: "shares", type: "uint256" },
      { internalType: "bool", name: "isLong", type: "bool" },
      {
        internalType: "enum IOntraV2Hook.TrailingStopTier",
        name: "tier",
        type: "uint8",
      },
      { internalType: "uint256", name: "epoch", type: "uint256" },
    ],
    name: "withdrawTrailingStop",
    outputs: [{ internalType: "uint256", name: "amountOut", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "user", type: "address" },
      { internalType: "PoolId", name: "poolId", type: "bytes32" },
      {
        internalType: "enum IOntraV2Hook.TrailingStopTier",
        name: "tier",
        type: "uint8",
      },
      { internalType: "bool", name: "isLong", type: "bool" },
      { internalType: "uint256", name: "epoch", type: "uint256" },
    ],
    name: "getUserShares",
    outputs: [{ internalType: "uint256", name: "shares", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "PoolId", name: "poolId", type: "bytes32" },
      {
        internalType: "enum IOntraV2Hook.TrailingStopTier",
        name: "tier",
        type: "uint8",
      },
      { internalType: "bool", name: "isLong", type: "bool" },
    ],
    name: "getCurrentEpoch",
    outputs: [{ internalType: "uint256", name: "epoch", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "PoolId", name: "poolId", type: "bytes32" },
      {
        internalType: "enum IOntraV2Hook.TrailingStopTier",
        name: "tier",
        type: "uint8",
      },
      { internalType: "uint256", name: "epoch", type: "uint256" },
    ],
    name: "trailingPools",
    outputs: [
      {
        components: [
          { internalType: "int24", name: "highestTickEver", type: "int24" },
          { internalType: "int24", name: "lowestTickEver", type: "int24" },
          { internalType: "int24", name: "triggerTickLong", type: "int24" },
          { internalType: "int24", name: "triggerTickShort", type: "int24" },
          { internalType: "uint256", name: "totalToken0Long", type: "uint256" },
          { internalType: "uint256", name: "totalToken1Short", type: "uint256" },
          { internalType: "uint256", name: "totalSharesLong", type: "uint256" },
          { internalType: "uint256", name: "totalSharesShort", type: "uint256" },
          { internalType: "uint256", name: "executedToken1", type: "uint256" },
          { internalType: "uint256", name: "executedToken0", type: "uint256" },
          { internalType: "uint256", name: "aaveDepositedToken0Long", type: "uint256" },
          { internalType: "uint256", name: "aaveDepositedToken1Short", type: "uint256" },
        ],
        internalType: "struct IOntraV2Hook.TrailingStopPool",
        name: "pool",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
] as const;

// ERC20 ABI for token approval
export const ERC20_ABI = [
  {
    inputs: [
      { internalType: "address", name: "spender", type: "address" },
      { internalType: "uint256", name: "amount", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ internalType: "bool", name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "owner", type: "address" },
      { internalType: "address", name: "spender", type: "address" },
    ],
    name: "allowance",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;
