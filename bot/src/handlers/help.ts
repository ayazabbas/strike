import { type Context } from "grammy";
import { mainMenuKeyboard } from "./start.js";

export async function handleHelp(ctx: Context) {
  const text = [
    "Strike Bot - How It Works\n",
    "Strike is a binary options trading bot on BSC. Predict whether an asset's price will go UP or DOWN before the market expires.\n",
    "Getting Started:",
    "1. Use /start to create your wallet",
    "2. Send BNB to your wallet address",
    "3. Browse markets and place bets\n",
    "Commands:",
    "/start - Create wallet & open main menu",
    "/history - View past markets and results",
    "/help - Show this help message\n",
    "How Betting Works:",
    "- Each market has a strike price and expiry time",
    "- Bet UP if you think the price will be above the strike at expiry",
    "- Bet DOWN if you think it will be below",
    "- Winnings are proportional to the pool size",
    "- A 3% protocol fee applies to winnings\n",
    "Menu Options:",
    "Markets - Browse and bet on active markets",
    "My Bets - View your positions and claim winnings",
    "Wallet - Check balance and deposit address",
    "Settings - View bot and network info",
  ].join("\n");

  await ctx.reply(text, { reply_markup: mainMenuKeyboard() });
}
