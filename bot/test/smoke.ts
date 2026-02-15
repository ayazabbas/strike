import { getMarketCount, getMarketAddresses, getMarketInfo } from "../src/services/blockchain.js";
import { getLatestPrices } from "../src/services/pyth.js";

async function main() {
  const count = await getMarketCount();
  console.log("Market count:", count);

  const addrs = await getMarketAddresses(0, 10);
  console.log("Market addresses:", addrs);

  if (addrs.length > 0) {
    const info = await getMarketInfo(addrs[0]);
    console.log("Market info:", {
      state: info.state,
      strikePrice: info.strikePrice,
      tradingEnd: new Date(info.tradingEnd * 1000).toISOString(),
      expiryTime: new Date(info.expiryTime * 1000).toISOString(),
      upPool: info.upPool.toString(),
      downPool: info.downPool.toString(),
    });
  }

  const prices = await getLatestPrices();
  console.log("Pyth prices:", prices.map(p => `${p.feedName}: $${p.price.toFixed(2)}`));

  console.log("\nAll smoke tests passed!");
}

main().catch((err) => {
  console.error("Smoke test failed:", err);
  process.exit(1);
});
