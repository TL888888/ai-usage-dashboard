# Gemini 費用只能估算（Google 沒有查餘額的 API）
- 發生什麼：10/16 估算約 US$0.13、AI Studio 帳單卻顯示 48.02，差很多；Michelle 曾決定「費用一律看實際、不用 tokens 推算」，後來因 Google 無 API 查 Gemini 餘額／依 Key 花費，10/19 改回「估算＋校正倍數」。
- 為什麼：Google 官方只在 AI Studio 帳單頁顯示餘額；Cloud Billing 匯出 BigQuery 只有依專案／SKU，沒有 Key。已知少算原因：行動秘書 OCR 只回報 candidatesTokenCount（不含思考 tokens）、失敗／重試呼叫不回報、逾時中斷可能已計費沒回報。
- 之後怎麼做：畫面一律標「估算」；Gemini 依系統花費只有選整月才算，其他區間顯示「—」；靠每月手動填 Credit balance 校正。每日金額上限用的估計花費約只有實際帳單 1/10，不能當真。
