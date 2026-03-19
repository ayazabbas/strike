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
                usdt: "0x6Cec5A83a392B90aeDB6f8f7D8A71e231883cb2f"
                    .parse()
                    .unwrap(),
                fee_model: "0xC89a0BAE5c91428Fde19D07820917feBDCBf1597"
                    .parse()
                    .unwrap(),
                outcome_token: "0x7e3F8454abE51CA4d6AAc932e94DF80425Fd27D0"
                    .parse()
                    .unwrap(),
                vault: "0x4b5DF4104C4a2238ECa1fE8721c725Af80012bb6"
                    .parse()
                    .unwrap(),
                order_book: "0xab1f925c7D97B365FCb4151fCf42d7AC528Cc830"
                    .parse()
                    .unwrap(),
                batch_auction: "0x5b78902D8453821973667a7D1145b5a1208b862c"
                    .parse()
                    .unwrap(),
                market_factory: "0xD1a6C60DF935595eD5BeA7Dc26623f9A5DeB117C"
                    .parse()
                    .unwrap(),
                pyth_resolver: "0x6Ab6901ae588Cf7B0fb59B40c79A0bBfe944D920"
                    .parse()
                    .unwrap(),
                redemption: "0xF70e37E668DDF8D9b93920887392dAfDC900e9D3"
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
