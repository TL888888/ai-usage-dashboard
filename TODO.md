# 【AI用量統計】ai-usage-dashboard 待辦（交接用，2026-11-02）

> 更完整的歷史待辦在 `C:\Users\113059\Projects\AI用量統計\TODO.md`。

## 已完成（最近）
- [x] f42180c「自建系統用量一律依系統名稱分類（org_directory 只決定公司）」2026-11-02 已上線並在正式站驗收通過：
      10 月台灣大量 3,625,824、10 月 Excel 0 筆、營業部／資材部／企劃室已併進各系統；總覽、各系統用量、儲值與帳單、經營會議簡報正常。

## 2026-11-12 交接（第二個對話，已超過 20 萬 tokens，換新）
已完成並上線（main 最新 b657698，全部已 push）：
- Gemini 校正倍數改用「相鄰兩次手動填的後台餘額」（sql/2026-11-09_Gemini餘額校正.sql 已貼）；③ 變成唯讀倍數明細。
- 資材部兩個回報來源 zicai_meeting／zicai_draw（api/usage-report.js；Vercel 環境變數已由大頭目設好）。兩列要等開發者開始回報才看得到。
- 頁首「🏠 首頁」按鈕。
進行中／待辦：
- [ ] 資材部歸哪家公司：回報沒有提問人 email，目前歸台灣大量；若屬南京，要加「系統→公司」對照（index.html 集團統計 internalMonthRows）。
- [ ] 繪圖軟體若用圖片模型：ai_model_prices 只有文字 tokens 單價，會低估並影響校正倍數；確認實際模型後再決定加單價（需貼 SQL 到 TL_projects）。
- [ ] 資材部兩把 key 若不在同一個 Gemini 帳單餘額，不該混進餘額校正，需告訴我。
- [ ] Gemini 實際餘額 11/09 後沒更新，請 Michelle 定期填 Credit balance（超過 35 天沒填網頁會黃色提醒）。
- [ ] 10/19 前（第一筆餘額前）沒有餘額記錄可校正，若能找到 9/18~10/19 任一天餘額補填 ②。
- [ ] 第 2 步：每週自動讀 Gemini 後台餘額（Claude in Chrome，先只讀）——等小科組長派工，尚未開始。
- 驗收提醒：用 Chrome 驗正式站時，瀏覽器可能暫存舊頁，要重新載入。

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
