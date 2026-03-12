# Deployments

## BSC Testnet (Chain ID: 97) — V2 deployed 2026-03-12

| Contract | Address |
|----------|---------|
| **MockUSDT** | [`0x4Be5501EDDF6263984614840A13228D0ecbf8430`](https://testnet.bscscan.com/address/0x4Be5501EDDF6263984614840A13228D0ecbf8430) |
| **FeeModel** | [`0x2EBB7d9468AC5ab8254Aeeac1c30A0878e1fB169`](https://testnet.bscscan.com/address/0x2EBB7d9468AC5ab8254Aeeac1c30A0878e1fB169) |
| **OutcomeToken** | [`0x24bA7F171e82d4994cd2BD0f8899955076fEBff5`](https://testnet.bscscan.com/address/0x24bA7F171e82d4994cd2BD0f8899955076fEBff5) |
| **Vault** | [`0xf7c51CC50F1589082850978BA8E779318299FeC9`](https://testnet.bscscan.com/address/0xf7c51CC50F1589082850978BA8E779318299FeC9) |
| **OrderBook** | [`0xAFeeF2F0DBE473e4C2BC4b5981793F69804CfaD0`](https://testnet.bscscan.com/address/0xAFeeF2F0DBE473e4C2BC4b5981793F69804CfaD0) |
| **BatchAuction** | [`0xDB15B4BDC2A2595BbC03af25f225668c098e0ACC`](https://testnet.bscscan.com/address/0xDB15B4BDC2A2595BbC03af25f225668c098e0ACC) |
| **MarketFactory** | [`0x5b562aeD5db8e4799565F1092d3D2b3C851909b7`](https://testnet.bscscan.com/address/0x5b562aeD5db8e4799565F1092d3D2b3C851909b7) |
| **PythResolver** | [`0x23a2553eD776bEE953cC4378F1BCcCe83eDF9BB3`](https://testnet.bscscan.com/address/0x23a2553eD776bEE953cC4378F1BCcCe83eDF9BB3) |
| **Redemption** | [`0x850DfD796FBb88f576D7136C5f205Cf2AEc01e74`](https://testnet.bscscan.com/address/0x850DfD796FBb88f576D7136C5f205Cf2AEc01e74) |
| **Pyth Core** | [`0xd7308b14BF4008e7C7196eC35610B1427C5702EA`](https://testnet.bscscan.com/address/0xd7308b14BF4008e7C7196eC35610B1427C5702EA) |

### V2 Changes
- USDT collateral (not native BNB) — 1 YES + 1 NO = 1 USDT
- Atomic `clearBatch(marketId)` — no orderIds param
- Uniform 20bps fee, clearing bounty disabled
- Settlement at clearing price (not order tick)
- Per-batch order tracking, batch overflow protection (MAX 400)
- GTC/GTB separate settlement logic

## Price Feeds

| Pair | Pyth Price ID |
|------|--------------|
| BTC/USD | `0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43` |

## Previous Deployments

### V1 — BSC Testnet (2026-03-11)

| Contract | Address |
|----------|---------|
| FeeModel | `0xb5d1C27A44E976293D4e2623C3154172B1FaC923` |
| OutcomeToken | `0x58833f1f9DD1F40Eb7Dbf9DC0737b6b7B6066479` |
| Vault | `0x8deE3b4a762AF013928A42a52E93784C2538aADE` |
| OrderBook | `0xFEB0EBe9dE1Fd39272D252B91bd0EaD9b6f80220` |
| BatchAuction | `0xe8f7E8d64f504a0D2c8CF9b79e26a9dDF5DE6672` |
| MarketFactory | `0x153929450d3A92064cB067bc7854023b560096c4` |
| PythResolver | `0x1da35127af1DEF31eceFE5DAb3F504D9f6E62396` |
| Redemption | `0xd0BFa67B6cb3D28FA0cBdA920daA5501c7DB59a4` |

### PoC (v0 — Parimutuel)

| Contract | Address |
|----------|---------|
| MarketFactory (PoC) | `0xC04761a62156894028f8107d1A27E5C714d55B01` |
| Market Implementation (PoC) | `0x55FebD192fa22f3eA05259776aBeC0686147DfEC` |
