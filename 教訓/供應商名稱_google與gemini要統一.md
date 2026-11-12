# 供應商與 Key 名稱統一
- ai_norm_provider：ai_provider 的 google 和 gemini 都算 Gemini（行動秘書 OCR 寫 google，其他寫 gemini）；舊資料沒 ai_provider 就看 Key 開頭（GEMINI_／DEEPINFRA_）。
- Key 名稱轉大寫再分組；比對去前綴 GEMINI_API_KEY_／AI_API_KEY_／DEEPINFRA_API_KEY_（AI_API_KEY_MARKET 與 AI Studio 的 GEMINI_API_KEY_MARKET 都當 MARKET）。有些系統 Key 叫 AI_API_KEY_XXX（看不出供應商）→ 以 ai_provider 欄位為準。
- 系統名稱＝首頁卡片名稱（SYSTEM_LABELS，index.html）；任何系統改名這裡要跟著改。光電／PCB 共用 system_name=market 分不開。
