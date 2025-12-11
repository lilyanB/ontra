import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseUnits } from "viem";
import { CONTRACTS, POOL_KEY, TOKENS } from "@/config/contracts";
import { SWAP_ROUTER_ABI } from "@/config/abis";

export function useSwap() {
  const { data: hash, writeContract, isPending, error } = useWriteContract();

  const {
    isLoading: isConfirming,
    isSuccess: isConfirmed,
    isError: isConfirmError,
    error: receiptError,
  } = useWaitForTransactionReceipt({
    hash,
  });

  const swap = async (
    fromToken: "USDC" | "WETH",
    toToken: "USDC" | "WETH",
    amount: string,
    isExactInput: boolean = true
  ) => {
    const fromTokenInfo = TOKENS[fromToken];
    const toTokenInfo = TOKENS[toToken];
    const amountBigInt = parseUnits(amount, fromTokenInfo.decimals);

    // Determine swap direction
    // zeroForOne: true if swapping currency0 (USDC) for currency1 (WETH)
    const zeroForOne = fromToken === "USDC";

    // amountSpecified: negative for exact input, positive for exact output
    const amountSpecified = isExactInput ? -amountBigInt : amountBigInt;

    // sqrtPriceLimitX96: min/max price limit to prevent excessive slippage
    // For zeroForOne (USDC->WETH), use MIN_SQRT_PRICE + 1
    // For oneForZero (WETH->USDC), use MAX_SQRT_PRICE - 1
    const MIN_SQRT_PRICE = BigInt("4295128739");
    const MAX_SQRT_PRICE = BigInt(
      "1461446703485210103287273052203988822378723970342"
    );
    const sqrtPriceLimitX96 = zeroForOne
      ? MIN_SQRT_PRICE + BigInt(1)
      : MAX_SQRT_PRICE - BigInt(1);

    writeContract({
      address: CONTRACTS.SwapRouterWithLocker,
      abi: SWAP_ROUTER_ABI,
      functionName: "swap",
      args: [
        POOL_KEY,
        {
          zeroForOne,
          amountSpecified,
          sqrtPriceLimitX96,
        },
        {
          takeClaims: false,
          settleUsingBurn: false,
        },
        "0x", // empty hookData
      ],
      gas: 5_000_000n,
    });
  };

  return {
    swap,
    hash,
    isPending,
    isConfirming,
    isConfirmed,
    isConfirmError,
    error,
    receiptError,
  };
}
