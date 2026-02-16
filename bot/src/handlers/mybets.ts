import { type Context, InlineKeyboard } from "grammy";
import { getUser, getUserBets, getUserBetCount, getUserBetMarkets, getUserBetsForMarket } from "../db/database.js";
import {
  getMarketInfo,
  getUserBets as getOnChainBets,
  getWinningSide,
  getResolutionPrice,
  MarketState,
  Side,
  formatEther,
  isMarketFromFactory,
  encodeClaimCall,
  encodeRefundCall,
} from "../services/blockchain.js";
import { sendTransaction } from "../services/privy.js";
import { config } from "../config.js";
import { PYTH, type FeedName } from "../config.js";
import { formatPrice } from "../services/pyth.js";
import type { Address } from "viem";

const PAST_PAGE_SIZE = 5;

function feedNameFromId(priceId: string): string {
  for (const [name, id] of Object.entries(PYTH.feeds)) {
    if (priceId.toLowerCase() === id.toLowerCase()) return name;
  }
  return "Unknown";
}

function formatTime(ts: number): string {
  return new Date(ts * 1000).toISOString().slice(11, 16);
}

function formatTimeWindow(startTime: number, expiryTime: number): string {
  return `${formatTime(startTime)}-${formatTime(expiryTime)} UTC`;
}

interface ClaimableMarket {
  address: string;
  feed: string;
  type: "claim" | "refund";
}

