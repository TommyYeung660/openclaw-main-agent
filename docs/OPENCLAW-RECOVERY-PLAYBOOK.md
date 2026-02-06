# OpenClaw 快速修復 / 還原方案（基於本地備份）

> 適用情境：OpenClaw gateway 異常、`openclaw.json` 損壞/誤改、sub agents/workspace 消失、cron jobs 亂咗、sandbox/agents/bindings 配置錯亂。
>
> 本方案以每日備份產物為唯一可信來源：
> - 備份 root：`/Users/admin/openclaw_backup/`
> - 最新：`/Users/admin/openclaw_backup/latest`（symlink）
> - 每日快照：`/Users/admin/openclaw_backup/nightly/YYYY-MM-DD/`

---

## 0) 原則（先保命再修）
1) **先止血、後還原**：先確認當前狀態，避免覆蓋掉仍然可用嘅資料。
2) **只改必要範圍**：優先還原 `openclaw.json`、cron jobs、workspaces；其他（logs/cache）按需。
3) **敏感資料保護**：備份內可能包含 tokens/credentials（例如 `.openclaw/credentials/*`、以及某些 workspace 的 `secrets/*`）。
4) **會影響 OpenClaw 服務狀態（restart/start/stop/update）**：按 Tommy 現行規則，必須由 Tommy 明確確認先做。

---

## 1) 快速判斷問題類型（3 分鐘內）
### A. Gateway 係咪仲活著
在 host terminal：
- `openclaw status`
- 檢查近期 logs（如需要）：`/Users/admin/.openclaw/logs/gateway.log`、`gateway.err.log`

### B. 配置檔是否壞
- `python3 -m json.tool /Users/admin/.openclaw/openclaw.json >/dev/null && echo JSON_OK`

### C. cron scheduler 是否正常
- 用 OpenClaw 工具：`cron.list(includeDisabled=true)`
- 如 jobs 消失：優先檢查 `.openclaw/cron/jobs.json`

---

## 2) 備份位置與內容（你應該知道備份有咩）
以最新備份為例：
- `BK=/Users/admin/openclaw_backup/latest`
- workspaces：`$BK/workspaces/*`
- OpenClaw 設定快照：`$BK/openclaw-dot/.openclaw/`
  - `openclaw.json`
  - `openclaw_json_bak/`（你的 SOP 備份/注解全集）
  - `cron/jobs.json`（cron job 定義）
  - `agents/`（agent 定義/模型資訊）
  - `identity/`、`credentials/`（高度敏感）
- manifest：`$BK/manifests/`

> 注意：目前備份腳本排除 `.openclaw/media/`（依 Tommy 選項）。如需媒體檔要另行處理。

---

## 3) 典型故障 → 對應修復路徑

### 3.1 `openclaw.json` 壞咗／被誤改（最常見）
**目標**：用備份覆蓋還原，並保留你既有 SOP 備份紀錄。

建議步驟：
1) 設定備份路徑：
   - `BK=/Users/admin/openclaw_backup/latest/openclaw-dot/.openclaw`
2) 先備份現況（就算已壞都要留底）：
   - `cp /Users/admin/.openclaw/openclaw.json /Users/admin/.openclaw/openclaw.json.broken.$(date +%Y%m%d%H%M%S) || true`
3) 覆蓋還原：
   - `cp "$BK/openclaw.json" /Users/admin/.openclaw/openclaw.json`
4) 驗 JSON：
   - `python3 -m json.tool /Users/admin/.openclaw/openclaw.json >/dev/null && echo JSON_OK`

> 若只是少量 agent/workspace 被誤刪：仍然建議先全檔還原，再做最小差異修補，避免 bindings/agents.list 不一致。

### 3.2 sub agent workspace 消失 / 被改壞
**目標**：把 `/Users/admin/.openclaw/workspace/*` 還原。

步驟：
1) `BK=/Users/admin/openclaw_backup/latest/workspaces`
2) 先備份現況 workspace（如果仍存在）：
   - `mv /Users/admin/.openclaw/workspace /Users/admin/.openclaw/workspace.broken.$(date +%Y%m%d%H%M%S) || true`
3) 還原：
   - `rsync -a --delete "$BK/" /Users/admin/.openclaw/workspace/`

### 3.3 cron jobs 消失 / scheduler 混亂
**目標**：以備份的 cron jobs 定義為準。

優先檢查：
- `BK=/Users/admin/openclaw_backup/latest/openclaw-dot/.openclaw/cron/jobs.json`

還原策略（由保守到激進）：
1) 只讀對照：比較現況與備份 `jobs.json`
2) 如確認現況壞：用備份覆蓋 `jobs.json`
   - `cp "$BK/cron/jobs.json" /Users/admin/.openclaw/cron/jobs.json`

> 覆蓋後，通常需要 gateway reload/restart 才會完全生效（此步驟需 Tommy 明確確認）。

### 3.4 Telegram delivery / chat id 出錯殘留（常見：chat not found）
- 用 `cron.list` 找到有問題嘅 job
- `cron.update(jobId, patch={delivery:{...}})` 修正 to/chat id
- 用 one-shot `schedule.kind=at` + `cron.wake` 驗證 scheduler 層

---

## 4) GitHub 還原（本地硬盤壞/整個資料夾冇咗時用）
如 `/Users/admin/.openclaw/workspace/<agent>` 整個遺失：
1) 先建立 workspace root：`mkdir -p /Users/admin/.openclaw/workspace`
2) 逐 repo clone 回來（例）：
   - main-agent：`git clone git@github.com:TommyYeung660/openclaw-main-agent.git /Users/admin/.openclaw/workspace/main-agent`
   - cron-watch-agent：`git clone git@github.com:TommyYeung660/openclaw-cron-watch-agent.git /Users/admin/.openclaw/workspace/cron-watch-agent`
   - 其他 agents 同理
3) clone 完，對應 `openclaw.json` 的 workspace path 是否一致（必要時修 `openclaw.json`）

> 注意：如果某些 workspace 含 `memory/` 或 `state/` 但被 `.gitignore` 排除，GitHub 可能唔包含；此時應以本地備份為準。

---

## 5) 復原後驗證清單（10 分鐘內）
1) `openclaw.json`：JSON OK
2) `cron.list(includeDisabled=true)`：jobs 存在，nextRunAt 合理
3) Telegram 方向：
   - bot 仲喺群組內
   - delivery chat id 正確（例如 `-5162606720`）
4) sub agent：
   - 用 Telegram 端對相關 bot `/reset` 或 `/new`（載入新 config）
5) nightly backup job：
   - 確認仍存在：`openclaw nightly backup + git push`（01:00）

---

## 6) 已知風險 / 注意事項（來自目前備份內容觀察）
- 備份內存在敏感檔：
  - `/Users/admin/openclaw_backup/latest/openclaw-dot/.openclaw/credentials/*`
  - 以及某些 workspace 可能有 `secrets/*`（例如 moltbook-agent）
  若要把備份搬到外置硬碟/雲端，建議另行加密或最少嚴格權限（700）。
- `.openclaw/media/` 未被備份（按設定），需要時要另外處理。

---

## 7) 最短路徑（TL;DR）
- 配置壞：還原 `openclaw.json`（從 `.../openclaw-dot/.openclaw/openclaw.json`）
- workspace 壞：還原 `.../workspaces/*` 到 `~/.openclaw/workspace/`
- cron 壞：對照/還原 `.../openclaw-dot/.openclaw/cron/jobs.json`
- 最後驗證：`openclaw status` + `cron.list` + Telegram `/reset`

