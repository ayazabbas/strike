# Deployments

## BSC Testnet (Chain ID: 97)

| Contract | Address |
|----------|---------|
| **MarketFactory** | [`0xC04761a62156894028f8107d1A27E5C714d55B01`](https://testnet.bscscan.com/address/0xC04761a62156894028f8107d1A27E5C714d55B01) |
| **Market Implementation** | [`0x55FebD192fa22f3eA05259776aBeC0686147DfEC`](https://testnet.bscscan.com/address/0x55FebD192fa22f3eA05259776aBeC0686147DfEC) |
| **Pyth Oracle** | [`0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb`](https://testnet.bscscan.com/address/0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb) |
| **Fee Collector** | `0xC2AFf8375481b7fb36d964f96ff01Dd3Bb032262` |

## Price Feeds

| Pair | Pyth Price ID |
|------|--------------|
| BTC/USD | `0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43` |

## Verification

All contracts are deployed from the same deployer address and can be verified on [BSC Testnet Explorer](https://testnet.bscscan.com/).

### Deployment Transaction

The deployment script (`contracts/script/Deploy.s.sol`) deploys:
1. Market implementation contract (used as the clone template)
2. MarketFactory (pointing to the implementation and Pyth oracle)

```bash
# Reproduce the deployment
cd contracts
forge script script/Deploy.s.sol \
  --rpc-url https://bsc-testnet-rpc.publicnode.com \
  --broadcast
```