export async function handleMyBets(ctx: Context, page = 0) {
  const telegramId = ctx.from!.id;
  const user = getUser(telegramId);

  if (!user) {
    await ctx.editMessageText("You need to /start first.", {
      reply_markup: new InlineKeyboard().text("Back", "main"),
    });
    return;
  }

  const bets = getUserBets(telegramId);

  if (bets.length === 0) {
    await ctx.editMessageText("You haven't placed any bets yet.\n\nGo to Markets to start!", {
      reply_markup: new InlineKeyboard()
        .text("View Markets", "markets")
        .row()
        .text("Back", "main"),
    });
    return;
  }

  // ── Active bets (open/unresolved markets) ──────────────────────────
  const allMarketAddresses = [...new Set(bets.map((b) => b.market_address))];
  let text = "";
  const claimable: ClaimableMarket[] = [];
  const activeAddrs: string[] = [];
  const pastAddrs: string[] = [];

  // Classify markets as active vs past
  for (const addr of allMarketAddresses) {
    try {
      if (!(await isMarketFromFactory(addr as Address))) continue;
      const market = await getMarketInfo(addr as Address);
      if (market.state === MarketState.Open || market.state === MarketState.Closed) {
        activeAddrs.push(addr);
      } else {
        pastAddrs.push(addr);
      }
    } catch {
      // skip errored markets
    }
  }

  // Show active bets section
  if (activeAddrs.length > 0) {
    text += "ACTIVE BETS\n\n";
    for (const addr of activeAddrs) {
      try {
        const market = await getMarketInfo(addr as Address);
        const feed = feedNameFromId(market.priceId);
        const onChain = await getOnChainBets(addr as Address, user.wallet_address as Address);

        const upBet = Number(formatEther(onChain.upBet)).toFixed(4);
        const downBet = Number(formatEther(onChain.downBet)).toFixed(4);

        text += `${feed} | ${formatTimeWindow(market.startTime, market.expiryTime)}\n`;
        text += `OPEN | Strike: $${formatPrice(market.strikePrice)}\n`;
        if (Number(upBet) > 0) text += `Your bet: ⬆️ UP ${upBet} BNB\n`;
        if (Number(downBet) > 0) text += `Your bet: ⬇️ DOWN ${downBet} BNB\n`;
        text += "\n";
      } catch {
        // skip
      }
    }
  }

  // ── Past results (resolved/cancelled) paginated ────────────────────
  // Use DB-level pagination for past markets
  const totalPastMarkets = getUserBetCount(telegramId);
  // Subtract active markets from total for pagination
  const activeBetMarketCount = activeAddrs.length;
  const totalPast = Math.max(0, totalPastMarkets - activeBetMarketCount);

  if (totalPast > 0) {
    const totalPages = Math.ceil(totalPast / PAST_PAGE_SIZE);
    const currentPage = Math.min(page, Math.max(0, totalPages - 1));

    // We need to get past markets only. Fetch enough from DB to skip active ones.
    // Strategy: fetch all market addresses from DB, filter out active, then paginate.
    const allDbMarkets = getUserBetMarkets(telegramId, 0, totalPastMarkets);
    const activeSet = new Set(activeAddrs.map(a => a.toLowerCase()));
    const pastDbMarkets = allDbMarkets.filter(a => !activeSet.has(a.toLowerCase()));

    const offset = currentPage * PAST_PAGE_SIZE;
    const pageMarkets = pastDbMarkets.slice(offset, offset + PAST_PAGE_SIZE);
    const actualTotalPages = Math.ceil(pastDbMarkets.length / PAST_PAGE_SIZE);

    const explorer = config.chainId === 56 ? "https://bscscan.com" : "https://testnet.bscscan.com";

    text += `PAST RESULTS (${currentPage + 1}/${actualTotalPages})\n\n`;

    for (const addr of pageMarkets) {
      try {
        if (!(await isMarketFromFactory(addr as Address))) continue;
        const market = await getMarketInfo(addr as Address);
        const feed = feedNameFromId(market.priceId);
        const window = formatTimeWindow(market.startTime, market.expiryTime);
        const dbBets = getUserBetsForMarket(telegramId, addr);
        const onChain = await getOnChainBets(addr as Address, user.wallet_address as Address);

        text += `${feed} | ${window}\n`;
        text += `Strike: $${formatPrice(market.strikePrice)}`;

        if (market.state === MarketState.Resolved) {
          try {
            const resPrice = await getResolutionPrice(addr as Address);
            text += ` → $${formatPrice(resPrice)}`;
          } catch {}

          try {
            const winningSide = await getWinningSide(addr as Address);
            const sideLabel = winningSide === Side.Up ? "UP" : "DOWN";

            for (const bet of dbBets) {
              const won = bet.side === (winningSide === Side.Up ? "up" : "down");
              const result = won ? "Won" : "Lost";
              text += `\n  ${bet.side.toUpperCase()} ${bet.amount} BNB — ${result}`;
              if (bet.tx_hash) {
                text += ` [TX](${explorer}/tx/${bet.tx_hash})`;
              }
            }
            text += `\n  Result: ${sideLabel} wins`;

            // Check claimable
            const upBet = Number(formatEther(onChain.upBet)).toFixed(4);
            const downBet = Number(formatEther(onChain.downBet)).toFixed(4);
            const userSide = Number(upBet) > 0 ? Side.Up : Side.Down;
            if (userSide === winningSide) {
              const sharesLeft = userSide === Side.Up ? onChain.upShares : onChain.downShares;
              if (sharesLeft > 0n) {
                text += ` (unclaimed)`;
                claimable.push({ address: addr, feed, type: "claim" });
              }
            }
            text += "\n";
          } catch {
            for (const bet of dbBets) {
              text += `\n  ${bet.side.toUpperCase()} ${bet.amount} BNB`;
              if (bet.tx_hash) text += ` [TX](${explorer}/tx/${bet.tx_hash})`;
            }
            text += "\n";
          }
        } else if (market.state === MarketState.Cancelled) {
          const hasShares = onChain.upShares > 0n || onChain.downShares > 0n;
          for (const bet of dbBets) {
            text += `\n  ${bet.side.toUpperCase()} ${bet.amount} BNB — Refunded`;
            if (bet.tx_hash) text += ` [TX](${explorer}/tx/${bet.tx_hash})`;
          }
          if (hasShares) {
            text += `\n  🔄 Refund available`;
            claimable.push({ address: addr, feed, type: "refund" });
          }
          text += "\n";
        }

        text += "\n";
      } catch {
        text += `Market ${addr.slice(0, 6)}...${addr.slice(-4)} — Error loading\n\n`;
      }
    }

    // Pagination buttons
    const kb = new InlineKeyboard();

    if (claimable.length > 0) {
      const totalLabel = claimable.length === 1
        ? "Claim Winnings"
        : `Claim All Winnings (${claimable.length})`;
      kb.text(totalLabel, "claimall").row();
    }

    if (currentPage > 0) {
      kb.text("« Prev", `mybets:page:${currentPage - 1}`);
    }
    if (currentPage < actualTotalPages - 1) {
      kb.text("Next »", `mybets:page:${currentPage + 1}`);
    }
    kb.row();
    kb.text("Refresh", "mybets").row();
    kb.text("Back", "main");

    await ctx.editMessageText(text, {
      parse_mode: "Markdown",
      link_preview: { is_disabled: true },
      reply_markup: kb,
    });
  } else {
    // Only active bets, no past results
    const kb = new InlineKeyboard();

    // Also check claimable from active bets that might be resolved
    // (already handled above, but active means open/closed so no claimable)

    kb.text("Refresh", "mybets").row();
    kb.text("Back", "main");

    await ctx.editMessageText(text || "No bets to display.", {
      reply_markup: kb,
    });
  }
}

