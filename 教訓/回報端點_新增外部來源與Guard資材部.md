# 外部程式回報用量（api/usage-report.js）
- 新增來源：SOURCES 加一筆＋Vercel 設密語環境變數＋index.html SYSTEM_LABELS。端點只寫一筆用量，system_name／provider 由伺服器固定；思考 tokens 併入 completion_tokens。密語只放 Vercel（及對方的指令碼屬性），由 Michelle 私下交付。
- Guard system（同事 janny0831 掛號包裹登記）：GUARD_REPORT_TOKEN；表格固定一列「等待回報」；同事說明 Projects\掛號包裹登記\給同事_AI用量回報.md（尚未轉交）。與同一張帳單，已被攤進校正倍數。
- 資材部 zicai_meeting／zicai_draw：ZICAI_MEETING_REPORT_TOKEN／ZICAI_DRAW_REPORT_TOKEN；沒有提問人 email；開發者說明在 雲端系統總管\查詢資材部Gemini用量回報_給開發者.md。
- 沒回報用量的呼叫：wechat api/ai-proxy.js（Cloudflare Worker／Groq）；card-note-repair.js 沒呼叫 AI。Edge Function stats-ai-usage-push 原始碼只在 Supabase，費用欄位是估算且畫面已不用。
