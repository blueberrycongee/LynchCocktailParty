# Runbook (sequential)

Prereq: one Codex/Claude Code window per role, run in order.

Auto mode (single command)
- edit `state/topic.txt`
- run `.\run.ps1` (adds `-FullAuto` to reduce approvals)

Auto mode (watch topic changes)
- run `.\watch.ps1` (add `-FullAuto` if desired)

0) Set the topic
- edit `state/topic.txt` with the target asset/topic and time range

0.5) (Optional) Live log view
- run: `Get-Content state/party.log -Wait`

1) Ground Environment (news + facts)
- open a Codex window for "Ground"
- use `prompts/00_ground_env.md`
- write output JSON to `state/ground_facts.json`
- append log block to `state/party.log`

2) Level-0 Noise Trader
- use `prompts/01_level0_noise_trader.md`
- inputs: `state/ground_facts.json`
- output: `state/level0.json`
- append log block to `state/party.log`

3) Level-1 Trend Follower
- use `prompts/02_level1_trend_follower.md`
- inputs: `state/ground_facts.json`, `state/level0.json`
- output: `state/level1.json`
- append log block to `state/party.log`

4) Level-2 Fundamentalist
- use `prompts/03_level2_fundamentalist.md`
- inputs: `state/ground_facts.json`
- output: `state/level2.json`
- append log block to `state/party.log`

5) Level-3 Contrarian
- use `prompts/04_level3_contrarian.md`
- inputs: `state/ground_facts.json`, `state/level0.json`, `state/level1.json`, `state/level2.json`
- output: `state/level3.json`
- append log block to `state/party.log`

6) Level-4 Skeptic
- use `prompts/05_level4_skeptic.md`
- inputs: `state/ground_facts.json`, `state/level0.json`, `state/level1.json`, `state/level2.json`, `state/level3.json`
- output: `state/level4.json`
- append log block to `state/party.log`

7) God / Oracle
- use `prompts/06_god_oracle.md`
- inputs: all files above
- outputs: `state/report.json` and `state/report.md`
- append log block to `state/party.log`

Notes
- Keep Ground facts neutral (no sentiment, no predictions).
- Each role should only write its own file in `state/`.
- The log is append-only; do not edit other roles' entries.
