//! Chain configuration and contract addresses.

use alloy::primitives::Address;

/// Contract addresses for a Strike deployment.
#[derive(Debug, Clone)]
pub struct ContractAddresses {
    pub usdt: Address,
    pub fee_model: Address,
    pub outcome_token: Address,
    pub vault: Address,
    pub order_book: Address,
    pub batch_auction: Address,
    pub market_factory: Address,
    pub pyth_resolver: Address,
    pub redemption: Address,
}

/// Configuration for connecting to a Strike deployment.
#[derive(Debug, Clone)]
pub struct StrikeConfig {
    /// Contract addresses.
    pub addresses: ContractAddresses,
    /// Chain ID.
    pub chain_id: u64,
    /// Default HTTP RPC URL.
    pub rpc_url: String,
    /// Default WebSocket URL for event subscriptions.
    pub wss_url: String,
    /// Indexer base URL.
    pub indexer_url: String,
}

impl StrikeConfig {
    /// BSC Testnet deployment (chain ID 97).
    pub fn bsc_testnet() -> Self {
        Self {
            addresses: ContractAddresses {
                usdt: "0xb242dc031998b06772C63596Bfce091c80D4c3fA"
                    .parse()
                    .unwrap(),
                fee_model: "0xa044FF6E4385c3d671E47aa9E31cb91a50a3F276"
                    .parse()
                    .unwrap(),
                outcome_token: "0x427CFce18cC5278f2546F88ab02c6a0749228A45"
                    .parse()
                    .unwrap(),
                vault: "0xc9aA051e0BB2E0Fbb8Bfe4e4BB9ffa5Bf690023b"
                    .parse()
                    .unwrap(),
                order_book: "0xB59e3d709Bd8Df10418D47E7d2CF045B02D06E32"
                    .parse()
                    .unwrap(),
                batch_auction: "0x414D9da55d61835fD7Bb127978a2c49B8F09BdD5"
                    .parse()
                    .unwrap(),
                market_factory: "0x6415619262033090EA0C2De913a3a6d9FC1d9DE9"
                    .parse()
                    .unwrap(),
                pyth_resolver: "0xDcb807de5Ba5F3af04286a9dC1F6f3eb33066b92"
                    .parse()
                    .unwrap(),
                redemption: "0x4b55f917Ab45028d4C75f3dA400B50D81209593b"
                    .parse()
                    .unwrap(),
            },
            chain_id: 97,
            rpc_url: "https://data-seed-prebsc-1-s1.binance.org:8545".to_string(),
            wss_url: "wss://bsc-testnet.core.chainstack.com/e602061228197d446d43e62320004d74"
                .to_string(),
            indexer_url: "https://strike-indexer.fly.dev".to_string(),
        }
    }

    /// BSC Mainnet deployment (chain ID 56).
    ///
    /// Note: Mainnet contracts are not yet deployed. Update addresses when available.
    pub fn bsc_mainnet() -> Self {
        Self {
            addresses: ContractAddresses {
                usdt: "0x55d398326f99059fF775485246999027B3197955"
                    .parse()
                    .unwrap(),
                // Placeholder addresses — update when mainnet contracts are deployed
                fee_model: Address::ZERO,
                outcome_token: Address::ZERO,
                vault: Address::ZERO,
                order_book: Address::ZERO,
                batch_auction: Address::ZERO,
                market_factory: Address::ZERO,
                pyth_resolver: Address::ZERO,
                redemption: Address::ZERO,
            },
            chain_id: 56,
            rpc_url: "https://bsc-dataseed1.binance.org".to_string(),
            wss_url: "wss://bsc-ws-node.nariox.org:443".to_string(),
            indexer_url: String::new(),
        }
    }

    /// Custom deployment with user-provided addresses and chain ID.
    pub fn custom(addresses: ContractAddresses, chain_id: u64) -> Self {
        Self {
            addresses,
            chain_id,
            rpc_url: String::new(),
            wss_url: String::new(),
            indexer_url: String::new(),
        }
    }
}
