# Events Reference

Complete list of events emitted by all Strike protocol contracts.

## Vault

```solidity
event Deposited(address indexed user, uint256 amount);
```
Emitted when USDT is deposited into the Vault for a user (via `safeTransferFrom`).

```solidity
event Withdrawn(address indexed user, uint256 amount);
```
Emitted when USDT is transferred to a user's wallet (via `safeTransfer`).

```solidity
event Locked(address indexed user, uint256 amount);
```
Emitted when collateral is locked (e.g., on order placement).

```solidity
event Unlocked(address indexed user, uint256 amount);
```
Emitted when collateral is unlocked (e.g., on cancel or partial unfill).

```solidity
event CollateralTransferred(address indexed from, address indexed to, uint256 amount);
```
Emitted when locked collateral moves between accounts (e.g., protocol fee payment during settlement).

```solidity
event AddedToMarketPool(uint256 indexed marketId, uint256 amount);
```
Emitted when collateral is moved into a market's redemption pool (during fill settlement).

```solidity
event RedeemedFromPool(uint256 indexed marketId, address indexed to, uint256 amount);
```
Emitted when USDT is paid out from a market's redemption pool to a user (during token redemption).

```solidity
event EmergencyModeActivated(uint256 timestamp);
```
Emitted when the admin activates emergency mode. After `EMERGENCY_TIMELOCK` (7 days) elapses, users can call `emergencyWithdraw`.

```solidity
event EmergencyWithdrawn(address indexed user, uint256 amount);
```
Emitted when a user withdraws all funds during emergency mode.

## OrderBook

```solidity
event MarketRegistered(uint256 indexed marketId, uint256 minLots);
```
Emitted when a new market is registered for trading (called by MarketFactory via OPERATOR_ROLE).

```solidity
event OrderPlaced(
    uint256 indexed orderId,
    uint256 indexed marketId,
    address indexed owner,
    Side side,
    uint256 tick,
    uint256 lots,
    uint256 batchId
);
```
Emitted when a user places an order. `side` is `Bid` (0), `Ask` (1), `SellYes` (2), or `SellNo` (3). `batchId` is the batch the order was placed into.

```solidity
event OrderCancelled(uint256 indexed orderId, address indexed owner);
```
Emitted when an order is cancelled by its owner. Collateral is unlocked.

```solidity
event GtcAutoCancelled(uint256 indexed orderId, address indexed owner);
```
Emitted when a GTC order is automatically cancelled during settlement because it has moved too far from the clearing price (beyond PROXIMITY_THRESHOLD). The order's collateral or tokens are returned to the owner.

```solidity
event MarketDeactivated(uint256 indexed marketId);
```
Emitted when a market is permanently deactivated (no new orders or clearing).

```solidity
event MarketHalted(uint256 indexed marketId);
```
Emitted when trading on a market is temporarily halted. Orders cannot be placed but can be cancelled.

```solidity
event MarketResumed(uint256 indexed marketId);
```
Emitted when a halted market resumes trading.

## BatchAuction

```solidity
event BatchCleared(
    uint256 indexed marketId,
    uint256 indexed batchId,
    uint256 clearingTick,
    uint256 matchedLots
);
```
Emitted when a batch is cleared. `clearingTick` is the price tick at which bids and asks cross (0 if no crossing). `matchedLots` is the total lots matched at the clearing tick.

```solidity
event OrderSettled(
    uint256 indexed orderId,
    address indexed owner,
    uint256 filledLots,
    uint256 collateralReleased
);
```
Emitted when an order is settled during atomic `clearBatch()`. `filledLots` may be 0 if the order did not participate in the clearing. `collateralReleased` is the unfilled/excess collateral returned.

## OutcomeToken

Standard ERC-1155 events from OpenZeppelin:

```solidity
event TransferSingle(
    address indexed operator,
    address indexed from,
    address indexed to,
    uint256 id,
    uint256 value
);
```
Emitted on single token mint, burn, or transfer.

