import {
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
} from "wagmi";
import { parseUnits } from "viem";
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
