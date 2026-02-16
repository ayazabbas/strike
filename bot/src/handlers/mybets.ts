import { type Context, InlineKeyboard } from "grammy";
import { getUser, getUserBets } from "../db/database.js";
import {
  getMarketInfo,
  getUserBets as getOnChainBets,
  MarketState,
  Side,
  formatEther,
} from "../services/blockchain.js";
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
  const kb = new InlineKeyboard();

  for (const addr of marketAddresses.slice(0, 5)) {
    try {
      const market = await getMarketInfo(addr as Address);
      // Skip markets not from current factory
      const { isMarketFromFactory } = await import("../services/blockchain.js");
      if (!(await isMarketFromFactory(addr as Address))) continue;
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
          text += `🏆 You won!\n`;
          kb.text(`Claim - ${feed}`, `claim:${addr}`).row();
        } else {
          text += `❌ You lost\n`;
        }
      } else if (market.state === MarketState.Cancelled) {
        text += `🔄 Refund available\n`;
      }

      text += "\n";
    } catch {
      // skip errored markets
    }
  }

  kb.text("Refresh", "mybets").row();
  kb.text("Back", "main");

  await ctx.editMessageText(text, { reply_markup: kb });
}

export async function handleClaim(ctx: Context, marketAddress: string) {
  const telegramId = ctx.from!.id;
  const user = getUser(telegramId);
  if (!user) return;

  await ctx.editMessageText("Claiming your winnings...");

  try {
    const { sendTransaction } = await import("../services/privy.js");
    const { encodeClaimCall } = await import("../services/blockchain.js");

    const data = encodeClaimCall();
    const txHash = await sendTransaction(user.wallet_id, {
      to: marketAddress,
      value: "0x0",
      data,
      chainId: (await import("../config.js")).config.chainId,
    });

    const explorer = (await import("../config.js")).config.chainId === 56
      ? `https://bscscan.com/tx/${txHash}`
      : `https://testnet.bscscan.com/tx/${txHash}`;

    await ctx.editMessageText(
      `Winnings claimed!\n\n[View TX](${explorer})`,
      {
        parse_mode: "Markdown",
        link_preview: { is_disabled: true },
        reply_markup: new InlineKeyboard().text("Back to Bets", "mybets").row().text("Main Menu", "main"),
      }
    );
  } catch (err: any) {
    await ctx.editMessageText(`Claim failed: ${err.message ?? "Unknown error"}`, {
      reply_markup: new InlineKeyboard()
        .text("Retry", `claim:${marketAddress}`)
        .row()
        .text("Back", "mybets"),
    });
  }
}
