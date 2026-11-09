# 【AI用量統計】ai-usage-dashboard 待辦（交接用，2026-11-02）

> 更完整的歷史待辦在 `C:\Users\113059\Projects\AI用量統計\TODO.md`。

## 已完成（最近）
- [x] f42180c「自建系統用量一律依系統名稱分類（org_directory 只決定公司）」2026-11-02 已上線並在正式站驗收通過：
      10 月台灣大量 3,625,824、10 月 Excel 0 筆、營業部／資材部／企劃室已併進各系統；總覽、各系統用量、儲值與帳單、經營會議簡報正常。

## 進行中（2026-11-09 小科組長派工）
- [ ] Gemini 餘額校正：SQL 與網頁已寫好、本機只驗了 SQL（pglite 模擬），**等 Michelle 貼 sql/2026-11-09_Gemini餘額校正.sql 到 TL_projects，再 push、正式站驗收**；第 2 步（每週自動讀後台餘額）等派工。

## 等 Michelle 決定
- [ ] 共用帳號 tlcs 的「AI用量統計」權限目前是管理員（為了驗收才開），建議改回「無權限」，由 Michelle 決定。
- [ ] **Guard system 記進 AI用量統計**（Michelle 11-02：「記進AI用量統計」，改變 10-19「只靠同事回報、不手動填」的決定）。小科組長正在問她，**她回答前不要動手**。方案：
  - 幣別：AI Studio 帳單是台幣，截圖的 $12.77＝NT$12.77。
  - **不可重複扣**：每月填的 Gemini 帳單總額本來就含 Guard，所以 Gemini 剩餘、校正倍數裡已經含 Guard（被攤到我們各系統）。不可以再把 Guard 加進餘額。
  - 做法：「儲值與帳單 → ③ 每月 Gemini 實際帳單」總額旁加一格「其中 Guard system」，每月一起填（AI Studio Spend 頁，金鑰篩選 Guard system，日期上個月 1 號到月底）。
    - 存法建議：`ai_monthly_spend` provider=gemini、key_name=`GUARD`。
    - 校正倍數改用「總額 − Guard」÷ 我們系統的估算（改 `ai_gemini_month_factors()`，**SQL 在 TL_projects**，開頭加專案檢查）。
    - Gemini 剩餘維持照總額（含 Guard），不變。
    - 「各系統 tokens 與花費」表與總覽柱狀圖：Guard 那列從「等待回報」改成顯示該月實際金額（只有整月有數字，其他區間「—」）。
    - 若之後同事加了回報程式（api/usage-report.js 收到 system_name=guard），要決定以回報為準還是手填為準，避免兩種做法並存。
  - 工作量約 2 小時（1 份 SQL＋網頁）。給同事的回報說明可先不轉交。
  - 要問 Michelle 的問題：「每月填 Gemini 帳單總額時，多抄一格 Guard system 金額，可以嗎？」
  - 提醒：截圖的 12.77 是 10/6～11/2 的金額；記 10 月要把日期改成 **10/1～10/31** 再看一次。

## 其他進行中／不急
- [ ] 每月 1～6 日：Michelle 到 AI Studio 填上個月 Gemini 帳單總額（倍數校正用）；每月 6 日 Excel 自動上傳。
- [ ] 光電／PCB 產業訊息分開統計：要在 TL_technology 的 `_market-common.js` 回報時區分領域（總管記在看板）。
- [ ] 營業商務訊息（wechat）免密碼登入也有「閃兩次」：可比照本系統在 `<head>` 先判斷直接跳轉（由 wechat 對話處理）。
- [ ] 各系統每日金額上限集中到 AI用量統計設定（第二階段，2026-10-19 Michelle 同意「兩個都要」，尚未規劃派工）。注意上限是用估算判斷。
- [ ] wechat 的 ai-proxy.js（Groq）沒有回報用量。
- [ ] Edge Function `stats-ai-usage-push` 程式碼只在 Supabase 上，交接前應備份進 repo。
- [ ] （長期）org_directory 改成直接讀人資系統的公司／部門。
