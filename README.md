# LynchCocktailParty

LynchCocktailParty is an experimental toy by the author. It is a small, file-based
multi-agent simulation inspired by Peter Lynch's "cocktail party" intuition about
market sentiment. This project is for exploration and narrative experiments only.
Not financial advice.

What it does
- Builds a neutral "ground facts" snapshot from recent headlines and price data.
- Runs five market personas (Level-0 to Level-4) that react differently.
- Produces a "God/Oracle" summary that looks for divergences and crowd extremes.

Quick start (Codex/Claude Code)
1) Edit the topic
   - `state/topic.txt`

2) Build Ground facts (RSS + Stooq CSV)
   - `powershell -NoProfile -ExecutionPolicy Bypass -File .\ground_fetch.ps1`

3) Run Level-0 -> God (use gpt-5.2 by default)
   - `.\run.ps1 -SkipGround -BypassSandbox -Sandbox danger-full-access -NoSearch`

4) Read the outputs
   - `state/report.json`
   - `state/report.md`
   - `state/party.log`

Optional: Live log view
`Get-Content state/party.log -Wait`

Structure
- `prompts/` prompt templates for each role
- `state/` shared inputs/outputs
- `ground_fetch.ps1` RSS + price fetch for the Ground environment
- `run.ps1` sequential runner
- `RUNBOOK.md` step-by-step instructions

Notes
- Downstream roles only read `state/ground_facts.json` and never open links.
- If a source is unreachable, the Ground step records a gap instead of guessing.
