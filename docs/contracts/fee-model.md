# FeeModel.sol

Pure fee-calculation contract for the Strike CLOB protocol. This contract performs no transfers -- all movement of funds is handled by callers (Vault, BatchAuction, etc.). FeeModel only computes amounts.

Inherits: `AccessControl` (OpenZeppelin).

## Fee Schedule

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `takerFeeBps` | `uint256` | Taker fee in basis points | 30 (0.30%) |
| `makerRebateBps` | `uint256` | Maker rebate in basis points | 0 (0.00%) |
| `resolverBounty` | `uint256` | Fixed BNB (wei) paid per market resolution | 0.005 ether |
| `prunerBounty` | `uint256` | Fixed BNB (wei) paid per pruned expired order | 0.0001 ether |
| `protocolFeeCollector` | `address` | Address that receives the protocol's net fee share | deployer |

**Invariant:** `makerRebateBps <= takerFeeBps` (rebate is funded from taker fees).

**Constant:** `MAX_BPS = 10_000` (100%).

## Calculation Functions

### calculateTakerFee

```solidity
function calculateTakerFee(uint256 amount) public view returns (uint256 fee)
```

Returns the taker fee for a given trade amount.

Formula: `fee = amount * takerFeeBps / 10_000`

### calculateMakerRebate

```solidity
function calculateMakerRebate(uint256 amount) public view returns (uint256 rebate)
```

Returns the maker rebate for a given trade amount.

Formula: `rebate = amount * makerRebateBps / 10_000`

### calculateNetProtocolFee

```solidity
function calculateNetProtocolFee(uint256 amount) public view returns (uint256 netFee)
```

Returns the net protocol fee (taker fee minus maker rebate). This is the amount that flows to `protocolFeeCollector`.

Formula: `netFee = calculateTakerFee(amount) - calculateMakerRebate(amount)`

## Admin Functions

All admin functions require `DEFAULT_ADMIN_ROLE`.

### setFeeParams

```solidity
function setFeeParams(uint256 _takerFeeBps, uint256 _makerRebateBps) external
```

Update the taker fee and maker rebate. Reverts if `_takerFeeBps > MAX_BPS` or `_makerRebateBps > _takerFeeBps`.

### setBounties

```solidity
function setBounties(uint256 _resolverBounty, uint256 _prunerBounty) external
```

Update the resolver and pruner bounty amounts (in wei). These values are stored here but the actual BNB transfers happen in other contracts (MarketFactory pays resolver bounty from the creation bond; BatchAuction pays pruner bounty).

### setProtocolFeeCollector

```solidity
function setProtocolFeeCollector(address _collector) external
```

Update the protocol fee collector address. Reverts if `_collector` is the zero address.

## Events

| Event | Parameters | Description |
|-------|-----------|-------------|
| `FeeParamsUpdated` | `uint256 takerFeeBps, uint256 makerRebateBps` | Emitted when fee schedule changes |
| `BountiesUpdated` | `uint256 resolverBounty, uint256 prunerBounty` | Emitted when bounties change |
| `ProtocolFeeCollectorUpdated` | `address indexed collector` | Emitted when fee collector changes |

## Constructor

```solidity
constructor(
    address admin,
    uint256 _takerFeeBps,
    uint256 _makerRebateBps,
    uint256 _resolverBounty,
    uint256 _prunerBounty,
    address _protocolFeeCollector
)
```

Grants `DEFAULT_ADMIN_ROLE` to `admin` and initializes all fee parameters.

## Example

With default parameters (takerFeeBps=30, makerRebateBps=0):

- Trade amount: 1 BNB (1e18 wei)
- Taker fee: 1e18 * 30 / 10000 = 3e15 wei = 0.003 BNB
- Maker rebate: 0
- Net protocol fee: 0.003 BNB (all goes to `protocolFeeCollector`)

If makerRebateBps were set to 10 (0.10%):

- Taker fee: 0.003 BNB
- Maker rebate: 0.001 BNB (paid to the maker from the taker fee)
- Net protocol fee: 0.002 BNB
