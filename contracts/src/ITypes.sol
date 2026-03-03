// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title ITypes
/// @notice Shared types for the Strike CLOB protocol.

/// @notice Side of an order in a binary outcome market.
enum Side {
    Bid, // buying YES outcome (willing to pay tick/100)
    Ask  // selling YES outcome (willing to accept tick/100)
}

/// @notice Order type classification.
enum OrderType {
    GoodTilBatch, // lives for one batch auction, then expires
    GoodTilCancel // persists until filled or cancelled
}

/// @notice An order in the order book.
struct Order {
    uint256 id;          // unique order ID
    uint256 marketId;    // market this order belongs to
    address owner;       // order placer
    Side side;           // Bid or Ask
    OrderType orderType; // GTC or GTB
    uint256 tick;        // price tick 1-99 (price = tick/100)
    uint256 lots;        // remaining lots (each lot = 1e15 wei = 0.001 BNB)
    uint256 batchId;     // batch ID when order was placed
    uint256 timestamp;   // block.timestamp when placed
}

/// @notice Result of a batch auction clearing.
struct BatchResult {
    uint256 marketId;      // market that was cleared
    uint256 batchId;       // sequential batch number
    uint256 clearingTick;  // clearing price tick (0 = no cross)
    uint256 matchedLots;   // total lots matched at clearing tick
    uint256 totalBidLots;  // cumulative bid lots at clearing tick
    uint256 totalAskLots;  // cumulative ask lots at clearing tick
    uint256 timestamp;     // block.timestamp of clearing
}

/// @notice Market lifecycle states.
enum MarketState {
    Open,      // orders accepted, batches clear
    Closed,    // no new orders, final batch clears
    Resolving, // resolution submitted, finality pending
    Resolved,  // outcome set, redemption open
    Cancelled  // no resolution within 24h → refunds
}

/// @notice Market descriptor stored in OrderBook.
struct Market {
    uint256 id;             // market ID (matches OutcomeToken marketId)
    bool active;            // true if trading is open
    bool halted;            // true if temporarily halted
    uint256 currentBatchId; // current batch counter
    uint256 minLots;        // minimum order size in lots
    uint256 batchInterval;  // seconds between batch auctions
    uint256 expiryTime;     // timestamp when market expires
}
