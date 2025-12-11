"use client";

import { useState, useEffect, useMemo } from "react";
import { useAccount, useBalance } from "wagmi";
import { formatUnits, parseUnits } from "viem";
import { useSwap } from "@/hooks/useSwap";
import {
  useApproveToken,
  useTokenAllowance,
  useTierExecutionPrices,
} from "@/hooks/useOntraContract";
import { CONTRACTS } from "@/config/contracts";
import Toast from "@/components/Toast";
import { tickToPrice } from "@/utils/tickToPrice";

const TOKENS = {
  WETH: {
    symbol: "WETH",
    address: "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9" as `0x${string}`,
    decimals: 18,
    icon: "🔵",
  },
  USDC: {
    symbol: "USDC",
    address: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" as `0x${string}`,
    decimals: 6,
    icon: "🟢",
  },
};

function Page() {
  const { address, isConnected } = useAccount();
  const [fromToken, setFromToken] = useState<"WETH" | "USDC">("WETH");
  const [toToken, setToToken] = useState<"WETH" | "USDC">("USDC");
  const [fromAmount, setFromAmount] = useState("");
  const [toAmount, setToAmount] = useState("");

  const [toast, setToast] = useState<{
    message: string;
    type: "pending" | "success" | "error";
  } | null>(null);

  const {
    swap,
    hash: swapHash,
    isPending: isSwapping,
    isConfirming: isSwapConfirming,
    isConfirmed: isSwapConfirmed,
    isConfirmError: isSwapError,
    error: swapError,
    receiptError: swapReceiptError,
  } = useSwap();

  const {
    approveToken,
    isPending: isApproving,
    isConfirming: isApprovingConfirming,
    isConfirmed: isApproved,
    isConfirmError: isApproveError,
  } = useApproveToken(CONTRACTS.SwapRouterWithLocker);

  const { allowance, refetch: refetchAllowance } = useTokenAllowance(
    fromToken,
    address,
    CONTRACTS.SwapRouterWithLocker
  );

  // Get current tick for price calculation
  const { currentTick } = useTierExecutionPrices(fromToken);

  // Calculate output amount based on input and current tick
  useEffect(() => {
    if (fromAmount && currentTick !== undefined && parseFloat(fromAmount) > 0) {
      const price = tickToPrice(currentTick); // WETH price in USDC
      const inputAmount = parseFloat(fromAmount);

      if (fromToken === "WETH") {
        // WETH -> USDC: multiply by price
        const outputAmount = inputAmount * price;
        setToAmount(outputAmount.toFixed(6));
      } else {
        // USDC -> WETH: divide by price
        const outputAmount = inputAmount / price;
        setToAmount(outputAmount.toFixed(8));
      }
    } else if (!fromAmount) {
      setToAmount("");
    }
  }, [fromAmount, currentTick, fromToken]);

  const { data: wethBalance } = useBalance({
    address: address,
    token: TOKENS.WETH.address,
  });

  const { data: usdcBalance } = useBalance({
    address: address,
    token: TOKENS.USDC.address,
  });

  const getBalance = (tokenSymbol: "WETH" | "USDC") => {
    if (!isConnected) return "0.0";

    if (tokenSymbol === "WETH") {
      return wethBalance
        ? parseFloat(
            formatUnits(wethBalance.value, wethBalance.decimals)
          ).toFixed(4)
        : "0.0";
    } else {
      return usdcBalance
        ? parseFloat(
            formatUnits(usdcBalance.value, usdcBalance.decimals)
          ).toFixed(4)
        : "0.0";
    }
  };

  const needsApproval = useMemo(() => {
    if (!fromAmount || !allowance) return false;
    const amountBigInt = parseUnits(fromAmount, TOKENS[fromToken].decimals);
    return allowance < amountBigInt;
  }, [fromAmount, allowance, fromToken]);

  // Refetch allowance when approval is confirmed
  useEffect(() => {
    if (isApproved) {
      refetchAllowance();
    }
  }, [isApproved, refetchAllowance]);

  // Show approval status
  useEffect(() => {
    if (isApprovingConfirming) {
      setToast({ message: "Approval transaction pending...", type: "pending" });
    }
  }, [isApprovingConfirming]);

  useEffect(() => {
    if (isApproved) {
      setToast({ message: "Token approved successfully!", type: "success" });
    }
  }, [isApproved]);

  useEffect(() => {
    if (isApproveError) {
      setToast({ message: "Approval transaction failed", type: "error" });
    }
  }, [isApproveError]);

  // Show swap status
  useEffect(() => {
    if (isSwapConfirming) {
      setToast({ message: "Swap transaction pending...", type: "pending" });
    }
  }, [isSwapConfirming]);

  useEffect(() => {
    if (isSwapConfirmed) {
      setToast({ message: "Swap completed successfully!", type: "success" });
      setFromAmount("");
      setToAmount("");
    }
  }, [isSwapConfirmed]);

  useEffect(() => {
    if (isSwapError) {
      const errorMsg = swapReceiptError?.message || "Transaction reverted";
      const shortHash = swapHash
        ? `${swapHash.slice(0, 10)}...${swapHash.slice(-8)}`
        : "";
      setToast({
        message: `${errorMsg}${
          shortHash ? ` (${shortHash})` : ""
        }. Check Sepolia scan for details.`,
        type: "error",
      });
    }
  }, [isSwapError, swapReceiptError, swapHash]);

  useEffect(() => {
    if (swapError) {
      setToast({ message: `Error: ${swapError.message}`, type: "error" });
    }
  }, [swapError]);

  const handleSwap = async () => {
    if (!address) {
      setToast({ message: "Please connect your wallet", type: "error" });
      return;
    }

    if (!fromAmount || parseFloat(fromAmount) <= 0) {
      setToast({ message: "Please enter a valid amount", type: "error" });
      return;
    }

    if (needsApproval) {
      // First approve the token
      await approveToken(fromToken, fromAmount);
    } else {
      // Execute the swap
      await swap(fromToken, toToken, fromAmount, true);
    }
  };

  const switchTokens = () => {
    setFromToken(toToken);
    setToToken(fromToken);
    setFromAmount(toAmount);
    setToAmount(fromAmount);
  };

  return (
    <>
      {toast && (
        <Toast
          message={toast.message}
          type={toast.type}
          onClose={() => setToast(null)}
        />
      )}
      <div className="page-container">
        <div className="swap-container">
          <div className="swap-header">
            <h1>Swap</h1>
            <button className="settings-btn">⚙️</button>
          </div>

          <div className="swap-card">
            <div className="token-input-container">
              <div className="token-input-header">
                <span className="label">From</span>
                <span className="balance">
                  Balance: {getBalance(fromToken)}
                </span>
              </div>
              <div className="token-input">
                <input
                  type="text"
                  placeholder="0.0"
                  value={fromAmount}
                  onChange={(e) => setFromAmount(e.target.value)}
                  className="amount-input"
                />
                <button className="token-select">
                  <span className="token-icon">{TOKENS[fromToken].icon}</span>
                  {fromToken}
                  <span className="dropdown-arrow">▼</span>
                </button>
              </div>
            </div>

            <div className="swap-arrow-container">
              <button onClick={switchTokens} className="swap-arrow-btn">
                ⇅
              </button>
            </div>

            <div className="token-input-container">
              <div className="token-input-header">
                <span className="label">To</span>
                <span className="balance">Balance: {getBalance(toToken)}</span>
              </div>
              <div className="token-input">
                <input
                  type="text"
                  placeholder="0.0"
                  value={toAmount}
                  onChange={(e) => setToAmount(e.target.value)}
                  className="amount-input"
                />
                <button className="token-select">
                  <span className="token-icon">{TOKENS[toToken].icon}</span>
                  {toToken}
                  <span className="dropdown-arrow">▼</span>
                </button>
              </div>
            </div>

            <button
              onClick={handleSwap}
              className="swap-button"
              disabled={
                isApproving ||
                isApprovingConfirming ||
                isSwapping ||
                isSwapConfirming ||
                !address
              }
            >
              {!address
                ? "Connect Wallet"
                : isApproving || isApprovingConfirming
                ? "Approving..."
                : isSwapping || isSwapConfirming
                ? "Swapping..."
                : needsApproval
                ? "Approve Token"
                : "Swap"}
            </button>
          </div>
        </div>
      </div>
    </>
  );
}

export default Page;
