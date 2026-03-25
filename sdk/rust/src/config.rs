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
                fee_model: "0x46C198Fa5e0E1CCEc3652bAB9A975B9F68B7F39E"
                    .parse()
                    .unwrap(),
                outcome_token: "0x1c6622bE0D8cefD48009A337CD393cAe4530fc9a"
                    .parse()
                    .unwrap(),
                vault: "0x10909d11446e48551DA0366f59b9Ac9Cb9079314"
                    .parse()
                    .unwrap(),
                order_book: "0x343d3f42562A8E5C794DFf8637664D2d03246FB9"
                    .parse()
                    .unwrap(),
                batch_auction: "0xF6233287fb878706B191b868a5e38E1DfdfAdDf7"
                    .parse()
                    .unwrap(),
                market_factory: "0xd2783195A8d4Ee2f99616c3b9048B43187951E67"
                    .parse()
                    .unwrap(),
                pyth_resolver: "0xF83aE0cfd2D1546Bb4b15ecEB010C1B045d7Ddc9"
                    .parse()
                    .unwrap(),
                redemption: "0x03961AcDb718D84079De1B0236a77A7a1A3df177"
                    .parse()
                    .unwrap(),
            },
            chain_id: 97,
            rpc_url: "https://data-seed-prebsc-1-s1.binance.org:8545".to_string(),
            wss_url: "wss://bsc-testnet.core.chainstack.com/e602061228197d446d43e62320004d74"
                .to_string(),
            indexer_url: "https://testnet.strike.pm/api".to_string(),
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
                fee_model: "0xBB628007734963352b1cF9094847B902b0fca9aB"
                    .parse()
                    .unwrap(),
                outcome_token: "0xBd65B054a08fe0e8d26325e69B6EB6aD6dfF1516"
                    .parse()
                    .unwrap(),
                vault: "0x2556E5DE92281EdA3300F044dfB9158416407eed"
                    .parse()
                    .unwrap(),
                order_book: "0x074Ca415B501Bcca0020e9c312cf1F80796Ae3b1"
                    .parse()
                    .unwrap(),
                batch_auction: "0xa8e9a6B62B93A4360969972Dc7300C6Be7B5f9D8"
                    .parse()
                    .unwrap(),
                market_factory: "0x9c045dc57c1132e5D13b234F8e166cAaD8CE2c3D"
                    .parse()
                    .unwrap(),
                pyth_resolver: "0x1B3335A22D410713A4Cd32eF8ffBEe672aD4e65d"
                    .parse()
                    .unwrap(),
                redemption: "0x03961AcDb718D84079De1B0236a77A7a1A3df177"
                    .parse()
                    .unwrap(),
            },
            chain_id: 56,
            rpc_url: "https://bsc-dataseed1.binance.org".to_string(),
            wss_url: "wss://bsc-ws-node.nariox.org:443".to_string(),
            indexer_url: "https://app.strike.pm/api".to_string(),
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
