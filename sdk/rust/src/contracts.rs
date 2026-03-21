//! Alloy contract bindings generated from ABI JSON files.
//!
//! Each binding is tagged with `#[sol(rpc)]` so alloy generates typed call builders.

use alloy::sol;

sol!(
    #[sol(rpc)]
    OrderBook,
    "abi/OrderBook.json"
);

sol!(
    #[sol(rpc)]
    BatchAuction,
    "abi/BatchAuction.json"
);

sol!(
    #[sol(rpc)]
    MarketFactory,
    "abi/MarketFactory.json"
);

sol!(
    #[sol(rpc)]
    Vault,
    "abi/Vault.json"
);

sol!(
    #[sol(rpc)]
    MockUSDT,
    "abi/MockUSDT.json"
);

sol!(
    #[sol(rpc)]
    OutcomeToken,
    "abi/OutcomeToken.json"
);

sol!(
    #[sol(rpc)]
    RedemptionContract,
    "abi/Redemption.json"
);

sol!(
    #[sol(rpc)]
    FeeModel,
    "abi/FeeModel.json"
);

sol!(
    #[sol(rpc)]
    PythResolver,
    "abi/PythResolver.json"
);
