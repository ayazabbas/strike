# Keeper Service

The keeper is a background service that automates market lifecycle management.

## What It Does

### Market Creation

- Creates a new BTC/USD 5-minute market at every clean 5-minute interval
- Boundaries: `:00`, `:05`, `:10`, `:15`, `:20`, `:25`, `:30`, `:35`, `:40`, `:45`, `:50`, `:55`
- Only creates a market if no open market currently exists (prevents overlapping markets)
- Uses the deployer wallet to sign creation transactions

### Market Resolution

- Polls for expired markets every 30 seconds
- Resolves any market that has passed its expiry time
- Fetches fresh Pyth price data for resolution
- Skips empty markets (no bets placed)
- Handles errors gracefully — a failed resolution doesn't crash the service

## Running the Keeper

### Development

```bash
cd bot
npm run keeper
```

### Production (systemd)

The keeper runs as a systemd user service:

```bash
systemctl --user start strike-keeper
systemctl --user status strike-keeper

# View logs
journalctl --user -u strike-keeper -f
```

## Configuration

The keeper uses the same `.env.local` configuration as the bot:

| Variable | Used For |
|----------|----------|
| `MARKET_FACTORY_ADDRESS` | Which factory to create markets on |
| `DEPLOYER_PRIVATE_KEY` | Signing creation and resolution transactions |
| `BSC_RPC_URL` | Blockchain RPC endpoint |
| `CHAIN_ID` | Network selection |

## Log Output

```
[2026-02-15T21:30:16Z] Strike Keeper starting...
[2026-02-15T21:30:16Z] Factory: 0xDf8C...1358
[2026-02-15T21:30:16Z] Chain ID: 97
[2026-02-15T21:30:16Z] Duration: 300s
[2026-02-15T21:30:17Z] Creating new BTC/USD 5-minute market...
[2026-02-15T21:30:21Z] Market created — tx: 0xca5f...bf0f
[2026-02-15T21:30:21Z] Next market creation at 2026-02-15T21:35:00.000Z (in 279s)
```

## Failure Handling

- If market creation fails, it logs the error and retries at the next 5-minute boundary
- If resolution fails for a specific market, it skips that market and continues checking others
- The systemd service auto-restarts on crash (`RestartSec=5`)
- Markets that aren't resolved within 24 hours are auto-cancelled by the smart contract
