"use client";

import { useState, useEffect } from "react";
import { useAccount, useBalance } from "wagmi";
import { formatUnits } from "viem";

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

  const handleSwap = () => {
    console.log("Swap", { fromToken, toToken, fromAmount, toAmount });
  };

  const switchTokens = () => {
    setFromToken(toToken);
    setToToken(fromToken);
    setFromAmount(toAmount);
    setToAmount(fromAmount);
  };

  return (
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
              <span className="balance">Balance: {getBalance(fromToken)}</span>
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

          <button onClick={handleSwap} className="swap-button">
            {isConnected ? "Swap" : "Connect Wallet"}
          </button>
        </div>
      </div>
    </div>
  );
}

export default Page;
