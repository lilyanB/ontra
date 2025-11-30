# UHI Hookathon 2025

## Project Name:

Ontra

## Description:

Ontra — The On-Chain Trading Engine Ontra is a Uniswap v4 Hook that brings institutional-grade execution directly on-chain. The core idea is a Rehypothecation Hook: any LP liquidity or order liquidity that is not currently active is automatically deposited into Aave to earn yield. When liquidity becomes needed again, the Hook withdraws it in a single batch to minimize gas. Ontra provides an on-chain execution layer supporting: Limit orders TWAP orders (30s / 1m / 5m packs) Trailing stop orders (5% / 10% / 15% pools) Hidden orders secured with Fhenix FHE All orders resting in the system earn yield through Aave. Ontra’s goal is simple: professional, efficient, privacy-enabled execution — fully on-chain.

## Todo List

- [x] Implement addLiquidity and removeLiquidity with Aave integration
- [ ] Implement migratePosition function from pool to Aave and vice versa
- [ ] Implement Limit Orders
- [ ] Implement TWAP Orders
- [ ] Implement Trailing Stop Orders
- [ ] Integrate Fhenix FHE for Hidden Orders
- [ ] Write comprehensive tests
- [ ] Optimize gas usage
- [ ] Prepare documentation

## Specifications

- all yield generated from Aave deposits is returned to liquidity providers
