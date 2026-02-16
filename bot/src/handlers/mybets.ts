import { type Context, InlineKeyboard } from "grammy";
import { getUser, getUserBets } from "../db/database.js";
import {
  getMarketInfo,
  getUserBets as getOnChainBets,
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

export async function handleMyBets(ctx: Context) {
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

  // Group by market and get on-chain info
  const marketAddresses = [...new Set(bets.map((b) => b.market_address))];
  let text = "Your Bets:\n\n";
  const claimable: ClaimableMarket[] = [];

  for (const addr of marketAddresses.slice(0, 5)) {
    try {
      if (!(await isMarketFromFactory(addr as Address))) continue;
      const market = await getMarketInfo(addr as Address);
      const feed = feedNameFromId(market.priceId);
      const onChain = await getOnChainBets(addr as Address, user.wallet_address as Address);

      const upBet = Number(formatEther(onChain.upBet)).toFixed(4);
      const downBet = Number(formatEther(onChain.downBet)).toFixed(4);

      text += `${feed} | ${formatTimeWindow(market.startTime, market.expiryTime)}\n`;

      if (market.state === MarketState.Resolved) {
        const sideLabel = market.winningSide === Side.Up ? "⬆️ UP" : "⬇️ DOWN";
        text += `Resolved ${sideLabel} | Strike: $${formatPrice(market.strikePrice)}\n`;
      } else if (market.state === MarketState.Cancelled) {
        text += `CANCELLED | Strike: $${formatPrice(market.strikePrice)}\n`;
      } else {
        text += `OPEN | Strike: $${formatPrice(market.strikePrice)}\n`;
      }

      if (Number(upBet) > 0) text += `Your bet: ⬆️ UP ${upBet} BNB\n`;
      if (Number(downBet) > 0) text += `Your bet: ⬇️ DOWN ${downBet} BNB\n`;

      if (market.state === MarketState.Resolved) {
        const userSide = Number(upBet) > 0 ? Side.Up : Side.Down;
        if (userSide === market.winningSide) {
          // Check if already claimed: winning shares == 0 means already claimed
          const sharesLeft = userSide === Side.Up ? onChain.upShares : onChain.downShares;
          if (sharesLeft > 0n) {
            text += `🏆 You won! (unclaimed)\n`;
            claimable.push({ address: addr, feed, type: "claim" });
          } else {
            text += `🏆 You won! (claimed)\n`;
          }
        } else {
          text += `❌ You lost\n`;
        }
      } else if (market.state === MarketState.Cancelled) {
        // Check if already refunded: shares == 0 means already refunded
        const hasShares = onChain.upShares > 0n || onChain.downShares > 0n;
        if (hasShares) {
          text += `🔄 Refund available\n`;
          claimable.push({ address: addr, feed, type: "refund" });
        } else {
          text += `🔄 Refunded\n`;
        }
      }

      text += "\n";
    } catch {
      // skip errored markets
    }
  }

  const kb = new InlineKeyboard();

  if (claimable.length > 0) {
    const totalLabel = claimable.length === 1
      ? "Claim Winnings"
      : `Claim All Winnings (${claimable.length})`;
    kb.text(totalLabel, "claimall").row();
  }

  kb.text("Refresh", "mybets").row();
  kb.text("Back", "main");

  await ctx.editMessageText(text, { reply_markup: kb });
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

  for (const addr of marketAddresses.slice(0, 5)) {
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
