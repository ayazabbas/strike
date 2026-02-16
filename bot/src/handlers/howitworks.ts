import { type Context, InlineKeyboard } from "grammy";

const pages = [
  {
    title: "❓ How Strike Works",
    text: [
      "Strike is a price prediction game on BNB Chain.\n",
      "Every 5 minutes, a new round starts with BTC's current price locked in as the strike price.\n",
      "Your job: predict whether BTC will be ABOVE or BELOW that price when the round ends.\n",
      "That's it. Pick a side, place your bet, and wait 5 minutes. 🎯",
    ].join("\n"),
  },
  {
    title: "💰 The Prize Pool",
    text: [
      "All bets go into a shared pool — one side for UP, one for DOWN.\n",
      "When the round ends, the winning side splits the ENTIRE pool.\n",
      "Your share depends on how much you bet vs the total on your side:\n",
      "• If you're 50% of the UP pool and UP wins, you get 50% of everything.\n",
      "• Fewer people on your side = bigger payout.\n",
      "• A 3% fee is taken from winnings only.\n",
      "⏰ Early bird bonus: Bets placed early in the round get up to 2x shares! The multiplier decays linearly from 2x → 1x as betting closes. Bet early for a bigger edge.\n",
      "Example: $10 in UP pool, $30 in DOWN pool. UP wins → UP bettors split $40. If you bet $5 early (with 1.5x multiplier), your shares are worth more than a late $5 bet. 🚀",
    ].join("\n"),
  },
  {
    title: "⏱ Round Timing",
    text: [
      "Each round has two phases:\n",
      "1️⃣ Betting Open (~4 min)\nPlace your bets! The strike price and live BTC price are shown.\n",
      "2️⃣ Betting Closed (~1 min)\nNo more bets. Watch the price and wait for resolution.\n",
      "After 5 minutes, the round resolves automatically using Pyth Network's price oracle. Winners can claim instantly.",
    ].join("\n"),
  },
  {
    title: "🏁 Getting Started",
    text: [
      "1. Tap /start — a wallet is created for you automatically\n",
      "2. Send tBNB to your wallet address (BSC Testnet)\n",
      "3. Tap ⚡ Live to see the current round\n",
      "4. Pick UP 🟢 or DOWN 🔴 and choose your bet size\n",
      "5. Wait for the round to end\n",
      "6. Check 🎲 My Bets to claim your winnings!\n",
      "Tip: Start small (0.01 BNB) to get a feel for it.",
    ].join("\n"),
  },
];

export async function handleHowItWorks(ctx: Context, page = 0) {
  const p = pages[page];
  const kb = new InlineKeyboard();

  if (page > 0) {
    kb.text("« Prev", `howitworks:${page - 1}`);
  }
  if (page < pages.length - 1) {
    kb.text("Next »", `howitworks:${page + 1}`);
  }
  kb.row();
  kb.text("⚡ Go to Live", "live").row();
  kb.text("« Back", "main");

  const text = `${p.title}\n\n${p.text}\n\n📄 ${page + 1}/${pages.length}`;

  await ctx.editMessageText(text, { reply_markup: kb });
}
