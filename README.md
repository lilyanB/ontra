# UHI Hookathon 2025

## Project Name:

Ontra

## Description:

Ontra — The On-Chain Trading Engine Ontra is a Uniswap v4 Hook that brings institutional-grade execution directly on-chain. The core idea is a Rehypothecation Hook: any LP liquidity or order liquidity that is not currently active is automatically deposited into Aave to earn yield. When liquidity becomes needed again, the Hook withdraws it in a single batch to minimize gas. Ontra provides an on-chain execution layer supporting: Limit orders TWAP orders (30s / 1m / 5m packs) Trailing stop orders (5% / 10% / 15% pools) Hidden orders secured with Fhenix FHE All orders resting in the system earn yield through Aave. Ontra’s goal is simple: professional, efficient, privacy-enabled execution — fully on-chain.

## Todo List

- [x] Implement addLiquidity with Aave integration
- [x] Implement removeLiquidity with Aave integration
- [x] Implement rebalanceToAave function
- [x] Implement Trailing Stop Orders
- [ ] Implement Limit Orders
- [ ] Implement TWAP Orders
- [ ] Integrate Fhenix FHE for Hidden Orders
- [ ] Write comprehensive tests
- [ ] Optimize gas usage
- [ ] Prepare documentation
- [ ] Deploy to testnet
- [ ] Implement front-end interface
- [ ] Implement subgraph for event indexing

Outside of scope for the Hookathon:

- [ ] implement router for safety checks
- [ ] Deploy to mainnet

## Specifications

- yield generated from Aave deposits during rehypothecation is returned to liquidity providers
- trailing stop lost orders are deposited into Aave until triggered and the generated yield is returned to the order placer
- executed trailing stop lost are also deposited into Aave until withdrawn by the order placer. Generated yield is returned to the owner
