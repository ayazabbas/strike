# Deployments

## BSC Testnet (Chain ID: 97) — V4 deployed 2026-03-13

| Contract | Address |
|----------|---------|
| **MockUSDT** | [`0x35c2731E24d88198cDc0128dD42fC2Ee969fB3fa`](https://testnet.bscscan.com/address/0x35c2731E24d88198cDc0128dD42fC2Ee969fB3fa) |
| **FeeModel** | [`0x958AA4E008765C1146b46701c5286eB5c57bd7E3`](https://testnet.bscscan.com/address/0x958AA4E008765C1146b46701c5286eB5c57bd7E3) |
| **OutcomeToken** | [`0x2C7E4d5b838D61141252b1c4c09618478C561f49`](https://testnet.bscscan.com/address/0x2C7E4d5b838D61141252b1c4c09618478C561f49) |
| **Vault** | [`0xe19bB1799ed8C369980cb346014c68f83df1C294`](https://testnet.bscscan.com/address/0xe19bB1799ed8C369980cb346014c68f83df1C294) |
| **OrderBook** | [`0x31EFda3d089CB5150b6aee57adDA3a7Aa97151A3`](https://testnet.bscscan.com/address/0x31EFda3d089CB5150b6aee57adDA3a7Aa97151A3) |
| **BatchAuction** | [`0xF22db29C2Fe828c5F31C6764d042b39419CBD3fd`](https://testnet.bscscan.com/address/0xF22db29C2Fe828c5F31C6764d042b39419CBD3fd) |
| **MarketFactory** | [`0x4460F2Bc7d4405fc3DBd9344F40D5A0f4a4dF4f0`](https://testnet.bscscan.com/address/0x4460F2Bc7d4405fc3DBd9344F40D5A0f4a4dF4f0) |
| **PythResolver** | [`0x9ffc6b4A6D86034fDD9a3758bC25361BFC994972`](https://testnet.bscscan.com/address/0x9ffc6b4A6D86034fDD9a3758bC25361BFC994972) |
| **Redemption** | [`0xdBd7dFFEbf8F7a2a3772832D03Ed0a87a57Fb776`](https://testnet.bscscan.com/address/0xdBd7dFFEbf8F7a2a3772832D03Ed0a87a57Fb776) |
| **Pyth Core** | [`0xd7308b14BF4008e7C7196eC35610B1427C5702EA`](https://testnet.bscscan.com/address/0xd7308b14BF4008e7C7196eC35610B1427C5702EA) |

### V4 Changes
- Full clean redeploy to fix immutable OrderBook reference in MarketFactory
- LOT_SIZE = 1e16 ($0.01/lot, 100 lots = $1 payout)
- New MockUSDT address (redeployed with contract stack)

## Price Feeds

| Pair | Pyth Price ID |
|------|--------------|
| BTC/USD | `0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43` |

## Previous Deployments

### V3 — BSC Testnet (2026-03-13)

| Contract | Address |
|----------|---------|
| MarketFactory | `0xBeC18FFcd4c0C2801AC037deED977148D6e99B24` |
| OrderBook | `0xa4dE27DB7d95492311C1097349356354fF8A6859` |
| BatchAuction | `0x0E471438fc81A244adb66b6ed2040DA580340a06` |
| Vault | `0x3aE0D470D493AB834681Ce299D98A3cD3A118b90` |
| OutcomeToken | `0x73B84fb86f8D32d20E4f667bC45b399aF9ca9cEf` |
| PythResolver | `0x885A81709729584C69CA9ceDD671Bddb69F626fE` |
| Redemption | `0x27A53D8694C4565040D5D929F3efd786c5548B54` |
| FeeModel | `0xE0d8158299E814ce185dDB844aa4618965214FFC` |
| MockUSDT | `0x4Be5501EDDF6263984614840A13228D0ecbf8430` |

### V2 — BSC Testnet (2026-03-12)

| Contract | Address |
|----------|---------|
| MockUSDT | `0x4Be5501EDDF6263984614840A13228D0ecbf8430` |
| FeeModel | `0x2EBB7d9468AC5ab8254Aeeac1c30A0878e1fB169` |
| OutcomeToken | `0x24bA7F171e82d4994cd2BD0f8899955076fEBff5` |
| Vault | `0xf7c51CC50F1589082850978BA8E779318299FeC9` |
| OrderBook | `0xAFeeF2F0DBE473e4C2BC4b5981793F69804CfaD0` |
| BatchAuction | `0xDB15B4BDC2A2595BbC03af25f225668c098e0ACC` |
| MarketFactory | `0x5b562aeD5db8e4799565F1092d3D2b3C851909b7` |
| PythResolver | `0x23a2553eD776bEE953cC4378F1BCcCe83eDF9BB3` |
| Redemption | `0x850DfD796FBb88f576D7136C5f205Cf2AEc01e74` |

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
