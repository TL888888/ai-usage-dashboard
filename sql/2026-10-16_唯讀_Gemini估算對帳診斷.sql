-- ══════════════════════════════════════════════════════════════════════
-- 【AI用量統計】唯讀診斷：為什麼系統估算（約 US$0.13）跟 AI Studio 帳單（$48.02）差很多（2026-10-16）
-- 貼到 Supabase 專案：TL_projects（bvuygyajzupeqpqfwmgi）→ SQL Editor → 整份貼上 → Run
-- 只有 SELECT，不會改任何資料。結果只會顯示最後一段；三段可以分開各跑一次（選取一段再按 Run）。
-- 官方單價（2026-10 查 ai.google.dev/gemini-api/docs/pricing，付費層，每百萬 tokens）：
--   gemini-2.5-flash       輸入 $0.30、輸出 $2.50（輸出含思考 tokens）
--   gemini-2.5-flash-lite  輸入 $0.10、輸出 $0.40
-- ══════════════════════════════════════════════════════════════════════

-- ① Edge Function 實際用的單價（反推）：依模型，把系統記的花費和「照官方單價重算」放在一起比
select coalesce(ai_model, '(未記錄)') as 模型,
       count(*) as 次數,
       sum(prompt_tokens) as 輸入tokens,
       sum(completion_tokens) as 輸出tokens,
       round(sum(estimated_cost_usd)::numeric, 4) as 系統記的花費USD,
       round(sum(estimated_cost_usd) / nullif(sum(prompt_tokens + completion_tokens), 0) * 1e6, 4) as 系統平均每百萬tokens單價,
       round((sum(prompt_tokens) * 0.30 + sum(completion_tokens) * 2.50)::numeric / 1e6, 4) as 照25flash官方價重算USD
from ai_usage_events
where created_at >= '2026-09-19' and public.ai_norm_provider(ai_provider, api_key_name) = 'gemini'
group by 1
order by 次數 desc;

-- ② 10/1 起每天、每個系統的用量（台灣時間），用來對照 AI Studio 長條圖 10/8、10/15～16 的高峰
select (created_at at time zone 'Asia/Taipei')::date as 日期,
       system_name as 系統,
       upper(api_key_name) as key,
       count(*) as 次數,
       sum(prompt_tokens) as 輸入tokens,
       sum(completion_tokens) as 輸出tokens,
       max(prompt_tokens) as 單次最大輸入tokens,
       round(sum(estimated_cost_usd)::numeric, 4) as 系統記的花費USD
from ai_usage_events
where created_at >= '2026-09-30 16:00:00+00' and public.ai_norm_provider(ai_provider, api_key_name) = 'gemini'
group by 1, 2, 3
order by 1, 輸入tokens desc;

-- ③ 依 Key 合計（9/19 起，對應 AI Studio「Sep 19 – Oct 16」區間），可以跟 AI Studio 篩選單一 Key 的花費對照
select upper(api_key_name) as key,
       count(*) as 次數,
       sum(prompt_tokens) as 輸入tokens,
       sum(completion_tokens) as 輸出tokens,
       round(sum(estimated_cost_usd)::numeric, 4) as 系統記的花費USD,
       round((sum(prompt_tokens) * 0.30 + sum(completion_tokens) * 2.50)::numeric / 1e6, 4) as 照25flash官方價重算USD,
       max(created_at) as 最近一次
from ai_usage_events
where created_at >= '2026-09-18 16:00:00+00' and public.ai_norm_provider(ai_provider, api_key_name) = 'gemini'
group by 1
order by 輸入tokens desc;
