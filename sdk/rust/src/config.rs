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
                fee_model: "0xE7A18fAc36E4DF4F10C7d69a23AB45c01ea86781"
                    .parse()
                    .unwrap(),
                outcome_token: "0x88147c22E98B201493600e1Bbf9775Eea8B0E229"
                    .parse()
                    .unwrap(),
                vault: "0xaa8b16F64e2dC9958F0dBe97D5f274571a80497a"
                    .parse()
                    .unwrap(),
                order_book: "0x48C5ccBb3034E8bB76D96974c66a900B1CdAEcE7"
                    .parse()
                    .unwrap(),
                batch_auction: "0xEf0F96D0854C15265e40Dc5e7aD44a8D7405e51d"
                    .parse()
                    .unwrap(),
                market_factory: "0xED39F523B9cD6D915ab76B17029A20A4132Cb952"
                    .parse()
                    .unwrap(),
                pyth_resolver: "0xc72B3Da051FB25125396c83fa89856fbBE1e5f42"
                    .parse()
                    .unwrap(),
                redemption: "0xd3CcF8f19574F1Baf1117314Fd5131bC8B7059D1"
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
    pub fn bsc_mainnet() -> Self {
        Self {
            addresses: ContractAddresses {
                usdt: "0x55d398326f99059fF775485246999027B3197955"
                    .parse()
                    .unwrap(),
                fee_model: "0x115a7dda16926eddc048281e1fb80c15bc724a6a"
                    .parse()
                    .unwrap(),
                outcome_token: "0x161f2222684842cf1b5fb03e016365a91626690a"
                    .parse()
                    .unwrap(),
                vault: "0x223a1c6eb44cc6d7e74d11b3235941da2b02f164"
                    .parse()
                    .unwrap(),
                order_book: "0xa5ec8b3ac82853438bbb1788e0bd9d906b7c8d4e"
                    .parse()
                    .unwrap(),
                batch_auction: "0xddc0eb9fd6ce697294b8935d09acaebb494a491b"
                    .parse()
                    .unwrap(),
                market_factory: "0xb7f4b97b95b85d7c285ac0f6319785657dc0f1da"
                    .parse()
                    .unwrap(),
                pyth_resolver: "0x09c0574bfb7465ebc115258137e321e42ef813f8"
                    .parse()
                    .unwrap(),
                redemption: "0xb61c6880db469fb40e49757aa25b49baac26b451"
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
