# 【AI用量統計】ai-usage-dashboard 待辦（2026-11-12 瘦身；已完成的搬到 TODO_歷史.md）

## 現況
main 最新 b657698（含 11-09 Gemini 校正、資材部兩個回報來源、頁首「🏠 首頁」按鈕），全部已 push。

## 進行中／待確認
- [ ] 資材部歸哪家公司：回報沒有提問人 email，目前歸台灣大量；若屬南京，要加「系統→公司」對照（index.html 集團統計 internalMonthRows）。
- [ ] 資材部兩列（zicai_meeting／zicai_draw）要等開發者開始回報才看得到。繪圖軟體若用圖片模型，`ai_model_prices` 只有文字單價會低估並影響校正倍數；確認模型後再決定加單價（需貼 SQL 到 TL_projects）。
- [ ] 資材部兩把 key 若不在同一個 Gemini 帳單餘額，不該混進餘額校正，需告訴我。
- [ ] Gemini 實際餘額 11/09 後沒更新 → 請 Michelle 定期填 Credit balance（超過 35 天網頁黃色提醒）。
- [ ] 第 2 步：每週自動讀 Gemini 後台餘額（Claude in Chrome，先只讀）——等小科組長派工，尚未開始。
- [ ] 9/18~10/19（第一筆餘額前）沒有餘額可校正，若找得到任一天餘額可補填 ②。
- [ ] 每月 6 日 Excel 自動上傳（Michelle 把檔案放 `C:\TL\AI用量統計\待上傳`）。

## 等 Michelle 決定
- [ ] 共用帳號 tlcs 的「AI用量統計」權限目前是管理員（為了驗收才開），建議改回「無權限」。
- [ ] **Guard system 記進 AI用量統計**（Michelle 11-02 說「記進AI用量統計」，改變 10-19「只靠同事回報」的決定）。小科組長問她「每月填 Gemini 帳單總額時多抄一格 Guard 金額可以嗎」，**她回答前不要動手**。方案：
  - 帳單是台幣（截圖 $12.77＝NT$12.77；那是 10/6～11/2 的數字，記 10 月要改成 10/1～10/31 再看）。
  - **不可重複扣**：Gemini 剩餘、校正倍數裡已含 Guard（被攤到我們各系統），不可再把 Guard 加進餘額。
  - 做法：帳單總額旁加「其中 Guard」一格，存 `ai_monthly_spend` provider=gemini、key_name=`GUARD`；校正倍數改用「總額 − Guard」÷ 我們系統的估算。**注意 11-09 起倍數已改用餘額法，此方案要依新機制重新設計**（SQL 在 TL_projects，開頭加專案檢查）。
  - 各系統表與柱狀圖：Guard 列從「等待回報」改顯示該月實際金額（只有整月有數字）。若同事日後加回報（system_name=guard），要決定以回報或手填為準，避免兩種並存。約 2 小時。

## 不急／長期
- [ ] 光電／PCB 產業訊息分開統計：要在 TL_technology `_market-common.js` 回報時區分領域（總管看板有記）。
- [ ] wechat 免密碼登入也有「閃兩次」：可比照本系統在 `<head>` 先判斷直接跳轉（由 wechat 對話處理）。
- [ ] 各系統每日金額上限集中到 AI用量統計設定（第二階段，Michelle 10-19 同意；尚未規劃派工；上限分散位置見 NOTES）。
- [ ] wechat 的 ai-proxy.js（Groq）沒回報用量。
- [ ] Edge Function `stats-ai-usage-push` 原始碼只在 Supabase，交接 MIS 前應備份進 repo。
- [ ] org_directory 改成直接讀人資系統的公司／部門。
- [ ] 各 API 的 `estimateCostUSD`（每日上限用）固定每百萬 tokens $0.15，Gemini 實際較貴，可考慮調整。
