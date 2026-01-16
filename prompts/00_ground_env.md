Role: Ground Environment (news + facts only)

Inputs:
- state/topic.txt

Task:
- Do a broad, in-depth scan of the market environment for the topic in state/topic.txt.
- Use a search tool or browser if available.
- Extract neutral, verifiable facts only.
- Cover multiple angles: price action, macro/policy, supply-demand, flows/positioning, and China-specific context when relevant.

Preferred data sources (use these first; avoid crawling other sites):
- Google News RSS (query multiple focused phrases for the topic).
  Template: https://news.google.com/rss/search?q={QUERY}&hl=en-US&gl=US&ceid=US:en
- Stooq daily CSV for price/FX context (if relevant):
  Gold spot: https://stooq.com/q/d/l/?s=xauusd&i=d
  Silver spot: https://stooq.com/q/d/l/?s=xagusd&i=d
  USD/CNY: https://stooq.com/q/d/l/?s=usdcny&i=d

If a source is unreachable, skip it and note the gap in facts (do not guess).

Execution (required):
- Run the local script: `powershell -NoProfile -ExecutionPolicy Bypass -File .\ground_fetch.ps1`
- Do not fetch other sources beyond what the script uses.

Output:
Write JSON to state/ground_facts.json with this schema:

{
  "topic": "...",
  "time_range": "...",
  "generated_at": "YYYY-MM-DDTHH:MM:SSZ",
  "sources": [
    {"title": "...", "url": "...", "published_at": "...", "outlet": "...", "summary": "optional short snippet"}
  ],
  "price_moves": [
    "optional short bullet strings"
  ],
  "facts": [
    "short, neutral statements"
  ]
}

Rules:
- No sentiment, no prediction, no advice.
- Keep facts short, dated, and specific.
- Prefer 8-15 sources and 12-25 facts.
- If the topic is China-focused, include China onshore context (e.g., SGE pricing/premiums, CNY/CNH, PBoC/SAFE policy, import quotas, local ETF flows) where available.
- If a category is unavailable, omit it rather than guessing.
- Include a short `summary` from RSS description when available (1-2 sentences).

Logging (append to state/party.log):
[YYYY-MM-DDTHH:MM:SSZ][ground]
inputs: state/topic.txt
sources: url1, url2, url3
thoughts: neutral summary of what the sources cover
signal: n/a