```solidity
event TransferBatch(
    address indexed operator,
    address indexed from,
    address indexed to,
    uint256[] ids,
    uint256[] values
);
```
Emitted on batch token mint, burn, or transfer (e.g., `mintPair` and `burnPair` mint/burn two tokens at once).

```solidity
event ApprovalForAll(address indexed account, address indexed operator, bool approved);
```
Standard ERC-1155 approval event.

Additionally, OutcomeToken emits custom events:

```solidity
event PairMinted(address indexed to, uint256 indexed marketId, uint256 amount);
```
Emitted when a YES+NO token pair is minted.

```solidity
event PairBurned(address indexed from, uint256 indexed marketId, uint256 amount);
```
Emitted when a YES+NO token pair is burned.

```solidity
event Redeemed(address indexed from, uint256 indexed marketId, uint256 amount, bool winningOutcome);
```
Emitted when winning outcome tokens are burned during redemption.

## FeeModel

```solidity
event FeeBpsUpdated(uint256 feeBps);
```
Emitted when the uniform fee is updated.

```solidity
event ClearingBountyUpdated(uint256 clearingBountyBps);
```
Emitted when the clearing bounty is updated.

```solidity
event ProtocolFeeCollectorUpdated(address indexed collector);
```
Emitted when the protocol fee collector address is updated.

## MarketFactory

```solidity
event MarketCreated(
    uint256 indexed factoryMarketId,
    uint256 indexed orderBookMarketId,
    bytes32 priceId,
    int64 strikePrice,
    uint256 expiryTime,
    address indexed creator
);
```
Emitted when a new binary outcome market is created. Includes both the factory and orderbook market IDs, the Pyth price feed ID, the strike price threshold, and the expiry timestamp.

```solidity
event MarketClosed(uint256 indexed factoryMarketId);
```
Emitted when a market reaches expiry and is closed (no new orders).

```solidity
event MarketStateChanged(uint256 indexed factoryMarketId, MarketState newState);
```
Emitted on every state transition: Open -> Closed -> Resolving -> Resolved, or Open/Closed -> Cancelled. `MarketState` is an enum: `Open` (0), `Closed` (1), `Resolving` (2), `Resolved` (3), `Cancelled` (4).

```solidity
event FactoryPaused(bool paused);
```
Emitted when the factory is paused or unpaused. When paused, no new markets can be created.

```solidity
event DefaultParamsUpdated(uint256 batchInterval, uint128 minLots);
```
Emitted when default market creation parameters are updated.

```solidity
event CreationBondUpdated(uint256 newBond);
```
Emitted when the market creation bond amount is updated.

```solidity
event FeeCollectorUpdated(address indexed collector);
```
Emitted when the factory's fee collector address is updated.

```solidity
event ResolverBountyPaid(uint256 indexed factoryMarketId, address indexed resolver, uint256 amount);
```
Emitted when the creation bond is paid out to the resolver who successfully resolved a market.

## PythResolver

```solidity
event ResolutionSubmitted(
    uint256 indexed factoryMarketId,
    int64 price,
    uint256 publishTime,
    address indexed resolver
);
```
Emitted when the first resolution is submitted for a market. The resolver provides Pyth price data; the market transitions to Resolving state.

```solidity
event ResolutionChallenged(
    uint256 indexed factoryMarketId,
    int64 newPrice,
    uint256 newPublishTime,
    address indexed challenger
);
```
Emitted when a pending resolution is challenged with an earlier publishTime during the finality window (`FINALITY_PERIOD` = 90 seconds). The challenger's data replaces the pending resolution.

```solidity
event ResolutionFinalized(
    uint256 indexed factoryMarketId,
    int64 price,
    bool outcomeYes,
    address indexed finalizer
);
```
Emitted when a resolution is finalized after the finality gate passes. `outcomeYes` indicates whether price >= strikePrice. The resolver bounty is paid.

## Redemption

```solidity
event Redeemed(
    uint256 indexed factoryMarketId,
    address indexed user,
    uint256 amount,
    bool outcomeYes
);
```
Emitted when a user redeems winning outcome tokens for USDT. `amount` is the number of tokens burned; payout is `amount * LOT_SIZE` (1e16 = $0.01).
