# Deployments

## BSC Testnet (Chain ID: 97) — V7 deployed 2026-03-15

| Contract | Address |
|----------|---------|
| **MockUSDT** | [`0xb242dc031998b06772C63596Bfce091c80D4c3fA`](https://testnet.bscscan.com/address/0xb242dc031998b06772C63596Bfce091c80D4c3fA) |
| **FeeModel** | [`0x5c49f364FfE404B041e1f44cCd3801Ea9d328034`](https://testnet.bscscan.com/address/0x5c49f364FfE404B041e1f44cCd3801Ea9d328034) |
| **OutcomeToken** | [`0xaCbc1Ad38cF2767Ac57c5a23105e73A7DE319AEB`](https://testnet.bscscan.com/address/0xaCbc1Ad38cF2767Ac57c5a23105e73A7DE319AEB) |
| **Vault** | [`0x54DB2d048547b9b9426699833f3B57ab03b5F8dc`](https://testnet.bscscan.com/address/0x54DB2d048547b9b9426699833f3B57ab03b5F8dc) |
| **OrderBook** | [`0x0B8557c02CCD2E59571fDc56D16ac2b5fC3E14D2`](https://testnet.bscscan.com/address/0x0B8557c02CCD2E59571fDc56D16ac2b5fC3E14D2) |
| **BatchAuction** | [`0xd378411231665898E2cdB4c0e1cD723f6C696DA3`](https://testnet.bscscan.com/address/0xd378411231665898E2cdB4c0e1cD723f6C696DA3) |
| **MarketFactory** | [`0x9d6FC94A14a393Dd7b3F2FfBa0110D06010aD4a2`](https://testnet.bscscan.com/address/0x9d6FC94A14a393Dd7b3F2FfBa0110D06010aD4a2) |
| **PythResolver** | [`0x10CCAbaE996AE13403DbD9a6b1C38456D7B08bE9`](https://testnet.bscscan.com/address/0x10CCAbaE996AE13403DbD9a6b1C38456D7B08bE9) |
| **Redemption** | [`0x0eB52824d38E5682B876A79166C8B1045A0BBb2B`](https://testnet.bscscan.com/address/0x0eB52824d38E5682B876A79166C8B1045A0BBb2B) |
| **Pyth Core** | [`0xd7308b14BF4008e7C7196eC35610B1427C5702EA`](https://testnet.bscscan.com/address/0xd7308b14BF4008e7C7196eC35610B1427C5702EA) |

### V7 Changes
- **SellYes / SellNo order sides**: users can sell existing outcome tokens back into the orderbook
- `Side` enum expanded to 4 values: `Bid`, `Ask`, `SellYes`, `SellNo`
- OrderBook is now `ERC1155Holder` — custodies tokens during sell order lifetime
- `OutcomeToken.burnEscrow()` added with `ESCROW_ROLE` (granted to BatchAuction)
- `placeOrder` signature: `(marketId, side, orderType, tick, lots)` — note new param order
- Deploy script auto-grants `ESCROW_ROLE` to BatchAuction

## Price Feeds

| Pair | Pyth Price ID |
|------|--------------|
| BTC/USD | `0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43` |

## Previous Deployments

### V6 — BSC Testnet (2026-03-15, batchCancel)

| Contract | Address |
|----------|---------|
| MockUSDT | `0xb7FFc63715fA15047DCf3b16b0036AD05c3D04F7` |
| FeeModel | `0xe94398B40b9e564E23c4c7dB6115F031B135B678` |
| OutcomeToken | `0x4FA0E346dC388C5A0dFFb7E7a801463CBDfe300B` |
| Vault | `0xc97B3f5F9dac0e6cC05a7e44a791aF1Ec199392e` |
| OrderBook | `0x3D20998b135A4800cD7717D0504366F62C3DD641` |
| BatchAuction | `0x558822b9Fd5be9905200d799A85A721f78a7a0f0` |
| MarketFactory | `0x997A4Ad2249BED986463046DC070b1BB6e0E60A4` |
| PythResolver | `0x96df2608f7c8DCAA4013700502C99531C4299F69` |
| Redemption | `0xA51a642D840154536EAd35437BeaDB9ED088511d` |

### V4 — BSC Testnet (2026-03-13)

| Contract | Address |
|----------|---------|
| MockUSDT | `0x35c2731E24d88198cDc0128dD42fC2Ee969fB3fa` |
| FeeModel | `0x958AA4E008765C1146b46701c5286eB5c57bd7E3` |
| OutcomeToken | `0x2C7E4d5b838D61141252b1c4c09618478C561f49` |
| Vault | `0xe19bB1799ed8C369980cb346014c68f83df1C294` |
| OrderBook | `0x31EFda3d089CB5150b6aee57adDA3a7Aa97151A3` |
| BatchAuction | `0xF22db29C2Fe828c5F31C6764d042b39419CBD3fd` |
| MarketFactory | `0x4460F2Bc7d4405fc3DBd9344F40D5A0f4a4dF4f0` |
| PythResolver | `0x9ffc6b4A6D86034fDD9a3758bC25361BFC994972` |
| Redemption | `0xdBd7dFFEbf8F7a2a3772832D03Ed0a87a57Fb776` |

### V3 — BSC Testnet (2026-03-13)

| Contract | Address |
|----------|---------|
| MarketFactory | `0xBeC18FFcd4c0C2801AC037deED977148D6e99B24` |
| OrderBook | `0xa4dE27DB7d95492311C1097349356354fF8A6859` |
| BatchAuction | `0x0E471438fc81A244adb66b6ed2040DA580340a06` |

### V2 — BSC Testnet (2026-03-12)

| Contract | Address |
|----------|---------|
| MockUSDT | `0x4Be5501EDDF6263984614840A13228D0ecbf8430` |
| OrderBook | `0xAFeeF2F0DBE473e4C2BC4b5981793F69804CfaD0` |
| BatchAuction | `0xDB15B4BDC2A2595BbC03af25f225668c098e0ACC` |
| MarketFactory | `0x5b562aeD5db8e4799565F1092d3D2b3C851909b7` |
