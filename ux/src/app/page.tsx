"use client";

import { useState, useEffect } from "react";
import { useAccount, useBalance } from "wagmi";
import { formatUnits } from "viem";

const TOKENS = {
  ETH: {
    symbol: "ETH",
    address: null,
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
  const [fromToken, setFromToken] = useState<"ETH" | "USDC">("ETH");
  const [toToken, setToToken] = useState<"ETH" | "USDC">("USDC");
  const [fromAmount, setFromAmount] = useState("");
  const [toAmount, setToAmount] = useState("");

  const { data: ethBalance } = useBalance({
    address: address,
  });

  const { data: usdcBalance } = useBalance({
    address: address,
    token: TOKENS.USDC.address,
  });

  const getBalance = (tokenSymbol: "ETH" | "USDC") => {
    if (!isConnected) return "0.0";

    if (tokenSymbol === "ETH") {
      return ethBalance
        ? parseFloat(
            formatUnits(ethBalance.value, ethBalance.decimals)
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
