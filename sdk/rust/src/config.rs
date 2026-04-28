//! Chain configuration and contract addresses.

use alloy::primitives::Address;

/// Transaction send / confirmation tuning.
#[derive(Debug, Clone)]
pub struct TxConfig {
    /// HTTP receipt polling interval for remote RPC transports.
    pub receipt_poll_interval_ms: u64,
    /// Legacy gas price multiplier in basis points (10000 = 1.00x).
    pub gas_price_multiplier_bps: u64,
    /// Optional hard cap for legacy gas price bids.
    pub max_gas_price_wei: Option<u128>,
}

impl Default for TxConfig {
    fn default() -> Self {
        Self {
            receipt_poll_interval_ms: 500,
            gas_price_multiplier_bps: 11_000,
            max_gas_price_wei: None,
        }
    }
}

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
    /// Transaction send / confirmation tuning.
    pub tx: TxConfig,
}

impl StrikeConfig {
    /// BSC Testnet deployment (chain ID 97).
    pub fn bsc_testnet() -> Self {
        Self {
            addresses: ContractAddresses {
                usdt: "0xb242dc031998b06772C63596Bfce091c80D4c3fA"
                    .parse()
                    .unwrap(),
                fee_model: "0x78F6102Ee4C13c0836c4E0CCfc501B74F83C01CD"
                    .parse()
                    .unwrap(),
                outcome_token: "0x612AAD13FB8Cc41D32933966FE88dac3277f6d2a"
                    .parse()
                    .unwrap(),
                vault: "0xb7dE5e17633bd3E9F4DfeFdF2149F5725f9092Fe"
                    .parse()
                    .unwrap(),
                order_book: "0xF890b891F83f29Ce72BdD2720C1114ba16D5316c"
                    .parse()
                    .unwrap(),
                batch_auction: "0x743e60a7AE108614dDCb5bBb4468c4187002969B"
                    .parse()
                    .unwrap(),
                market_factory: "0xB4a9D6Dc1cAE195e276638ef9Cc20e797Cb3f839"
                    .parse()
                    .unwrap(),
                pyth_resolver: "0x2a7fba2365CCbd648e5c82E4846AD7D53fa47108"
                    .parse()
                    .unwrap(),
                redemption: "0x28de9b7536ecfeE55De0f34E0875037E08E14F88"
                    .parse()
                    .unwrap(),
            },
            chain_id: 97,
            rpc_url: "https://data-seed-prebsc-1-s1.binance.org:8545".to_string(),
            wss_url: "wss://bsc-testnet.core.chainstack.com/e602061228197d446d43e62320004d74"
                .to_string(),
            indexer_url: "https://testnet.strike.pm/api".to_string(),
            tx: TxConfig::default(),
        }
    }

    /// BSC Mainnet deployment (chain ID 56).
    pub fn bsc_mainnet() -> Self {
        Self {
            addresses: ContractAddresses {
                usdt: "0x55d398326f99059fF775485246999027B3197955"
                    .parse()
                    .unwrap(),
                fee_model: "0x10d479354013c20eC777569618186D79eE818D8a"
                    .parse()
                    .unwrap(),
                outcome_token: "0xdcA3d1Be0a181494F2bf46a5a885b2c2009574f3"
                    .parse()
                    .unwrap(),
                vault: "0x2a6EA3F574264E6fA9c6F3c691dA01BE6DaC066f"
                    .parse()
                    .unwrap(),
                order_book: "0x1E7C9b93D2C939a433D87b281918508Eec7c9171"
                    .parse()
                    .unwrap(),
                batch_auction: "0xCdd122520E9efbdb5bd1Cc246aE497c37c70bdBE"
                    .parse()
                    .unwrap(),
                market_factory: "0xcbBC04B2a3EfE858c7C3d159c56f194AF2a7eBac"
                    .parse()
                    .unwrap(),
                pyth_resolver: "0x101383ef333d5Cb7Cb154EAbcA68961e3ac5B1a4"
                    .parse()
                    .unwrap(),
                redemption: "0x9a46D6c017eDdA49832cC9eE315246d0B55E5804"
                    .parse()
                    .unwrap(),
            },
            chain_id: 56,
            rpc_url: "https://bsc-dataseed1.binance.org".to_string(),
            wss_url: "wss://bsc-ws-node.nariox.org:443".to_string(),
            indexer_url: "https://app.strike.pm/api".to_string(),
            tx: TxConfig::default(),
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
            tx: TxConfig::default(),
        }
    }
}
