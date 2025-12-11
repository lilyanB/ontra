import {
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
} from "wagmi";
import { parseUnits, keccak256, encodeAbiParameters } from "viem";
import { useMemo } from "react";
import {
  CONTRACTS,
  POOL_KEY,
  TOKENS,
  TRAILING_STOP_TIERS,
} from "@/config/contracts";
import { ONTRA_V2_HOOK_ABI, ERC20_ABI } from "@/config/abis";

export function useCreateTrailingStop() {
  const { data: hash, writeContract, isPending, error } = useWriteContract();

  const {
    isLoading: isConfirming,
    isSuccess: isConfirmed,
    isError: isConfirmError,
    error: receiptError,
  } = useWaitForTransactionReceipt({
    hash,
  });

  const createTrailingStop = async (
    tokenSymbol: "USDC" | "WETH",
    amount: string,
    trailingPercent: "5" | "10" | "15"
  ) => {
    const token = TOKENS[tokenSymbol];
    const amountBigInt = parseUnits(amount, token.decimals);
    const tier = TRAILING_STOP_TIERS[trailingPercent];

    // Determine if it's a long or short position
    // Long: depositing currency0 (USDC) to get currency1 (WETH) later
    // Short: depositing currency1 (WETH) to get currency0 (USDC) later
    const isLong =
      token.address.toLowerCase() === POOL_KEY.currency0.toLowerCase();

    writeContract({
      address: CONTRACTS.OntraV2Hook,
      abi: ONTRA_V2_HOOK_ABI,
      functionName: "createTrailingStop",
      args: [POOL_KEY, amountBigInt, isLong, tier],
      gas: 5_000_000n,
    });
  };

  return {
    createTrailingStop,
    hash,
    isPending,
    isConfirming,
    isConfirmed,
    isConfirmError,
    error,
    receiptError,
  };
}

export function useApproveToken() {
  const { data: hash, writeContract, isPending, error } = useWriteContract();

  const {
    isLoading: isConfirming,
    isSuccess: isConfirmed,
    isError: isConfirmError,
  } = useWaitForTransactionReceipt({
    hash,
  });

  const approveToken = async (tokenSymbol: "USDC" | "WETH", amount: string) => {
    const token = TOKENS[tokenSymbol];
    const amountBigInt = parseUnits(amount, token.decimals);

    writeContract({
      address: token.address,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [CONTRACTS.OntraV2Hook, amountBigInt],
    });
  };

  return {
    approveToken,
    hash,
    isPending,
    isConfirming,
    isConfirmed,
    isConfirmError,
    error,
  };
}

export function useTokenAllowance(
  tokenSymbol: "USDC" | "WETH" | undefined,
  userAddress: `0x${string}` | undefined
) {
  const token = tokenSymbol ? TOKENS[tokenSymbol] : undefined;

  const { data: allowance, refetch } = useReadContract({
    address: token?.address,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress ? [userAddress, CONTRACTS.OntraV2Hook] : undefined,
    query: {
      enabled: !!token && !!userAddress,
    },
  });

  return { allowance: allowance as bigint | undefined, refetch };
}

export function useTierExecutionPrices(
  tokenSymbol: "USDC" | "WETH" | undefined
) {
  const token = tokenSymbol ? TOKENS[tokenSymbol] : undefined;
  const isLong = token
    ? token.address.toLowerCase() === POOL_KEY.currency0.toLowerCase()
    : false;

  const poolId = useMemo(() => {
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
  }, []);

  // Get current epochs for each tier
  const { data: epoch0 } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getCurrentEpoch",
    args: token ? [poolId, 0, isLong] : undefined,
    query: { enabled: !!token },
  });

  const { data: epoch1 } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getCurrentEpoch",
    args: token ? [poolId, 1, isLong] : undefined,
    query: { enabled: !!token },
  });

  const { data: epoch2 } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getCurrentEpoch",
    args: token ? [poolId, 2, isLong] : undefined,
    query: { enabled: !!token },
  });

  // Get pool data for each tier
  const { data: pool0 } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "trailingPools",
    args: epoch0 !== undefined ? [poolId, 0, epoch0] : undefined,
    query: { enabled: epoch0 !== undefined },
  });

  const { data: pool1 } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "trailingPools",
    args: epoch1 !== undefined ? [poolId, 1, epoch1] : undefined,
    query: { enabled: epoch1 !== undefined },
  });

  const { data: pool2 } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "trailingPools",
    args: epoch2 !== undefined ? [poolId, 2, epoch2] : undefined,
    query: { enabled: epoch2 !== undefined },
  });

  // Get current tick from the hook
  const { data: lastTick } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getLastTick",
    args: [poolId],
    query: { enabled: !!token },
  });

  return {
    tier5: pool0
      ? {
          triggerTickLong: (pool0 as any).triggerTickLong,
          triggerTickShort: (pool0 as any).triggerTickShort,
        }
      : { triggerTickLong: 0, triggerTickShort: 0 },
    tier10: pool1
      ? {
          triggerTickLong: (pool1 as any).triggerTickLong,
          triggerTickShort: (pool1 as any).triggerTickShort,
        }
      : { triggerTickLong: 0, triggerTickShort: 0 },
    tier15: pool2
      ? {
          triggerTickLong: (pool2 as any).triggerTickLong,
          triggerTickShort: (pool2 as any).triggerTickShort,
        }
      : { triggerTickLong: 0, triggerTickShort: 0 },
    currentTick: lastTick as number | undefined,
    isLong,
  };
}
