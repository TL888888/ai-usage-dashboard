# Gemini 校正倍數用「相鄰兩次手動餘額」算（11-09 起）
- 做法：實際花費＝前次餘額＋期間儲值−這次餘額；倍數＝實際÷同期間官方單價估算。函式 ai_gemini_segments / ai_gemini_costed / ai_gemini_by_system / ai_gemini_month_est / ai_gemini_daily；SQL sql/2026-11-09_Gemini餘額校正.sql。
- 陷阱：帳單金額 0 不接受（舊版倍數會變 0）；第一筆餘額（10/19）之前沒有可校正記錄；舊每月帳單資料（ai_monthly_spend key_name=__TOTAL__）留當備援；超過 35 天沒填餘額網頁會黃色提醒。
- 陷阱：Guard 與資材部的用量若在同一張 Gemini 帳單，已被攤進倍數；不可再把 Guard 加進餘額（會重複扣）。圖片模型若按張數計價，ai_model_prices 只有文字單價會低估並影響倍數；對不到的模型一律當 2.5 Flash。
- 幣別：AI Studio 帳單是台幣（NT$947、10 月 53.34 對得上）。
