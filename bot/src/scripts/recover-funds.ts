/**
 * One-off recovery script: claim/refund keeper funds from all old markets.
 *
 * For each Resolved market  → calls claim() (keeper's winning-side bet)
 * For each Cancelled market → calls refund() (keeper's seed bets)
 *
 * Usage: npx tsx bot/src/scripts/recover-funds.ts
 */

import { type Address, formatEther } from "viem";
import {
  getMarketCount,
  getMarketAddresses,
  getMarketInfo,
  getUserBets,
  claimOnMarket,
  refundOnMarket,
  getKeeperAddress,
  publicClient,
  MarketState,
} from "../services/blockchain.js";

function log(msg: string) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

async function main() {
  const keeperAddress = getKeeperAddress();
  log(`Keeper address: ${keeperAddress}`);

  const count = await getMarketCount();
  log(`Total markets: ${count}`);

  if (count === 0) {
    log("No markets found. Nothing to recover.");
    return;
  }

  const addresses = await getMarketAddresses(0, count);

  let totalClaimed = 0n;
  let totalRefunded = 0n;
  let claimCount = 0;
  let refundCount = 0;
  let skipCount = 0;

  for (const addr of addresses) {
    try {
      const info = await getMarketInfo(addr);

      if (info.state === MarketState.Resolved) {
        // Check if keeper has winning-side bets to claim
        const userBets = await getUserBets(addr, keeperAddress);
        const winSideBet = info.winningSide === 0 ? userBets.upBet : userBets.downBet;

        if (winSideBet === 0n) {
          log(`  [SKIP] ${addr} — Resolved, no winning bet to claim`);
          skipCount++;
          continue;
        }

        try {
          const balBefore = await publicClient.getBalance({ address: keeperAddress });
          const hash = await claimOnMarket(addr);
          const receipt = await publicClient.waitForTransactionReceipt({ hash: hash as `0x${string}` });

          if (receipt.status === "success") {
            const balAfter = await publicClient.getBalance({ address: keeperAddress });
            // Net gain = balance change + gas spent
            const gasUsed = receipt.gasUsed * receipt.effectiveGasPrice;
            const recovered = balAfter - balBefore + gasUsed;
            totalClaimed += recovered;
            claimCount++;
            log(`  [CLAIM] ${addr} — recovered ${formatEther(recovered)} BNB — tx: ${hash}`);
          } else {
            log(`  [FAIL] ${addr} — claim tx reverted — tx: ${hash}`);
          }
        } catch (err) {
          log(`  [ERROR] ${addr} — claim failed: ${err instanceof Error ? err.message : err}`);
        }
      } else if (info.state === MarketState.Cancelled) {
        // Check if keeper has any bets to refund
        const userBets = await getUserBets(addr, keeperAddress);
        const totalBet = userBets.upBet + userBets.downBet;

        if (totalBet === 0n) {
          log(`  [SKIP] ${addr} — Cancelled, no bets to refund`);
          skipCount++;
          continue;
        }

        try {
          const balBefore = await publicClient.getBalance({ address: keeperAddress });
          const hash = await refundOnMarket(addr);
          const receipt = await publicClient.waitForTransactionReceipt({ hash: hash as `0x${string}` });

          if (receipt.status === "success") {
            const balAfter = await publicClient.getBalance({ address: keeperAddress });
            const gasUsed = receipt.gasUsed * receipt.effectiveGasPrice;
            const recovered = balAfter - balBefore + gasUsed;
            totalRefunded += recovered;
            refundCount++;
            log(`  [REFUND] ${addr} — recovered ${formatEther(recovered)} BNB — tx: ${hash}`);
          } else {
            log(`  [FAIL] ${addr} — refund tx reverted — tx: ${hash}`);
          }
        } catch (err) {
          log(`  [ERROR] ${addr} — refund failed: ${err instanceof Error ? err.message : err}`);
        }
      } else {
        // Open or Closed — skip
        skipCount++;
      }
    } catch (err) {
      log(`  [ERROR] ${addr} — could not read market info: ${err instanceof Error ? err.message : err}`);
    }
  }

  log("");
  log("═══ Recovery Summary ═══");
  log(`Markets scanned:  ${addresses.length}`);
  log(`Claims (resolved): ${claimCount} — total ${formatEther(totalClaimed)} BNB`);
  log(`Refunds (cancelled): ${refundCount} — total ${formatEther(totalRefunded)} BNB`);
  log(`Skipped:           ${skipCount}`);
  log(`Total recovered:   ${formatEther(totalClaimed + totalRefunded)} BNB`);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
