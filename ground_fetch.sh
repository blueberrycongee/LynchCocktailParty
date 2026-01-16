#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPIC_FILE="$ROOT/state/topic.txt"
OUT_FILE="$ROOT/state/ground_facts.json"
LOG_FILE="$ROOT/state/party.log"

if [[ ! -f "$TOPIC_FILE" ]]; then
  echo "Missing topic file: $TOPIC_FILE" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi

export ROOT TOPIC_FILE OUT_FILE LOG_FILE

python3 - <<'PY'
import csv
import json
import os
import re
from datetime import datetime, timezone, timedelta
from email.utils import parsedate_to_datetime
from html import unescape
from io import StringIO
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

root = os.environ["ROOT"]
topic_path = os.environ["TOPIC_FILE"]
out_path = os.environ["OUT_FILE"]
log_path = os.environ["LOG_FILE"]

with open(topic_path, "r", encoding="utf-8", errors="ignore") as f:
    text = f.read()

fields = {}
for line in text.splitlines():
    if ":" in line:
        k, v = line.split(":", 1)
        fields[k.strip()] = v.strip()

topic = fields.get("topic", "unknown")
time_range = fields.get("time_range", "last_7_days")
notes = fields.get("notes", "")

def rss_url(query: str) -> str:
    from urllib.parse import quote
    return "https://news.google.com/rss/search?q=" + quote(query) + "&hl=en-US&gl=US&ceid=US:en"

queries = []
queries.append(topic)
queries.append(f"{topic} price")
queries.append(f"{topic} demand")
queries.append(f"{topic} policy")
queries.append(f"{topic} ETF")
if re.search(r"China|Chinese|Shanghai|SGE|PBoC|SAFE", topic, re.IGNORECASE):
    queries.append("Shanghai Gold Exchange premium")
    queries.append("PBoC gold reserves")
    queries.append("China gold import quotas")
if notes:
    queries.append(notes)

seen_q = []
for q in queries:
    if q not in seen_q:
        seen_q.append(q)
queries = seen_q[:5]
rss_urls = [rss_url(q) for q in queries]

def clean_text(value: str) -> str:
    if not value:
        return ""
    text = unescape(value)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:300]

items = []
rss_unavailable = []

for url in rss_urls:
    try:
        req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req, timeout=30) as resp:
            data = resp.read()
        root_xml = ET.fromstring(data)
        channel = root_xml.find("channel")
        if channel is None:
            continue
        for item in channel.findall("item"):
            title = (item.findtext("title") or "").strip()
            link = (item.findtext("link") or "").strip()
            pub = (item.findtext("pubDate") or "").strip()
            source_el = item.find("source")
            outlet = (source_el.text or "").strip() if source_el is not None else "Google News"
            summary = clean_text(item.findtext("description") or "")
            items.append(
                {
                    "title": title,
                    "url": link,
                    "published_at": pub,
                    "outlet": outlet or "Google News",
                    "summary": summary,
                    "rss_url": url,
                }
            )
    except Exception:
        rss_unavailable.append(url)

cutoff = datetime.now(timezone.utc) - timedelta(days=7)
seen_links = set()
filtered = []

for it in items:
    if not it["title"] or not it["url"]:
        continue
    if it["url"] in seen_links:
        continue
    pub = it.get("published_at")
    if pub:
        try:
            pub_dt = parsedate_to_datetime(pub)
            if pub_dt.tzinfo is None:
                pub_dt = pub_dt.replace(tzinfo=timezone.utc)
            if pub_dt < cutoff:
                continue
        except Exception:
            continue
    seen_links.add(it["url"])
    filtered.append(it)

sources = filtered[:15]

def fetch_stooq(url: str):
    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urlopen(req, timeout=30) as resp:
        data = resp.read().decode("utf-8", errors="ignore")
    return list(csv.DictReader(StringIO(data)))

price_moves = []
price_facts = []
stooq_urls = {
    "XAUUSD": "https://stooq.com/q/d/l/?s=xauusd&i=d",
    "XAGUSD": "https://stooq.com/q/d/l/?s=xagusd&i=d",
    "USDCNY": "https://stooq.com/q/d/l/?s=usdcny&i=d",
}
stooq_unavailable = []

for symbol, url in stooq_urls.items():
    try:
        rows = [r for r in fetch_stooq(url) if r.get("Date")]
        rows.sort(key=lambda r: r["Date"])
        if len(rows) >= 2:
            last = rows[-1]
            prev = rows[-2]
            last_close = float(last["Close"])
            prev_close = float(prev["Close"])
            chg = last_close - prev_close
            chg_pct = (chg / prev_close) * 100.0 if prev_close else 0.0
            price_moves.append(
                f"{symbol} close {last['Date']}: {last_close:.4f} (change {chg:+.4f}, {chg_pct:+.2f}%)."
            )
        if len(rows) >= 7:
            window = rows[-7:]
            start = window[0]
            end = window[-1]
            start_close = float(start["Close"])
            end_close = float(end["Close"])
            chg = end_close - start_close
            chg_pct = (chg / start_close) * 100.0 if start_close else 0.0
            price_facts.append(
                f"{symbol} 7-trading-day change {start['Date']} to {end['Date']}: {chg:+.4f} ({chg_pct:+.2f}%)."
            )
            lows = [float(r["Low"]) for r in window if r.get("Low")]
            highs = [float(r["High"]) for r in window if r.get("High")]
            if lows and highs:
                price_facts.append(
                    f"{symbol} 7-trading-day range {start['Date']} to {end['Date']}: low {min(lows):.4f}, high {max(highs):.4f}."
                )
    except Exception:
        stooq_unavailable.append(url)

facts = []
for s in sources:
    title = s.get("title")
    outlet = s.get("outlet", "Google News")
    pub = s.get("published_at")
    if title:
        if pub:
            facts.append(f"{pub}: {outlet} reported '{title}'.")
        else:
            facts.append(f"{outlet} reported '{title}'.")

for url in sorted(set(rss_unavailable)):
    facts.append(f"Gap: Google News RSS unavailable for {url}.")
for url in stooq_unavailable:
    facts.append(f"Gap: Stooq CSV unavailable for {url}.")
if len(sources) < 8:
    facts.append(
        f"Gap: Only {len(sources)} Google News RSS items available within last_7_days for the selected queries."
    )

facts.extend(price_facts)
if len(facts) < 12:
    for pm in price_moves:
        facts.append(f"Price data: {pm}")

facts = facts[:25]

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
payload = {
    "topic": topic,
    "time_range": time_range,
    "generated_at": now,
    "sources": [
        {
            "title": s.get("title", ""),
            "url": s.get("url", ""),
            "published_at": s.get("published_at", ""),
            "outlet": s.get("outlet", "Google News"),
            "summary": s.get("summary", ""),
        }
        for s in sources
    ],
    "price_moves": price_moves,
    "facts": facts,
}

with open(out_path, "w", encoding="utf-8") as f:
    f.write(json.dumps(payload, ensure_ascii=True, indent=2))

log_sources = rss_urls + list(stooq_urls.values())
log_line = (
    f"[{now}][ground]\n"
    "inputs: state/topic.txt\n"
    f"sources: {', '.join(log_sources)}\n"
    "thoughts: Google News RSS headlines for the topic and Stooq spot price/FX closes.\n"
    "signal: n/a\n"
)

try:
    with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
        existing = f.read()
except FileNotFoundError:
    existing = ""

with open(log_path, "w", encoding="utf-8") as f:
    f.write(existing + log_line)
PY
