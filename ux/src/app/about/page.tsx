function AboutPage() {
  return (
    <div className="page-container">
      <div className="about-container">
        <div className="about-hero">
          <h1 className="about-title">About Ontra</h1>
          <p className="about-subtitle">
            Advanced DeFi Trading with Trailing Stop Loss Protection
          </p>
        </div>

        <div className="about-content">
          <section className="about-section">
            <h2>What is Ontra?</h2>
            <p>
              Ontra is a decentralized exchange protocol built on top of Uniswap
              V4 that provides advanced trading features including automated
              trailing stop loss orders. Our platform helps traders protect
              their positions and maximize profits through intelligent order
              execution.
            </p>
          </section>

          <section className="about-section">
            <h2>Key Features</h2>
            <div className="features-grid">
              <div className="feature-card">
                <div className="feature-icon">🔄</div>
                <h3>Instant Swaps</h3>
                <p>
                  Trade tokens instantly with the best rates powered by Uniswap
                  V4's efficient liquidity pools.
                </p>
              </div>
              <div className="feature-card">
                <div className="feature-icon">📉</div>
                <h3>Trailing Stop Loss</h3>
                <p>
                  Protect your gains with automated trailing stop loss orders
                  that adjust as prices move in your favor.
                </p>
              </div>
              <div className="feature-card">
                <div className="feature-icon">💰</div>
                <h3>Aave Integration</h3>
                <p>
                  Earn yields on your idle liquidity through seamless
                  integration with Aave lending protocol.
                </p>
              </div>
              <div className="feature-card">
                <div className="feature-icon">🔒</div>
                <h3>Secure & Transparent</h3>
                <p>
                  Built on battle-tested smart contracts with full transparency
                  and decentralization.
                </p>
              </div>
            </div>
          </section>

          <section className="about-section">
            <h2>How It Works</h2>
            <ol className="how-it-works">
              <li>Connect your wallet</li>
              <li>Swap tokens or create trailing stop loss orders</li>
              <li>Monitor your positions in the Orders page</li>
              <li>Earn passive income on your liquidity</li>
            </ol>
          </section>

          <section className="about-section">
            <h2>Supported Networks</h2>
            <div className="networks">
              <span className="network-badge">Sepolia testnet</span>
              <span className="network-badge">Ethereum Mainnet (soon)</span>
            </div>
          </section>

          <section className="about-section about-footer">
            <p>Built with ❤️ by ontra team</p>
          </section>
        </div>
      </div>
    </div>
  );
}

export default AboutPage;
