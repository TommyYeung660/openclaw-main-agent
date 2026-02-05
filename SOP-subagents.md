# SOP: 新增 OpenClaw Sub Agent（以 Telegram + Docker sandbox skill 為例）

此文件係主 agent 用嚟建立/維護專用 sub agent 的 checklist。

## 目標（先定義）
- Sub agent 只負責單一垂直任務（例：Stardew Wiki Q&A）。
- Telegram 群組回覆必須 mention-gated（`requireMention: true`）。
- 本地查詢/執行必須受控：只允許在 **自己 workspace** + **Docker sandbox** 內運行。

---

## 1) 建立獨立 Workspace
- 建議路徑：`~/.openclaw/workspaces/<agent>-agent/`
- workspace 內至少要有：
  - `SOUL.md`（sub agent system prompt / 行為限制）
  - `USER.md`（對象/稱呼/偏好）
  - `SKILL.md` / `README.md`（skill 使用說明）
  - `scripts/`（查詢/工具腳本）
  - `requirements.txt` 或 `pyproject.toml`（依賴管理）
  - `memory/`（sub agent 自己的記憶檔）

**注意**：主 agent workspace 係 `~/.openclaw/workspace/main-agent`（單數 workspace），sub agent 係 `~/.openclaw/workspaces/...`（複數 workspaces）。

---

## 2) Telegram 綁定（安全）
### 綁定到特定群組
- 用 `bindings` 將群組 peer 綁定到 agent：
  - `bindings: [{ agentId, match: { channel:"telegram", peer:{kind:"group", id:"<chat_id>"} } }]`

### 群組安全策略
- 全局建議：`channels.telegram.groupPolicy: "allowlist"`
- 目標群組 override：
  - `channels.telegram.groups["<chat_id>"].requireMention: true`
  - `channels.telegram.groups["<chat_id>"].allowFrom: ["*"]`

**原因**：Telegram 有 `sender_chat` / anonymous admin 轉發，sender 可能對唔上 allowlist；用 per-group `allowFrom:["*"]` + mention gating 係較安全的折衷。

---

## 3) Session / Memory 隔離
- OpenClaw 會按 `agent + peer` 自動分 lane/session。
- 記憶要落地到該 workspace 的 `memory/`，避免主 agent 個人記憶滲到群組 bot。

---

## 4) openclaw.json 正確配置（最低要求）
### agents.list
- `id`: sub agent id（例如 `stardew-wiki`）
- `workspace`: 指向獨立 workspace
- `tools.deny`: deny 大部分工具，只保留必要能力

### sandbox
- 若要允許受控 exec：用 Docker sandbox
- 推薦：
  - `sandbox.mode: "all"`
  - `sandbox.scope: "agent"`（只 mount 自己 workspace）
  - `sandbox.workspaceAccess: "rw"`（如需建立 venv/快取；否則可用 ro）

---

## 5) 自定義 Skill + Docker sandbox（踩坑總結）
### (A) Docker 必須存在
- 若 host 無 Docker，`sandbox.mode: "all"` 會導致 `spawn docker ENOENT`，甚至令 gateway 崩。

### (B) Debian PEP 668（禁止 system pip）
- Bookworm 內直接 `pip install` 可能報 `externally-managed-environment`。
- 正解：在 `/workspace/.venv` 建 venv，再用 venv pip 裝 requirements。

### (C) ensurepip 缺失
- `python3 -m venv` 需要 `python3-venv` / `python3.11-venv`。
- 若 base image 缺，必須自建 sandbox image 補齊。

### (D) sandbox 不會繼承 host env
- 例如 Ollama 連線需要 `OLLAMA_HOST`，要寫到：
  - `agents.list[].sandbox.docker.env.OLLAMA_HOST = "http://host.docker.internal:11434"`

### (E) 改 sandbox 配置後要 recreate
- 改咗 `sandbox.docker.*` 後：
  - `openclaw sandbox recreate --agent <agentId>`

---

## 6) Sub agent System Prompt（必須限制）
- 明確：只回答指定領域問題（例：Stardew Valley）。
- 明確：只允許執行**單一白名單命令**（例：`./.venv/bin/python3 scripts/query.py ...`）。
- 禁止：其他 exec / 文件讀寫 / web 工具 / 無關問題。

---

## 7) Python 依賴管理（你的標準：python + uv）
- 建議 repo 以 `pyproject.toml + uv.lock` 管理。
- sandbox setupCommand 建議用：
  - `uv venv /workspace/.venv`
  - `uv sync`（或 `uv pip sync`）

---

## 8) GitHub 推送（交付規則）
- 新增/修好 sub agent 後，必須將該 workspace 變成 git repo 並 push。
- 必須有 `.gitignore` 排除：
  - `.venv/`、`venv/`、`data/`、`memory/`、`*.log`

---

## 9) 驗收（最少做 3 個 check）
1. Telegram 群組：@mention 才回覆（非 mention 不回覆）
2. Skill 在 sandbox 內實跑一次（確保依賴、資料、模型、env OK）
3. 任何越權請求（無關問題/要求 shell/讀檔）都會被 prompt 拒絕
