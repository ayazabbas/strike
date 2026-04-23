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
                fee_model: "0x5b8fCB458485e5d63c243A1FA4CA45e4e984B1eE"
                    .parse()
                    .unwrap(),
                outcome_token: "0x92dFA493eE92e492Df7EB2A43F87FBcb517313a9"
                    .parse()
                    .unwrap(),
                vault: "0xEd56fF9A42F60235625Fa7DDA294AB70698DF25D"
                    .parse()
                    .unwrap(),
                order_book: "0x9CF4544389d235C64F1B42061f3126fF11a28734"
                    .parse()
                    .unwrap(),
                batch_auction: "0x8e4885Cb6e0D228d9E4179C8Bd32A94f28A602df"
                    .parse()
                    .unwrap(),
                market_factory: "0xa1EA91E7D404C14439C84b4A95cF51127cE0338B"
                    .parse()
                    .unwrap(),
                pyth_resolver: "0x9ddadD15f27f4c7523268CFFeb1A1b04FEEA32b9"
                    .parse()
                    .unwrap(),
                redemption: "0x98723a449537AF17Fd7ddE29bd7De8f5a7A1B9B2"
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
