import { type Context, InlineKeyboard } from "grammy";
import {
  getMarketCount,
  getMarketAddresses,
  getMarketInfo,
  MarketState,
  STATE_LABELS,
  type MarketInfo,
  formatEther,
  estimatePayout,
  parseEther,
  Side,
} from "../services/blockchain.js";
import { getLatestPrices, formatPrice } from "../services/pyth.js";
import { PYTH, type FeedName } from "../config.js";

function feedNameFromId(priceId: string): FeedName | "Unknown" {
  for (const [name, id] of Object.entries(PYTH.feeds)) {
    if (priceId.toLowerCase() === id.toLowerCase()) return name as FeedName;
  }
  return "Unknown";
}

function timeRemaining(expiryTime: number): string {
  const now = Math.floor(Date.now() / 1000);
  const diff = expiryTime - now;
  if (diff <= 0) return "Expired";
  const h = Math.floor(diff / 3600);
  const m = Math.floor((diff % 3600) / 60);
  const s = diff % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

export async function handleMarkets(ctx: Context) {
  try {
    const count = await getMarketCount();
    if (count === 0) {
      await ctx.editMessageText("No active markets yet.\n\nCheck back soon!", {
        reply_markup: new InlineKeyboard().text("Refresh", "markets").row().text("Back", "main"),
      });
      return;
    }

    const addresses = await getMarketAddresses(0, 10);
    const markets: MarketInfo[] = [];
    for (const addr of addresses) {
      try {
        const info = await getMarketInfo(addr);
        markets.push(info);
      } catch {
        // skip broken markets
      }
    }

    // Get live prices
    let prices: Record<string, number> = {};
    try {
      const priceData = await getLatestPrices();
      for (const p of priceData) prices[p.feedName] = p.price;
    } catch {
      // prices unavailable
    }

    // Filter to open/closed markets
    const active = markets.filter((m) => m.state === MarketState.Open || m.state === MarketState.Closed);

    if (active.length === 0) {
      await ctx.editMessageText("No active markets right now.\n\nCheck back soon!", {
        reply_markup: new InlineKeyboard().text("Refresh", "markets").row().text("Back", "main"),
      });
      return;
    }

    let text = "Active Markets:\n\n";
    const kb = new InlineKeyboard();

    for (const market of active) {
      const feed = feedNameFromId(market.priceId);
      const livePrice = prices[feed];
      const upPool = Number(formatEther(market.upPool)).toFixed(3);
      const downPool = Number(formatEther(market.downPool)).toFixed(3);
      const timeLeft = timeRemaining(market.expiryTime);
      const stateLabel = STATE_LABELS[market.state];
      const shortAddr = `${market.address.slice(0, 6)}...${market.address.slice(-4)}`;

      text += `${feed} | ${stateLabel}\n`;
      text += `Strike: $${formatPrice(market.strikePrice)}`;
      if (livePrice) text += ` | Now: $${formatPrice(livePrice)}`;
      text += `\n`;
      text += `UP: ${upPool} BNB | DOWN: ${downPool} BNB\n`;
      text += `Time left: ${timeLeft}\n\n`;

      if (market.state === MarketState.Open) {
        kb.text(`${feed} - ${timeLeft}`, `market:${market.address}`).row();
      }
    }

    kb.text("Refresh", "markets").row();
    kb.text("Back", "main");

    await ctx.editMessageText(text, { reply_markup: kb });
  } catch (err) {
    console.error("Markets error:", err);
    await ctx.editMessageText("Failed to load markets. Try again.", {
      reply_markup: new InlineKeyboard().text("Retry", "markets").row().text("Back", "main"),
    });
  }
}

export async function handleMarketDetail(ctx: Context, marketAddress: string) {
  try {
    const market = await getMarketInfo(marketAddress as `0x${string}`);
    const feed = feedNameFromId(market.priceId);

    let livePrice: number | null = null;
    try {
      const prices = await getLatestPrices([feed as FeedName]);
      livePrice = prices[0]?.price ?? null;
    } catch {}

    const upPool = Number(formatEther(market.upPool)).toFixed(4);
    const downPool = Number(formatEther(market.downPool)).toFixed(4);
    const totalPool = Number(formatEther(market.totalPool)).toFixed(4);
    const timeLeft = timeRemaining(market.expiryTime);

    let text = `${feed} Market\n\n`;
    text += `State: ${STATE_LABELS[market.state]}\n`;
    text += `Strike Price: $${formatPrice(market.strikePrice)}\n`;
    if (livePrice) {
      text += `Current Price: $${formatPrice(livePrice)}\n`;
      const diff = ((livePrice - market.strikePrice) / market.strikePrice) * 100;
      text += `Change: ${diff >= 0 ? "+" : ""}${diff.toFixed(2)}%\n`;
    }
    text += `\n`;
    text += `UP Pool: ${upPool} BNB\n`;
    text += `DOWN Pool: ${downPool} BNB\n`;
    text += `Total Pool: ${totalPool} BNB\n`;
    text += `Time Remaining: ${timeLeft}\n`;

    const kb = new InlineKeyboard();

    if (market.state === MarketState.Open) {
      kb.text("UP 0.01", `bet:${marketAddress}:up:0.01`)
        .text("UP 0.05", `bet:${marketAddress}:up:0.05`)
        .text("UP 0.1", `bet:${marketAddress}:up:0.1`)
        .row()
        .text("DOWN 0.01", `bet:${marketAddress}:down:0.01`)
        .text("DOWN 0.05", `bet:${marketAddress}:down:0.05`)
        .text("DOWN 0.1", `bet:${marketAddress}:down:0.1`)
        .row()
        .text("UP Custom", `betcustom:${marketAddress}:up`)
        .text("DOWN Custom", `betcustom:${marketAddress}:down`)
        .row();
    }

    kb.text("Refresh", `market:${marketAddress}`).row();
    kb.text("Back to Markets", "markets");

    await ctx.editMessageText(text, { reply_markup: kb });
  } catch (err) {
    console.error("Market detail error:", err);
    await ctx.editMessageText("Failed to load market details.", {
      reply_markup: new InlineKeyboard().text("Back", "markets"),
    });
  }
}
