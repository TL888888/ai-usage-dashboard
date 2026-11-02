-- ══════════════════════════════════════════════════════════════════════
-- 【AI用量統計】唯讀：「集團各公司統計」畫面上的「資材部」從哪裡來（2026-11-02）
-- 貼到 Supabase 專案：TL_projects → https://supabase.com/dashboard/project/bvuygyajzupeqpqfwmgi/sql/new
-- 只有 SELECT，不會改任何資料。結果請整張截圖（或匯出 CSV）。
--
-- 「集團各公司統計」的部門有兩個來源：
--   A. 各部門每月填的 Excel 月報表（匯入到 manual_ai_usage_monthly），部門名稱照 Excel 上填的
--   B. 公司自建 AI 系統的用量，依提問人 email 到對照表 org_directory 查部門
-- 這份把兩個來源裡含「資材」的資料都列出來（同時找繁體「資材」與簡體「资材」）。
-- ══════════════════════════════════════════════════════════════════════

-- 專案檢查：貼錯專案就立刻停下，什麼都不改
do $$ begin if to_regclass('public.ai_usage_events') is null then raise exception '貼錯專案！這段要貼到 TL_projects，請換專案重貼（什麼都沒改到）'; end if; end $$;

select '來源A：Excel 月報表' as 來源,
       to_char(m.report_month, 'YYYY-MM') as 月份,
       m.company as 公司,
       m.department as 部門,
       count(*) as 筆數或人次,
       string_agg(distinct coalesce(m.person_name, ''), '、') as 人員或email,
       sum(coalesce(m.token_amount, 0)) as tokens
from public.manual_ai_usage_monthly m
where m.department like '%資材%' or m.department like '%资材%'
group by 1, 2, 3, 4

union all

select '來源B：自建系統（對照表 org_directory）',
       to_char((e.created_at at time zone 'Asia/Taipei'), 'YYYY-MM'),
       o.company,
       o.department,
       count(*),
       string_agg(distinct lower(e.asker_email), '、'),
       sum(coalesce(e.total_tokens, 0))
from public.org_directory o
join public.ai_usage_events e on lower(trim(e.asker_email)) = lower(o.email)
where o.department like '%資材%' or o.department like '%资材%'
group by 1, 2, 3, 4

order by 1, 2, 3;
