import type { Bot, Context } from "grammy";
import type { Address } from "viem";
import {
  getMarketInfo,
  getWinningSide,
  MarketState,
  Side,
} from "./blockchain.js";
import { formatPrice } from "./pyth.js";
import { getBettorsByMarket } from "../db/database.js";
import { PYTH } from "../config.js";

function feedNameFromId(priceId: string): string {
  for (const [name, id] of Object.entries(PYTH.feeds)) {
    if (priceId.toLowerCase() === id.toLowerCase()) return name;
  }
  return "Unknown";
}

/**
 * Check if a market is resolved and notify all bettors of the result.
 * Returns the number of users notified, or 0 if the market isn't resolved.
 */
export async function notifyMarketResult(bot: Bot<Context>, marketAddress: string): Promise<number> {
  const market = await getMarketInfo(marketAddress as Address);

  if (market.state !== MarketState.Resolved) {
    return 0;
  }

  const winningSide = await getWinningSide(marketAddress as Address);
  const sideLabel = winningSide === Side.Up ? "UP" : "DOWN";
  const feed = feedNameFromId(market.priceId);

  const bettors = getBettorsByMarket(marketAddress);
  if (bettors.length === 0) return 0;

  let notified = 0;

  for (const bet of bettors) {
    const userBetSide = bet.side === "up" ? Side.Up : Side.Down;
    const won = userBetSide === winningSide;

    const text = [
      `Market Resolved: ${feed}`,
      ``,
      `Strike: $${formatPrice(market.strikePrice)}`,
      `Result: ${sideLabel} wins`,
      `Your bet: ${bet.side.toUpperCase()} ${bet.amount} BNB`,
      won ? `You won! Use My Bets to claim.` : `Better luck next time.`,
    ].join("\n");

    try {
      await bot.api.sendMessage(bet.telegram_id, text);
      notified++;
    } catch (err) {
      console.error(`Failed to notify user ${bet.telegram_id}:`, err);
    }
  }

  return notified;
}
