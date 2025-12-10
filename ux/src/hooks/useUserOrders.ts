import { useReadContract, useAccount } from "wagmi";
import { CONTRACTS, getPoolId } from "@/config/contracts";
import { ONTRA_V2_HOOK_ABI } from "@/config/abis";
import { useMemo } from "react";

export interface UserOrder {
  tier: 0 | 1 | 2;
  isLong: boolean;
  epoch: bigint;
  shares: bigint;
  poolData: {
    totalToken0Long: bigint;
    totalToken1Short: bigint;
    totalSharesLong: bigint;
    totalSharesShort: bigint;
    executedToken1: bigint;
    executedToken0: bigint;
    triggerTickLong: number;
    triggerTickShort: number;
  } | null;
}

export function useUserOrders() {
  const { address } = useAccount();
  const poolId = getPoolId();

  // Get epochs for each tier/direction combination (6 calls)
  const { data: epoch0Long } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getCurrentEpoch",
    args: [poolId, 0, true],
  });

  const { data: epoch0Short } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getCurrentEpoch",
    args: [poolId, 0, false],
  });

  const { data: epoch1Long } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getCurrentEpoch",
    args: [poolId, 1, true],
  });

  const { data: epoch1Short } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getCurrentEpoch",
    args: [poolId, 1, false],
  });

  const { data: epoch2Long } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getCurrentEpoch",
    args: [poolId, 2, true],
  });

  const { data: epoch2Short } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getCurrentEpoch",
    args: [poolId, 2, false],
  });

  // Get user shares for each combination
  const { data: shares0Long, refetch: refetch0Long } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getUserShares",
    args:
      address && epoch0Long !== undefined
        ? [address, poolId, 0, true, epoch0Long]
        : undefined,
    query: { enabled: !!address && epoch0Long !== undefined },
  });

  const { data: shares0Short, refetch: refetch0Short } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getUserShares",
    args:
      address && epoch0Short !== undefined
        ? [address, poolId, 0, false, epoch0Short]
        : undefined,
    query: { enabled: !!address && epoch0Short !== undefined },
  });

  const { data: shares1Long, refetch: refetch1Long } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getUserShares",
    args:
      address && epoch1Long !== undefined
        ? [address, poolId, 1, true, epoch1Long]
        : undefined,
    query: { enabled: !!address && epoch1Long !== undefined },
  });

  const { data: shares1Short, refetch: refetch1Short } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getUserShares",
    args:
      address && epoch1Short !== undefined
        ? [address, poolId, 1, false, epoch1Short]
        : undefined,
    query: { enabled: !!address && epoch1Short !== undefined },
  });

  const { data: shares2Long, refetch: refetch2Long } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getUserShares",
    args:
      address && epoch2Long !== undefined
        ? [address, poolId, 2, true, epoch2Long]
        : undefined,
    query: { enabled: !!address && epoch2Long !== undefined },
  });

  const { data: shares2Short, refetch: refetch2Short } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "getUserShares",
    args:
      address && epoch2Short !== undefined
        ? [address, poolId, 2, false, epoch2Short]
        : undefined,
    query: { enabled: !!address && epoch2Short !== undefined },
  });

  // Get pool data for positions with shares
  const { data: pool0Long } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "trailingPools",
    args: epoch0Long !== undefined ? [poolId, 0, epoch0Long] : undefined,
    query: {
      enabled:
        epoch0Long !== undefined &&
        shares0Long !== undefined &&
        Number(shares0Long) > 0,
    },
  });

  const { data: pool0Short } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "trailingPools",
    args: epoch0Short !== undefined ? [poolId, 0, epoch0Short] : undefined,
    query: {
      enabled:
        epoch0Short !== undefined &&
        shares0Short !== undefined &&
        Number(shares0Short) > 0,
    },
  });

  const { data: pool1Long } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "trailingPools",
    args: epoch1Long !== undefined ? [poolId, 1, epoch1Long] : undefined,
    query: {
      enabled:
        epoch1Long !== undefined &&
        shares1Long !== undefined &&
        Number(shares1Long) > 0,
    },
  });

  const { data: pool1Short } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "trailingPools",
    args: epoch1Short !== undefined ? [poolId, 1, epoch1Short] : undefined,
    query: {
      enabled:
        epoch1Short !== undefined &&
        shares1Short !== undefined &&
        Number(shares1Short) > 0,
    },
  });

  const { data: pool2Long } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "trailingPools",
    args: epoch2Long !== undefined ? [poolId, 2, epoch2Long] : undefined,
    query: {
      enabled:
        epoch2Long !== undefined &&
        shares2Long !== undefined &&
        Number(shares2Long) > 0,
    },
  });

  const { data: pool2Short } = useReadContract({
    address: CONTRACTS.OntraV2Hook,
    abi: ONTRA_V2_HOOK_ABI,
    functionName: "trailingPools",
    args: epoch2Short !== undefined ? [poolId, 2, epoch2Short] : undefined,
    query: {
      enabled:
        epoch2Short !== undefined &&
        shares2Short !== undefined &&
        Number(shares2Short) > 0,
    },
  });

  const userOrders = useMemo(() => {
    const orders: UserOrder[] = [];

    const positions = [
      {
        tier: 0 as const,
        isLong: true,
        epoch: epoch0Long,
        shares: shares0Long,
        pool: pool0Long,
      },
      {
        tier: 0 as const,
        isLong: false,
        epoch: epoch0Short,
        shares: shares0Short,
        pool: pool0Short,
      },
      {
        tier: 1 as const,
        isLong: true,
        epoch: epoch1Long,
        shares: shares1Long,
        pool: pool1Long,
      },
      {
        tier: 1 as const,
        isLong: false,
        epoch: epoch1Short,
        shares: shares1Short,
        pool: pool1Short,
      },
      {
        tier: 2 as const,
        isLong: true,
        epoch: epoch2Long,
        shares: shares2Long,
        pool: pool2Long,
      },
      {
        tier: 2 as const,
        isLong: false,
        epoch: epoch2Short,
        shares: shares2Short,
        pool: pool2Short,
      },
    ];

    positions.forEach(({ tier, isLong, epoch, shares, pool }) => {
      if (shares && Number(shares) > 0 && epoch !== undefined) {
        orders.push({
          tier,
          isLong,
          epoch: epoch as bigint,
          shares: shares as bigint,
          poolData: pool
            ? {
                totalToken0Long: (pool as any).totalToken0Long,
                totalToken1Short: (pool as any).totalToken1Short,
                totalSharesLong: (pool as any).totalSharesLong,
                totalSharesShort: (pool as any).totalSharesShort,
                executedToken1: (pool as any).executedToken1,
                executedToken0: (pool as any).executedToken0,
                triggerTickLong: (pool as any).triggerTickLong,
                triggerTickShort: (pool as any).triggerTickShort,
              }
            : null,
        });
      }
    });

    return orders;
  }, [
    epoch0Long,
    epoch0Short,
    epoch1Long,
    epoch1Short,
    epoch2Long,
    epoch2Short,
    shares0Long,
    shares0Short,
    shares1Long,
    shares1Short,
    shares2Long,
    shares2Short,
    pool0Long,
    pool0Short,
    pool1Long,
    pool1Short,
    pool2Long,
    pool2Short,
  ]);

  const refetch = () => {
    refetch0Long();
    refetch0Short();
    refetch1Long();
    refetch1Short();
    refetch2Long();
    refetch2Short();
  };

  return { userOrders, isLoading: false, refetch };
}