export async function handleClaimAll(ctx: Context) {
  const telegramId = ctx.from!.id;
  const user = getUser(telegramId);
  if (!user) return;

  await ctx.editMessageText("Scanning for unclaimed winnings...");

  const bets = getUserBets(telegramId);
  const marketAddresses = [...new Set(bets.map((b) => b.market_address))];

  // Find all claimable markets
  const claimable: { address: string; feed: string; type: "claim" | "refund" }[] = [];

  for (const addr of marketAddresses) {
    try {
      if (!(await isMarketFromFactory(addr as Address))) continue;
      const market = await getMarketInfo(addr as Address);
      const feed = feedNameFromId(market.priceId);
      const onChain = await getOnChainBets(addr as Address, user.wallet_address as Address);

      const upBet = Number(formatEther(onChain.upBet)).toFixed(4);
      const downBet = Number(formatEther(onChain.downBet)).toFixed(4);

      if (market.state === MarketState.Resolved) {
        const userSide = Number(upBet) > 0 ? Side.Up : Side.Down;
        if (userSide === market.winningSide) {
          const sharesLeft = userSide === Side.Up ? onChain.upShares : onChain.downShares;
          if (sharesLeft > 0n) {
            claimable.push({ address: addr, feed, type: "claim" });
          }
        }
      } else if (market.state === MarketState.Cancelled) {
        const hasShares = onChain.upShares > 0n || onChain.downShares > 0n;
        if (hasShares) {
          claimable.push({ address: addr, feed, type: "refund" });
        }
      }
    } catch {
      // skip errored markets
    }
  }

  if (claimable.length === 0) {
    await ctx.editMessageText("No unclaimed winnings found.", {
      reply_markup: new InlineKeyboard().text("Back to Bets", "mybets").row().text("Main Menu", "main"),
    });
    return;
  }

  const explorer = config.chainId === 56
    ? "https://bscscan.com/tx/"
    : "https://testnet.bscscan.com/tx/";

  const results: string[] = [];
  let failed = 0;

  for (let i = 0; i < claimable.length; i++) {
    const item = claimable[i];
    await ctx.editMessageText(`Claiming ${i + 1}/${claimable.length}... (${item.feed})`);

    try {
      const data = item.type === "claim" ? encodeClaimCall() : encodeRefundCall();
      const txHash = await sendTransaction(user.wallet_id, {
        to: item.address,
        value: "0x0",
        data,
        chainId: config.chainId,
      });
      const label = item.type === "claim" ? "Claimed" : "Refunded";
      results.push(`${label} ${item.feed}: [TX](${explorer}${txHash})`);
    } catch (err: any) {
      failed++;
      results.push(`Failed ${item.feed}: ${err.message ?? "Unknown error"}`);
    }
  }

  const summary = results.join("\n");
  const statusLine = failed > 0
    ? `\n\n${claimable.length - failed}/${claimable.length} succeeded, ${failed} failed.`
    : `\n\nAll ${claimable.length} claims successful!`;

  await ctx.editMessageText(
    `Claim Results:\n\n${summary}${statusLine}`,
    {
      parse_mode: "Markdown",
      link_preview: { is_disabled: true },
      reply_markup: new InlineKeyboard().text("Back to Bets", "mybets").row().text("Main Menu", "main"),
    }
  );
}
