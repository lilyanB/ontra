# UHI Hookathon 2025

## Project Name:

Ontra

## Description:

Ontra — The On-Chain Trading Engine Ontra is a Uniswap v4 Hook that brings institutional-grade execution directly on-chain. The core idea is a Rehypothecation Hook: any LP liquidity or order liquidity that is not currently active is automatically deposited into Aave to earn yield. When liquidity becomes needed again, the Hook withdraws it in a single batch to minimize gas. Ontra provides an on-chain execution layer supporting: Limit orders TWAP orders (30s / 1m / 5m packs) Trailing stop orders (5% / 10% / 15% pools) Hidden orders secured with Fhenix FHE All orders resting in the system earn yield through Aave. Ontra’s goal is simple: professional, efficient, privacy-enabled execution — fully on-chain.

## Deployment Link:

I need to deploy Aave mock because the configuration on sepolia is not working.
MockAavePool 0xfcAEE36D3df9d2eBf114cfcD0A628a0bbeBA2fBC

Sepolia Testnet:
OntraV2Hook: 0xb842CEB38B4eD22F5189ABcb774168187DEA5040
SwapRouterWithLocker: 0xe15D86D762A71c44E4559D98f9C44B1e45c7709E
Owner: 0x607A577659Cad2A2799120DfdEEde39De2D38706
key: struct PoolKey PoolKey({ currency0: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, currency1: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9, fee: 0, tickSpacing: 60, hooks: 0xb842CEB38B4eD22F5189ABcb774168187DEA5040 })

## Todo List

- [x] Implement addLiquidity with Aave integration
- [x] Implement removeLiquidity with Aave integration
- [x] Implement rebalanceToAave function
- [x] Implement Trailing Stop Orders
- [ ] Implement Limit Orders
- [ ] Implement TWAP Orders
- [ ] Integrate Fhenix FHE for Hidden Orders
- [x] Write comprehensive tests
- [ ] Prepare documentation
- [x] Deploy to testnet
- [x] Implement front-end interface

Outside of scope for the Hookathon:

- [ ] implement router for safety checks
- [ ] Deploy to mainnet
- [ ] Implement subgraph for event indexing
- [ ] Optimize gas usage

## Specifications

- yield generated from Aave deposits during rehypothecation is returned to liquidity providers
- trailing stop lost orders are deposited into Aave until triggered and the generated yield is returned to the order placer
- executed trailing stop lost are also deposited into Aave until withdrawn by the order placer. Generated yield is returned to the owner
