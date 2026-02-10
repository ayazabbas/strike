import { PYTH, type FeedName } from "../config.js";

export interface PythPrice {
  feedName: FeedName;
  price: number;
  confidence: number;
  publishTime: number;
}

/**
 * Fetch latest prices from Pyth Hermes REST API.
 */
export async function getLatestPrices(feeds?: FeedName[]): Promise<PythPrice[]> {
  const feedNames = feeds ?? (Object.keys(PYTH.feeds) as FeedName[]);
  const ids = feedNames.map((f) => PYTH.feeds[f]);

  const params = new URLSearchParams();
  for (const id of ids) params.append("ids[]", id);

  const res = await fetch(`${PYTH.hermesUrl}/v2/updates/price/latest?${params}`);
  if (!res.ok) throw new Error(`Pyth API error: ${res.status}`);

  const data = (await res.json()) as {
    parsed: Array<{
      id: string;
      price: { price: string; expo: number; conf: string; publish_time: number };
    }>;
  };

  return data.parsed.map((p) => {
    const feedName = feedNames.find((f) => PYTH.feeds[f].replace("0x", "") === p.id)!;
    const price = Number(p.price.price) * 10 ** p.price.expo;
    const confidence = Number(p.price.conf) * 10 ** p.price.expo;
    return { feedName, price, confidence, publishTime: p.price.publish_time };
  });
}

/**
 * Get raw price update data (VAA) for submitting to on-chain contracts.
 */
export async function getPriceUpdateData(feedIds: string[]): Promise<string[]> {
  const params = new URLSearchParams();
  for (const id of feedIds) params.append("ids[]", id);

  const res = await fetch(`${PYTH.hermesUrl}/v2/updates/price/latest?${params}`);
  if (!res.ok) throw new Error(`Pyth API error: ${res.status}`);

  const data = (await res.json()) as { binary: { data: string[] } };
  return data.binary.data.map((d) => `0x${d}`);
}

/**
 * Format a price for display.
 */
export function formatPrice(price: number): string {
  if (price >= 1000) return price.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  if (price >= 1) return price.toFixed(4);
  return price.toFixed(6);
}
