# 【AI用量統計】ai-usage-dashboard 注意事項（交接用）

> 詳細的歷史紀錄、計算規則、每次改版的原因，都在 **`C:\Users\113059\Projects\AI用量統計\NOTES.md`**（同一個系統的另一個資料夾，放 Excel 資料、簡報原始碼）。
> 本檔是給「接手的新對話／MIS」的總整理，2026-11-02 由舊對話（已超過 66 萬 tokens，依規則換新）寫下。

## 系統是什麼
- 網址：https://ai-usage-dashboard-sooty-five.vercel.app （tl-home.com 首頁卡片「AI用量統計」）
- 原始碼：本資料夾（GitHub repo，push 到 main 會由 Vercel 自動部署）
- 資料庫：Supabase **TL_projects**（bvuygyajzupeqpqfwmgi）
- 登入：**沒有帳號密碼**。從 tl-home.com 首頁點卡片 → `api/tl-sso.js` 讀 TL_technology 人資系統 `members.ai_usage_role`（無權限／僅讀取 reader／管理員 admin）→ 免密碼登入。
  資料庫只認 12 小時內跟人資確認過的人（`dashboard_admins.sso_verified_at`），所以人資取消權限最晚 12 小時失效。
- **交接給 MIS**：人資系統把 MIS 的「AI用量統計」設成管理員、關掉 Michelle 的即可，不用改程式。另要移交 Vercel 環境變數、DeepInfra 帳號、Google AI Studio 帳單、每月填帳單的工作。

## 分頁（2026-10-19 改版）
總覽（兩張餘額大卡片＋柱狀圖）｜各系統用量｜儲值與帳單｜集團各公司統計｜經營會議簡報

## 費用怎麼算（重要）
- **DeepInfra＝實際**：`api/deepinfra-snapshot.js` 每天台灣 23 點左右（vercel.json 排程 UTC 15:00）自動抓 DeepInfra 實際餘額與每月花費。單位已實測是美金。
- **Gemini＝估算**：tokens × 官方單價（表 `ai_model_prices`）× 匯率（`ai_provider_settings.usd_to_currency`，32）× **校正倍數**。
  - Google 沒有任何 API 能查 Gemini 餘額，所以只能估算＋每月對帳。
  - 校正倍數＝每月實際帳單 ÷ 官方單價估算（函式 `ai_gemini_month_factors()`）。帳單填在「儲值與帳單 → ③ 每月 Gemini 實際帳單」，存在 `ai_monthly_spend`（provider=gemini、key_name=`__TOTAL__`），**台幣**。
  - 2026-11-02 時倍數 ×1.11（依 10 月帳單）。帳單金額 0 不接受（倍數會變 0）。幾乎沒用量的月份不用填。
  - Gemini 剩餘：從儲值金額或最近一次手動填的實際餘額往下扣估算。
- AI Studio 帳單幣別確認是**台幣**（2026-10-19 Credit balance NT$947、10 月帳單 53.34 對得上）。

## 集團各公司統計（2026-11-02 改）
- Excel 月報匯入的資料 → 照 Excel 上填的部門。
- 公司自建 AI 系統的用量 → **一律依系統名稱（首頁卡片名稱，`SYSTEM_LABELS`）分類**；`org_directory` 只用來決定「算哪家公司」（找不到算台灣大量）。不再有「未分類」。

## 其他
- 系統名稱一律＝首頁卡片名稱（`SYSTEM_LABELS`，index.html）。光電／PCB 共用同一支程式回報（system_name=market），目前合併顯示。
- Guard system（同事 janny0831 的掛號包裹登記，金鑰在同一個 Gemini 專案、同一張帳單）：目前表格固定一列「等待回報」。回報端點 `api/usage-report.js`（密語 `GUARD_REPORT_TOKEN`，只在 Vercel）已上線，給同事的說明在 `C:\Users\113059\Projects\掛號包裹登記\給同事_AI用量回報.md`（**尚未轉交**）。新方案見 TODO.md。
- 每月自動上傳 Excel：`api/auto-import.js`（AUTO_IMPORT_TOKEN），電腦排程每月 6 日 17:00。
- SQL 都存在 `sql/`；要 Michelle 貼的 SQL 開頭一定要有專案檢查。
- 修改前先列「會碰到的既有功能」，改完逐項實測；本機網頁在 Claude 的瀏覽器跑不了，只能上線後在正式站驗收（需要有人在 Claude 的瀏覽器登入，或在 Michelle 的 Chrome 開新分頁只看不改）。
