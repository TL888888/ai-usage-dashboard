-- ══════════════════════════════════════════════════════════════════════
-- 【AI用量統計】唯讀：查目前各資料表的權限規則（RLS），規劃「改用人資權限免密碼登入」用（2026-10-17）
-- 貼到 Supabase 專案：TL_projects（bvuygyajzupeqpqfwmgi）→ SQL Editor → 整份貼上 → Run → 結果截圖
-- 只有 SELECT，不會改任何資料。
-- ══════════════════════════════════════════════════════════════════════
select c.relname as 資料表,
       c.relrowsecurity as 有開RLS,
       p.polname as 規則名稱,
       case p.polcmd when 'r' then 'SELECT' when 'a' then 'INSERT' when 'w' then 'UPDATE' when 'd' then 'DELETE' else 'ALL' end as 動作,
       pg_get_expr(p.polqual, p.polrelid) as 可讀條件,
       pg_get_expr(p.polwithcheck, p.polrelid) as 可寫條件
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
left join pg_policy p on p.polrelid = c.oid
where c.relname in ('ai_usage_events', 'manual_ai_usage_monthly', 'org_directory', 'dashboard_admins',
                    'ai_credit_topups', 'ai_billing_checks', 'ai_balance_snapshots', 'ai_monthly_spend', 'ai_provider_settings')
order by 1, 3;
