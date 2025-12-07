"use client";

import { useState } from "react";

function Page() {
  const [fromToken, setFromToken] = useState("ETH");
  const [toToken, setToToken] = useState("USDC");
  const [fromAmount, setFromAmount] = useState("");
  const [toAmount, setToAmount] = useState("");

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
              <span className="balance">Balance: 0.0</span>
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
                <span className="token-icon">🔵</span>
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
              <span className="balance">Balance: 0.0</span>
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
                <span className="token-icon">🟢</span>
                {toToken}
                <span className="dropdown-arrow">▼</span>
              </button>
            </div>
          </div>

          <button onClick={handleSwap} className="swap-button">
            Swap
          </button>
        </div>
      </div>
    </div>
  );
}

export default Page;
