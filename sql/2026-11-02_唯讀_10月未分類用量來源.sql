-- ══════════════════════════════════════════════════════════════════════
-- 【AI用量統計】唯讀：2026 年 10 月「台灣大量／未分類（尚未建立對照）」那 1.4M tokens 是誰用的（2026-11-02）
-- 貼到 Supabase 專案：TL_projects → https://supabase.com/dashboard/project/bvuygyajzupeqpqfwmgi/sql/new
-- 只有 SELECT，不會改任何資料。結果請整張截圖（或匯出 CSV）。
--
-- 為什麼會「未分類」：「集團各公司統計」把公司自建 AI 系統的用量，依「提問人 email」去對照表 org_directory 找公司和部門；
-- 找不到 email（對照表沒這個人，或用量紀錄根本沒記 email）就一律算「台灣大量／未分類（尚未建立對照）」。
-- ══════════════════════════════════════════════════════════════════════

-- 專案檢查：貼錯專案就立刻停下，什麼都不改
do $$ begin if to_regclass('public.ai_usage_events') is null then raise exception '貼錯專案！這段要貼到 TL_projects，請換專案重貼（什麼都沒改到）'; end if; end $$;

-- 10 月（台灣時間）找不到對照的用量：依「提問人 × 系統 × Key」列出，tokens 多的在前
select coalesce(nullif(lower(trim(e.asker_email)), ''), '（沒有記錄 email）') as 提問人email,
       e.system_name as 系統,
       upper(e.api_key_name) as api_key,
       count(*) as 次數,
       sum(e.total_tokens) as tokens
from public.ai_usage_events e
left join public.org_directory o on lower(o.email) = lower(trim(e.asker_email))
where e.created_at >= '2026-09-30 16:00:00+00'   -- 台灣時間 10/1 00:00
  and e.created_at <  '2026-10-31 16:00:00+00'   -- 台灣時間 11/1 00:00
  and o.email is null
group by 1, 2, 3
order by tokens desc;
