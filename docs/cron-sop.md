# Cron SOP（OpenClaw）

> 目的：確保所有現有/未來新增的 cron jobs **準時執行**、**成功或失敗都有可追溯日誌**，並確保 cron-watch agent 能**監控所有 jobs**且**每日發報告到正確 Telegram 群組**。

更新日期：2026-02-09（Asia/Hong_Kong）

---

## 0) 核心原則（總綱）

1. **準時性優先**：任何「必須準時」的 job，避免依賴 heartbeat。
2. **可追溯性優先**：任何 job 必須有「檔案層日誌」作為最終真相來源；`cron.runs` 只作輔助。
3. **單一路徑通知**：cron-watch 報告通知只用 `message.send`，目標固定數字 chat id。

---

## 1) Cron Job 設計準則（避免到點唔跑 / 無 runs / 無法追查）

### 1.1 不依賴 heartbeat 觸發
- **避免**：`wakeMode=next-heartbeat` 用於時間敏感 job。
- **優先**：`wakeMode=now`（到點即跑）。

### 1.2 優先使用 isolated + agentTurn（時間敏感 job）
- **推薦**：`sessionTarget=isolated` + `payload.kind=agentTurn`
- **原因**：避免主 session 不活躍、heartbeat 缺失、或主 session 阻塞時導致 job miss。

> 註：如果某 job 必須在 host 跑 shell，請確保該 agentTurn 有權限使用 `exec`（不要假設 sandbox）。

### 1.3 每個 job 必須有「檔案層日誌」（成功/失敗都要寫）
- 因為：
  - `cron.runs` 可能在 job 未 finished 前查到空陣列（race）
  - 可能出現歷史不完整/缺口/輪替
- 所以：每個 job 要把 stdout/stderr append 到固定路徑 log（最好每日分檔），並寫清楚：
  - START 時間
  - END 時間
  - exit code

**建議模板（shell 片段）**：
```sh
mkdir -p <log_dir>
TS=$(date +%F)
LOG=<log_dir>/<name>-$TS.log
{
  echo "\n===== START $(date '+%F %T') =====";
  <command>;
  EC=$?;
  echo "===== END $(date '+%F %T') exit=$EC =====";
  exit $EC;
} >> "$LOG" 2>&1
```

### 1.4 驗收必做：runs + 檔案日誌 + 產物落地
新增/修改 job 後，最小驗收：
- `cron.list(includeDisabled:true)`：核對 schedule / wakeMode / sessionTarget / payload
- 下次排程或 one-shot 後：
  - `cron.runs(jobId)` 有 finished entry
  - 檔案層日誌存在且含 START/END/exit
  -（如有產物）產物目錄存在（例如 backup 目錄）

---

## 2) Cron-watch Agent 準則（監控所有 jobs + 報告 + 正確發送）

### 2.1 動態掃描所有 jobs（含未來新增）
- 必須用：`cron.list(includeDisabled:true)` 作唯一 job 清單來源。
- 報告要包含：
  - 當日/昨日監控範圍（時區 Asia/Hong_Kong）
  - 每個 job 的 runs 統計（成功/失敗）
  - **資料完整性聲明**：`cron.runs` 是否覆蓋整個區間；若不完整，不能把缺口當作「0 runs」

#### 2.1.1 重要：cron.runs(jobId) 必須用完整 UUID（避免誤報「無 runs」）
- **只能**將 `cron.list()` 回傳的 `job.id`（完整 UUID，例如 `14788e83-f3de-49ca-9900-f87c2b9792c1`）傳入 `cron.runs(jobId)`。
- **禁止**使用「短 id / prefix」（例如 `14788e83`）去 call `cron.runs`：系統會回空陣列，造成 cron-watch **假陰性**（誤判 runs 遺失）。
- 短 id 只可以用於報告顯示（人類易讀），不可用作任何 API 參數。

### 2.2 固定輸出落點（避免寫到 main-agent）
cron-watch 報告/日誌必須硬性鎖定：
- 報告：
  - `/Users/admin/.openclaw/workspace/cron-watch-agent/reports/YYYY-MM-DD.md`
- 日誌：
  - `/Users/admin/.openclaw/workspace/cron-watch-agent/logs/daily-report-YYYY-MM-DD.log`

payload 必須明確寫：
- **Do NOT write reports/logs under main-agent**

### 2.3 Telegram 通知唯一規則（禁止用名字）
- 報告通知只用：`message.send`
- `channel=telegram`
- `to` **必須**是數字 chat id：`-5162606720`
- 禁止：`chat_id=cron-watch` 或任何 alias/name

### 2.4 cron-watch 自身排程
- cron-watch daily report 應使用：`wakeMode=now`（確保 08:00 準時）。

---

## 3) 已驗證可行的具體配置方向（本次修正成果）

- 將「moltbook hourly」與「nightly backup」改為：
  - `sessionTarget=isolated` + `agentTurn` + `wakeMode=now`
  - 並強制寫檔案層日誌

- cron-watch daily report：
  - `wakeMode=now`
  - payload 強制輸出到 `cron-watch-agent/`，並 `message.send` 到 `-5162606720`

---

## 4) 風險與備註

- **macOS 睡眠**：任何本機排程在睡眠期間都有可能 miss；檔案層日誌可追查，但不能魔法保證睡眠期間準時。
- **gateway timeout**：若出現 `gateway timeout after 60000ms`，優先以檔案層日誌/產物驗證真實執行狀態，再決定是否需（經 Tommy 確認後）重啟 gateway。
