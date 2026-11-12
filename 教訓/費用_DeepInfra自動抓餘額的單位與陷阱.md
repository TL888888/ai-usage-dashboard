# DeepInfra 自動抓餘額
- 單位是**美金**（stripe_balance=-19.93＝US$19.93，官方沒寫單位；DEEPINFRA_BALANCE_DIVISOR 不用設，原始數字存 raw_value 可重算）。
- /payment/usage 當月 invoice_id 是 "INVALID"（不是文件寫的 NOT_FINAL），已結算月份是 "in_..." 開頭。
- 排程：vercel.json UTC 15:00（台灣 23 點那一小時）；Vercel 免費方案只保證該小時內（曾落在 00:26）。DeepInfra 金鑰整帳戶共用，建議專用 DEEPINFRA_API_KEY_BILLING 不與 wechat 共用。
- 排程安全：有設 CRON_SECRET 就比對，沒設只認 Vercel 排程 user-agent。超過 3 天沒抓成功會黃色提醒（代表排程或金鑰壞了）。只有開始抓那天起才有每日數字。
- 提醒：DeepInfra 只給帳戶總額，只有一個系統在用時全算給它，多個系統顯示「—」。
