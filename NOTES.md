# 【AI用量統計】ai-usage-dashboard 注意事項（交接用）

> 兩個資料夾：本資料夾＝**程式碼 repo**（git，push main → Vercel 自動部署）；`C:\Users\113059\Projects\AI用量統計\`＝Excel、簡報原始碼、每月自動上傳腳本（無 git，其 NOTES 只講簡報／Excel／電腦端）。
> 歷史流水帳在 `NOTES_歷史.md`、`TODO_歷史.md`（平常不讀）。2026-11-12 瘦身並把教訓拆進 `教訓\`。

## 系統是什麼
- 網址：https://ai-usage-dashboard-sooty-five.vercel.app （tl-home.com 首頁卡片「AI用量統計」）
- 資料庫：Supabase **TL_projects**（bvuygyajzupeqpqfwmgi）。SQL 都存 `sql/`；要 Michelle 貼的 SQL 開頭一定要有專案檢查。
- 目的：總經理看集團各公司 AI 推動積極度（tokens）＋自家雲端系統用量與費用。
- 分頁：總覽（兩張餘額大卡片＋柱狀圖）｜各系統用量｜儲值與帳單｜集團各公司統計｜經營會議簡報
- 登入：免密碼，靠人資系統 `members.ai_usage_role`（`api/tl-sso.js`）。**交接 MIS**：人資系統把 MIS 設成管理員、關掉 Michelle 的，不用改程式；另移交 Vercel 環境變數、DeepInfra 帳號、Google AI Studio 帳單、定期填 Gemini 餘額的工作。
- 費用概要：DeepInfra＝實際（每天 23 點自動抓，`api/deepinfra-snapshot.js`，美金）；Gemini＝估算（tokens×官方單價×匯率 32×校正倍數），Michelle 定期填後台餘額校正（台幣）。紅色提醒 ≥70%（`CREDIT_ALERT_PCT`）。
- 自動上傳：`api/auto-import.js`＋`api/_parse.js`，電腦排程每月 6 日 17:00。回報端點：`api/usage-report.js`。
- 簡報分頁 `deck.html` 由 AI用量統計 資料夾 `node src\build.cjs` 產生後複製過來。

## 工作守則
- 修改前先列「會碰到的既有功能」，改完逐項實測（網頁、手機）；回報寫「既有功能檢查」。本機網頁在 Claude 瀏覽器跑不了，只能上線後在正式站驗收（Michelle 的 Chrome 開新分頁只看不改；瀏覽器可能暫存舊頁要重新載入）。
- Michelle 說「本來正常、現在怪」→ 查 git／SQL 紀錄，白話說明是哪次改動造成。

## 教訓索引（開機不讀；要做那類工作前，先讀對應檔，都在 `教訓\`）
| 做什麼工作時 | 讀哪個檔 |
|---|---|
| 動 Gemini 費用／餘額／估算、解釋為何和帳單不符 | 費用_Gemini只能估算不可當實際花費.md |
| 動 Gemini 校正倍數、儲值與帳單 ③、餘額填寫 | 費用_Gemini校正倍數_用餘額法算.md |
| 動 DeepInfra 抓餘額、排程、金鑰 | 費用_DeepInfra自動抓餘額的單位與陷阱.md |
| 寫任何加總／統計／網頁查詢 | 計算_加總一律在資料庫函式不可limit.md |
| 動供應商、Key 名稱、系統名稱／卡片改名 | 供應商名稱_google與gemini要統一.md |
| 動集團各公司統計、org_directory、部門歸屬 | 集團統計_自建系統一律依系統名稱分類.md |
| 動 Excel 匯入、自動上傳、重傳月報 | Excel匯入_上傳舊檔會蓋掉新資料.md |
| 改經營會議簡報／deck.html／pptx | 簡報_用詞原則與排版規則.md |
| 動登入、權限、tlcs 帳號、交接 MIS | 登入_人資權限免密碼與12小時失效.md |
| 加外部回報來源、處理 Guard／資材部 | 回報端點_新增外部來源與Guard資材部.md |
| 做「每日金額上限集中」或動各系統上限 | 上限_各系統每日金額上限分散位置.md |
