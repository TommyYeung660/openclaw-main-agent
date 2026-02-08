# MEMORY.md - Long-term Memory (Main Agent)

## SOP / 原則：新增 Sub Agent（Telegram + Docker sandbox skill）
- **每個 sub agent 必須有獨立 workspace**：`~/.openclaw/workspaces/<agent>-agent/`（與主 agent `~/.openclaw/workspace/main-agent` 分開；注意 workspace/workspaces 單複數）。
- **群組觸發必須 mention-gated**：`channels.telegram.groups[chatId].requireMention: true`。
- **群組安全**：全局 `channels.telegram.groupPolicy: "allowlist"`；針對目標群組可設 `allowFrom:["*"]` 以處理 anonymous admin / `sender_chat`，但仍靠 mention gating 保護。
- **每個 sub agent 有獨立 session + memory**：記憶落地到該 workspace 的 `memory/`，避免主 agent 私人記憶滲到群組 bot。
- **openclaw.json 綁定方式**：用 `agents.list` 建 agent，再用 `bindings` 綁定到指定 Telegram 群組 peer。
- **自定義 skill 建議用 Docker sandbox 運行**：
  - `sandbox.mode: "all"`, `sandbox.scope: "agent"`, `workspaceAccess` 依需要 ro/rw。
  - Debian/Bookworm 常見坑：PEP 668 禁止 system pip → 用 `/workspace/.venv`。
  - `python3 -m venv` 需要 `python3-venv`（ensurepip），必要時自建 sandbox image。
  - sandbox 不會繼承 host env：需用 `sandbox.docker.env` 注入（例：`OLLAMA_HOST=http://host.docker.internal:11434`）。
  - 改 sandbox config 後要 `openclaw sandbox recreate --agent <id>`。
- **Sub agent system prompt 必須嚴格限制**：只回答指定領域、只允許白名單命令（例：`./.venv/bin/python3 scripts/query.py ...`），拒絕其他 exec/寫檔/web 工具/無關問題。
- **Python 依賴管理標準（Tommy 要求）**：自定義 skill 統一採用 Python + uv（`pyproject.toml` + `uv.lock`），sandbox setupCommand 走 `uv venv` + `uv sync`。
- **交付規則**：新增/修好 sub agent 後，必須將該 workspace 推送到 GitHub（含 `.gitignore` 排除 venv/data/log/memory 等大檔）。

## 實例：Stardew Wiki sub agent（2026-02-05）
- 成功把 `stardew-wiki` 綁定到 Telegram 群組並做到 mention-gated 回覆。
- 修正 sandbox 依賴安裝：改用 `/workspace/.venv`；補齊 sandbox image 的 `python3-venv`；並在 `sandbox.docker.env` 注入 `OLLAMA_HOST`。
- 將 `~/.openclaw/workspaces/stardew-wiki-agent` 初始化為 git repo 並 push 到：`git@github.com:TommyYeung660/openclaw-stardew-wiki-agent.git`。

## 操作規則（Tommy）
- **任何會影響 OpenClaw 服務狀態的命令（例如 `openclaw gateway restart` / start / stop / update 等）必須先等 Tommy 確認後先可以執行。**

### 編輯 openclaw.json / 影響 OpenClaw 運行的檔案（重大變更 SOP）
- **絕對不可直接編輯就落地**：每次要改 `openclaw.json`（或類似會直接影響 OpenClaw 運行的配置檔）時，必須先列出「要改邊幾行／哪幾段（含行號或清楚定位）」同「改動內容摘要」，等 Tommy 明確確認後先可以實際執行 edit。
- **每次改之前必須先備份**：備份格式固定：`openclaw.json.bak.YYYYMMDDHHmm`（例：`openclaw.json.bak.202602061151`）。
- **必須寫改動注解文檔**：同一個備份時間戳，另外建立說明檔：`openclaw.json.bak.YYYYMMDDHHmm_changed.md`。
- **備份與注解存放路徑**：統一放在 `/Users/admin/.openclaw/openclaw_json_bak/`。

## Cron SOP（Tommy 已確認，2026-02-09）
- 所有現行 cron 規則已整理到：`docs/cron-sop.md`
- 之後新增/修改 cron job、以及 cron-watch agent 的工作，請以該 SOP 為準。

（舊條目：2026-02-06 的 Cron 設計準則已被 cron-sop.md 吸收整合。）
