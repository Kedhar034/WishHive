import { createHash } from "crypto";

// Parameters that only say where a click came from. Anything not on this list
// is kept, because on an arbitrary site a parameter may well pick the product.
const TRACKING_PARAMS = [
  /^utm_/i,
  /^gclid$/i,
  /^gbraid$/i,
  /^wbraid$/i,
  /^fbclid$/i,
  /^msclkid$/i,
  /^igshid$/i,
  /^srsltid$/i,
  /^mc_cid$/i,
  /^mc_eid$/i,
  /^_ga$/i,
  /^_gl$/i,
  /^affid$/i,
  /^affExtParam\d*$/i,
];

export const WISHHIVE_HOST = "flutterapplication-77c19.web.app";

export function parseHttpUrl(raw: unknown): URL | null {
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (!trimmed || trimmed.length > 2048) return null;
  try {
    const url = new URL(trimmed);
    if (url.protocol !== "https:" && url.protocol !== "http:") return null;
    return url;
  } catch {
    return null;
  }
}

const bareHost = (url: URL) => url.hostname.toLowerCase().replace(/^www\./, "");

export const isWishHiveLink = (url: URL) => bareHost(url) === WISHHIVE_HOST;

const BROWSER_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Accept-Language": "en;q=0.9",
};

/**
 * Follows HTTP redirects to the page a link really points at, so a short
 * link from any shop or any shortener lands on the same cache entry as the
 * full one. Bounded so a slow site cannot hold up the caller.
 */
export async function resolveRedirects(url: URL): Promise<URL> {
  const deadline = Date.now() + 6000;
  let current = url;
  for (let hop = 0; hop < 5; hop++) {
    const left = deadline - Date.now();
    if (left <= 0) break;
    try {
      const res = await fetch(current, {
        method: "GET",
        redirect: "manual",
        headers: BROWSER_HEADERS,
        signal: AbortSignal.timeout(Math.min(left, 4000)),
      });
      await res.body?.cancel().catch(() => undefined);
      const location = res.headers.get("location");
      if (res.status < 300 || res.status >= 400 || !location) break;
      const next = new URL(location, current);
      if (next.protocol !== "https:" && next.protocol !== "http:") break;
      current = next;
    } catch {
      break;
    }
  }
  return current;
}

/**
 * One spelling per product, so the cache is not paid for twice because the
 * same item was shared with different tracking parameters. Amazon and
 * Flipkart get exact rules because their links carry long tracking paths; it
 * applies to every Amazon country, and everything else keeps its own URL.
 */
export function canonicalize(url: URL): URL {
  const out = new URL(url.toString());
  out.hash = "";
  out.protocol = "https:";
  out.hostname = out.hostname.toLowerCase();
  const host = bareHost(out);

  if (/(^|\.)amazon\.[a-z.]+$/.test(host)) {
    const asin = out.pathname.match(
      /\/(?:dp|gp\/product|gp\/aw\/d|d|exec\/obidos\/asin)\/([A-Z0-9]{10})(?:[/?]|$)/i
    );
    if (asin) {
      out.hostname = `www.${host.replace(/^m\./, "")}`;
      out.pathname = `/dp/${asin[1].toUpperCase()}`;
      out.search = "";
      return out;
    }
  }

  if (/(^|\.)flipkart\.com$/.test(host)) {
    out.hostname = "www.flipkart.com";
    const pid = out.searchParams.get("pid");
    out.search = "";
    if (pid) out.searchParams.set("pid", pid);
    return out;
  }

  for (const key of [...out.searchParams.keys()]) {
    if (TRACKING_PARAMS.some((p) => p.test(key))) out.searchParams.delete(key);
  }
  out.searchParams.sort();
  if (out.pathname.length > 1) out.pathname = out.pathname.replace(/\/+$/, "");
  return out;
}

export const cacheKey = (url: URL) =>
  createHash("sha256").update(url.toString()).digest("hex");

/** Where a link really leads, cleaned, and the cache document for it. */
export async function productKey(link: URL) {
  const canonical = canonicalize(await resolveRedirects(link));
  return { canonical, key: cacheKey(canonical) };
}
