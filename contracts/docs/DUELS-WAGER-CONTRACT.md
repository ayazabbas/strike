# Strike Duels Wager Contract

## Contract

`StrikeDuelsWagerVault` is the v1 escrow for server-authoritative Strike Duels wagers on BNB Chain.

It supports two isolated wager modes:

- **PvP native BNB:** both players deposit the same enabled BNB bracket. The winner receives the pool minus protocol fee. Draw/no-contest refunds both players.
- **AI `$STRIKE` pool:** player deposits the fixed AI stake in `$STRIKE`. If the player beats the server-authoritative hard AI, the player receives their stake back plus the fixed reward from the treasury-funded reward pool. If AI wins/forfeit, the player stake remains in the pool. Draw/no-contest refunds the player stake.

The contract does **not** decide gameplay results. Only an address with `SETTLER_ROLE` can finalize a wager with a server-authored result and match-summary hash.

## Roles

- `DEFAULT_ADMIN_ROLE`: bootstrap/admin role; can grant/revoke roles.
- `SETTLER_ROLE`: can call `finalizeWager` and `refundWager`.
- `PAUSER_ROLE`: can pause/unpause create/join/finalize/refund flows.
- `TREASURY_ROLE`: can update treasury, caps, fee bps, PvP brackets, and AI fixed amounts.

## Constructor

```solidity
constructor(
    address strikeToken,
    address admin,
    address treasury,
    address settler,
    uint256 aiStakeAmount,
    uint256 aiWinRewardAmount,
    uint16 pvpFeeBps,
    uint256 maxPvpStakeAmount,
    uint256 maxAiRewardExposure
)
```

Recommended v1 defaults:

- `strikeToken`: `0xDccC017B0F923Cf3F3ACDB535eb1019439717777` on BNB Chain.
- `aiStakeAmount`: `50_000e18`.
- `aiWinRewardAmount`: `50_000e18`.
- `pvpFeeBps`: `500` (5% of total PvP pool).
- Initial PvP brackets: `0.001 ether` and `0.01 ether`.

## Public user functions

```solidity
function createPvpWager(bytes32 wagerId, address opponent) external payable;
function joinPvpWager(bytes32 wagerId) external payable;
function createAiWager(bytes32 wagerId, bytes32 aiConfigHash) external;
```

### PvP

- `wagerId` must be unused.
- `msg.value` must exactly match an enabled PvP bracket.
- `msg.value <= maxPvpStakeAmount`.
- `opponent` can be a specific wallet or `address(0)` for open challenge.
- The creator cannot join their own PvP wager.
- If opponent is non-zero, only that opponent can join.

### AI

- `wagerId` must be unused.
- The player transfers exactly `aiStakeAmount` `$STRIKE` via `safeTransferFrom`.
- The vault must have enough unreserved pool liquidity for `aiWinRewardAmount` before accepting the wager.
- Open AI reward exposure must remain `<= maxAiRewardExposure`.

## Settlement functions

```solidity
enum Result {
    PlayerAWins,
    PlayerBWins,
    DrawNoContest
}

function finalizeWager(bytes32 wagerId, Result result, bytes32 matchSummaryHash) external;
function refundWager(bytes32 wagerId, bytes32 reason) external;
```

- Only `SETTLER_ROLE` can settle/refund.
- Settlement is idempotent by state: finalized/refunded wagers cannot be finalized/refunded again.
- `matchSummaryHash` should be the backend's canonical hash of the final server-authored `MatchSummary`.
- PvP:
  - `PlayerAWins`: creator receives pool minus fee.
  - `PlayerBWins`: joiner receives pool minus fee.
  - `DrawNoContest`: both players are refunded their stakes.
- AI:
  - `PlayerAWins`: player receives `aiStakeAmount + aiWinRewardAmount`.
  - `PlayerBWins`: player's stake remains in reward pool.
  - `DrawNoContest`: player receives `aiStakeAmount` refund.

## Admin functions

```solidity
function setPvpBracket(uint256 amount, bool enabled) external;
function setPvpFeeBps(uint16 feeBps) external;
function setTreasury(address treasury) external;
function setCaps(uint256 maxPvpStakeAmount, uint256 maxAiRewardExposure) external;
function setAiPrize(uint256 stakeAmount, uint256 winRewardAmount) external;
function pause() external;
function unpause() external;
```

## Events

```solidity
event PvpWagerCreated(bytes32 indexed wagerId, address indexed creator, address indexed opponent, uint256 stakeAmount);
event PvpWagerJoined(bytes32 indexed wagerId, address indexed joiner);
event AiWagerCreated(bytes32 indexed wagerId, address indexed player, bytes32 aiConfigHash, uint256 stakeAmount, uint256 winRewardAmount);
event WagerFinalized(bytes32 indexed wagerId, Result result, bytes32 matchSummaryHash, address indexed payoutRecipient, uint256 payoutAmount, uint256 feeAmount);
event WagerRefunded(bytes32 indexed wagerId, bytes32 reason);
event TreasuryUpdated(address indexed treasury);
event CapsUpdated(uint256 maxPvpStakeAmount, uint256 maxAiRewardExposure);
event PvpBracketUpdated(uint256 amount, bool enabled);
event AiPrizeUpdated(uint256 stakeAmount, uint256 winRewardAmount);
event PvpFeeUpdated(uint16 feeBps);
```

## Deployment / ABI prep

Dry-run command:

```bash
cd /home/ubuntu/dev/strike/contracts
DEPLOYER_PRIVATE_KEY=<dry-run-key> \
forge script script/DeployStrikeDuelsWagerVault.s.sol --rpc-url $RPC_URL
```

Broadcast command (approval-required):

```bash
cd /home/ubuntu/dev/strike/contracts
DEPLOYER_PRIVATE_KEY=<approved-deployer-key> \
DUELS_WAGER_ADMIN=<final-admin> \
DUELS_WAGER_TREASURY=<treasury> \
DUELS_WAGER_SETTLER=<settler> \
forge script script/DeployStrikeDuelsWagerVault.s.sol --rpc-url $RPC_URL --broadcast --verify
```

ABI export after build:

```bash
jq '.abi' out/StrikeDuelsWagerVault.sol/StrikeDuelsWagerVault.json \
  > /home/ubuntu/dev/strike-frontend/src/lib/abi/StrikeDuelsWagerVault.json
```

## Safety notes

- Wager mode remains disabled in product/backend config until legal/product approval.
- Deployment/broadcast requires explicit approval. Scripts are dry-run-first.
- The contract has no geoblock; any jurisdiction gate must live in product/backend configuration for v1.
