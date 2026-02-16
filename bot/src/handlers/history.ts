import { type Context, InlineKeyboard } from "grammy";
import { getUser, getUserBetCount, getUserBetMarkets, getUserBetsForMarket } from "../db/database.js";
import {
  getMarketInfo,
  getWinningSide,
  getResolutionPrice,
  MarketState,
  Side,
} from "../services/blockchain.js";
import { formatPrice } from "../services/pyth.js";
import { PYTH } from "../config.js";
import { config } from "../config.js";
import type { Address } from "viem";

const PAGE_SIZE = 5;

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

export async function handleHistory(ctx: Context, page = 0) {
  const telegramId = ctx.from!.id;
  const user = getUser(telegramId);

  if (!user) {
    const text = "You need to /start first.";
    if (ctx.callbackQuery) {
      await ctx.editMessageText(text, {
        reply_markup: new InlineKeyboard().text("Back", "main"),
      });
    } else {
      await ctx.reply(text, {
        reply_markup: new InlineKeyboard().text("Back", "main"),
      });
    }
    return;
  }

  const totalMarkets = getUserBetCount(telegramId);

  if (totalMarkets === 0) {
    const text = "No betting history yet.\n\nGo to Markets to place your first bet!";
    if (ctx.callbackQuery) {
      await ctx.editMessageText(text, {
        reply_markup: new InlineKeyboard()
          .text("View Markets", "markets")
          .row()
          .text("Back", "main"),
      });
    } else {
      await ctx.reply(text, {
        reply_markup: new InlineKeyboard()
          .text("View Markets", "markets")
          .row()
          .text("Back", "main"),
      });
    }
    return;
  }

  const totalPages = Math.ceil(totalMarkets / PAGE_SIZE);
  const offset = page * PAGE_SIZE;
  const marketAddresses = getUserBetMarkets(telegramId, offset, PAGE_SIZE);

  const explorer = config.chainId === 56 ? "https://bscscan.com" : "https://testnet.bscscan.com";

  let text = `Betting History (${page + 1}/${totalPages})\n\n`;

  for (const addr of marketAddresses) {
    try {
      const market = await getMarketInfo(addr as Address);
      const feed = feedNameFromId(market.priceId);
      const window = formatTimeWindow(market.startTime, market.expiryTime);
      const bets = getUserBetsForMarket(telegramId, addr);

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

          for (const bet of bets) {
            const won = bet.side === (winningSide === Side.Up ? "up" : "down");
            const result = won ? "Won" : "Lost";
            text += `\n  ${bet.side.toUpperCase()} ${bet.amount} BNB — ${result}`;
            if (bet.tx_hash) {
              text += ` [TX](${explorer}/tx/${bet.tx_hash})`;
            }
          }
          text += `\n  Result: ${sideLabel} wins\n`;
        } catch {
          for (const bet of bets) {
            text += `\n  ${bet.side.toUpperCase()} ${bet.amount} BNB`;
            if (bet.tx_hash) text += ` [TX](${explorer}/tx/${bet.tx_hash})`;
          }
          text += "\n";
        }
      } else if (market.state === MarketState.Cancelled) {
        for (const bet of bets) {
          text += `\n  ${bet.side.toUpperCase()} ${bet.amount} BNB — Refunded`;
          if (bet.tx_hash) text += ` [TX](${explorer}/tx/${bet.tx_hash})`;
        }
        text += "\n";
      } else {
        for (const bet of bets) {
          text += `\n  ${bet.side.toUpperCase()} ${bet.amount} BNB — Pending`;
          if (bet.tx_hash) text += ` [TX](${explorer}/tx/${bet.tx_hash})`;
        }
        text += "\n";
      }

      text += "\n";
    } catch {
      text += `Market ${addr.slice(0, 6)}...${addr.slice(-4)} — Error loading\n\n`;
    }
  }

  const kb = new InlineKeyboard();
  if (page > 0) {
    kb.text("« Prev", `history:${page - 1}`);
  }
  if (page < totalPages - 1) {
    kb.text("Next »", `history:${page + 1}`);
  }
  kb.row();
  kb.text("Back", "main");

  if (ctx.callbackQuery) {
    await ctx.editMessageText(text, { parse_mode: "Markdown", reply_markup: kb });
  } else {
    await ctx.reply(text, { parse_mode: "Markdown", reply_markup: kb });
  }
}
