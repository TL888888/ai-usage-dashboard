-- ══════════════════════════════════════════════════════════════════════
-- 【AI用量統計】唯讀：10 月「台灣大量」的營業部、資材部、企劃室從哪裡來（2026-11-02）
-- 貼到 Supabase 專案：TL_projects → https://supabase.com/dashboard/project/bvuygyajzupeqpqfwmgi/sql/new
-- 只有 SELECT，不會改任何資料。結果請整張截圖（或匯出 CSV）。
--
-- 「集團各公司統計」10 月的部門只可能來自兩個地方（程式只抓 10 月，不會帶入別的月份）：
--   A. 10 月的 Excel 月報表（manual_ai_usage_monthly，report_month = 2026-10-01）
--   B. 10 月公司自建 AI 系統的用量，提問人 email 在對照表 org_directory 找得到 → 用對照表的部門
-- ══════════════════════════════════════════════════════════════════════

-- 專案檢查：貼錯專案就立刻停下，什麼都不改
do $$ begin if to_regclass('public.ai_usage_events') is null then raise exception '貼錯專案！這段要貼到 TL_projects，請換專案重貼（什麼都沒改到）'; end if; end $$;

select '來源A：10 月 Excel 月報表' as 來源,
       m.company as 公司,
       m.department as 部門,
       string_agg(distinct coalesce(m.person_name, ''), '、') as 人員或email,
       '（Excel）' as 系統,
       count(*) as 筆數,
       sum(coalesce(m.token_amount, 0)) as tokens
from public.manual_ai_usage_monthly m
where m.report_month = date '2026-10-01'
group by 1, 2, 3

union all

select '來源B：自建系統（對照表找得到的人）',
       o.company,
       o.department,
       lower(e.asker_email),
       e.system_name,
       count(*),
       sum(coalesce(e.total_tokens, 0))
from public.ai_usage_events e
join public.org_directory o on lower(o.email) = lower(trim(e.asker_email))
where e.created_at >= '2026-09-30 16:00:00+00'   -- 台灣時間 10/1 00:00
  and e.created_at <  '2026-10-31 16:00:00+00'   -- 台灣時間 11/1 00:00
group by 1, 2, 3, 4, 5

order by 1, 7 desc;
