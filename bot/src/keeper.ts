/**
 * Strike Keeper Service
 *
 * Runs alongside the bot to:
 * 1. Create new BTC/USD 5-minute markets at aligned wall-clock intervals
 * 2. Resolve expired markets using Pyth price data
 */

import { type Address } from "viem";
import { config, PYTH } from "./config.js";
import {
  getMarketCount,
  getMarketAddresses,
  getMarketInfo,
  createMarketOnChain,
  resolveMarketOnChain,
  MarketState,
  publicClient,
} from "./services/blockchain.js";
import { getPriceUpdateData } from "./services/pyth.js";

const DURATION = BigInt(PYTH.defaultDurationSeconds); // 300s = 5 minutes
const INTERVAL_MS = PYTH.defaultDurationSeconds * 1000; // 5 minutes in ms
const RESOLVE_POLL_MS = 30_000; // 30 seconds

function log(msg: string) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

function logError(msg: string, err: unknown) {
  console.error(`[${new Date().toISOString()}] ${msg}`, err instanceof Error ? err.message : err);
}

// ─── Market Creation ──────────────────────────────────────────────────────

/**
 * Calculate ms until the next aligned 5-minute boundary.
 * Boundaries: :00, :05, :10, :15, :20, :25, :30, :35, :40, :45, :50, :55
 */
function msUntilNextBoundary(): number {
  const now = Date.now();
  const next = Math.ceil(now / INTERVAL_MS) * INTERVAL_MS;
  // If we're exactly on a boundary, schedule for the next one
  return next === now ? INTERVAL_MS : next - now;
}

/**
 * Check if there is currently an open (non-resolved, non-cancelled) market.
 */
async function hasOpenMarket(): Promise<boolean> {
  const count = await getMarketCount();
  if (count === 0) return false;

  // Check recent markets (most likely to be open)
  const limit = Math.min(count, 5);
  const offset = Math.max(0, count - limit);
  const addresses = await getMarketAddresses(offset, limit);

  const now = Math.floor(Date.now() / 1000);
  for (const addr of addresses) {
    const info = await getMarketInfo(addr);
    // A market is truly open only if stored state is Open AND trading hasn't ended
    if (info.state === MarketState.Open && now < info.tradingEnd) return true;
  }
  return false;
}

async function createMarket() {
  try {
    // Don't create if there's already an open market
    if (await hasOpenMarket()) {
      log("Skipping creation — open market already exists");
      return;
    }

    const priceId = PYTH.feeds["BTC/USD"] as `0x${string}`;
    const pythUpdateData = await getPriceUpdateData([priceId]);

    log("Creating new BTC/USD 5-minute market...");
    const hash = await createMarketOnChain(
      priceId,
      DURATION,
      pythUpdateData as `0x${string}`[],
    );

    const receipt = await publicClient.waitForTransactionReceipt({ hash: hash as `0x${string}` });
    if (receipt.status === "success") {
      log(`Market created — tx: ${hash}`);
    } else {
      log(`Market creation reverted — tx: ${hash}`);
    }
  } catch (err) {
    logError("Failed to create market:", err);
  }
}

function scheduleCreation() {
  const ms = msUntilNextBoundary();
  const nextTime = new Date(Date.now() + ms);
  log(`Next market creation at ${nextTime.toISOString()} (in ${Math.round(ms / 1000)}s)`);

  setTimeout(async () => {
    await createMarket();
    // Schedule the next one
    scheduleCreation();
  }, ms);
}

// ─── Market Resolution ────────────────────────────────────────────────────

async function resolveExpiredMarkets() {
  try {
    const count = await getMarketCount();
    if (count === 0) return;

    const addresses = await getMarketAddresses(0, count);
    const now = Math.floor(Date.now() / 1000);

    for (const addr of addresses) {
      try {
        const info = await getMarketInfo(addr);

        // Skip already resolved or cancelled
        if (info.state === MarketState.Resolved || info.state === MarketState.Cancelled) continue;
        // Only resolve if past expiry time
        if (now < info.expiryTime) continue;
        // Skip empty markets (no bets — nothing to resolve, will auto-cancel)
        if (info.upPool === 0n && info.downPool === 0n) {
          log(`Skipping ${addr} — empty pool, will auto-cancel`);
          continue;
        }

        log(`Resolving market ${addr}...`);

        const feedId = info.priceId.startsWith("0x") ? info.priceId : `0x${info.priceId}`;
        const pythUpdateData = await getPriceUpdateData([feedId]);

        const hash = await resolveMarketOnChain(
          addr,
          pythUpdateData as `0x${string}`[],
        );

        const receipt = await publicClient.waitForTransactionReceipt({ hash: hash as `0x${string}` });
        if (receipt.status === "success") {
          log(`Resolved market ${addr} — tx: ${hash}`);
        } else {
          log(`Resolution reverted for ${addr} — tx: ${hash}`);
        }
      } catch (err) {
        logError(`Error resolving market ${addr}:`, err);
      }
    }
  } catch (err) {
    logError("Error polling for expired markets:", err);
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────

async function main() {
  log("Strike Keeper starting...");
  log(`Factory: ${config.marketFactoryAddress}`);
  log(`Chain ID: ${config.chainId}`);
  log(`Duration: ${PYTH.defaultDurationSeconds}s`);

  // Create a market immediately if none are open
  await createMarket();

  // Schedule aligned creation
  scheduleCreation();

  // Poll for resolution every 30s
  setInterval(resolveExpiredMarkets, RESOLVE_POLL_MS);

  log("Keeper running. Press Ctrl+C to stop.");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
