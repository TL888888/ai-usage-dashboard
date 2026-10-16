-- ══════════════════════════════════════════════════════════════════════
-- 【AI用量統計】費用改看「供應商實際數字」：每日餘額、每月依 Key 實際花費（2026-10-16 第二份）
-- 貼到 Supabase 專案：TL_projects（bvuygyajzupeqpqfwmgi）→ SQL Editor → 整份貼上 → Run
-- 前提：要先貼過 sql/2026-10-16_依Key統計與儲值提醒.sql（這份會用到裡面的 ai_norm_provider、ai_dash_is_admin、ai_credit_topups）。
-- 可以重複執行，不會刪掉任何資料。
--
-- Michelle 2026-10-16 決定的原則：tokens 照我們自己的紀錄；費用一律用供應商的實際數字，不再用 tokens 推算。
--
-- 這份做了什麼：
--   1. ai_provider_settings  ：每家供應商用什麼幣別記帳（Gemini＝台幣、DeepInfra＝美金）
--   2. ai_balance_snapshots  ：實際餘額紀錄。DeepInfra 由網站每天自動抓（source='api'）；Gemini 由人到 AI Studio 看了手動填（source='manual'）
--   3. ai_monthly_spend      ：每月實際花費。Gemini 每月到 AI Studio 依 Key 抄（manual）；DeepInfra 由網站自動抓月總計（api）
--                             key_name 存「Key 名稱去掉前綴後的部分」，例：GEMINI_API_KEY_SECRETARY → SECRETARY；'__TOTAL__' 代表不篩選 Key 的總計
--   4. 寫入兩筆儲值：DeepInfra 2026-08-27 US$20、Gemini 2026-09-18 NT$1,000（Michelle 口述）
--   5. ai_daily_balance()    ：每日餘額表（表二）
--   6. ai_latest_balance()   ：每家供應商最新的實際餘額與已用比例（70% 紅色提醒、30 天沒對帳黃色提醒用）
--   7. ai_usage_summary()    ：多一組「依系統 × 供應商」的 tokens（表一用）
--   舊的 ai_billing_checks（第一份 SQL 建的對帳表）裡已經填的資料，會搬進 ai_balance_snapshots；ai_credit_status() 不再使用，但先保留不刪。
-- ══════════════════════════════════════════════════════════════════════


-- ---------- 1. 供應商幣別 ----------
create table if not exists public.ai_provider_settings (
  provider  text primary key,
  currency  text not null check (currency in ('USD', 'TWD')),
  label     text not null
);
insert into public.ai_provider_settings (provider, currency, label) values
  ('gemini', 'TWD', 'Gemini（Google）'),
  ('deepinfra', 'USD', 'DeepInfra')
on conflict (provider) do nothing;
-- 如果之後確認 AI Studio 帳單其實是美金，執行：update public.ai_provider_settings set currency = 'USD' where provider = 'gemini';


-- ---------- 2. 實際餘額紀錄 ----------
create table if not exists public.ai_balance_snapshots (
  id          bigserial primary key,
  provider    text        not null references public.ai_provider_settings(provider),
  taken_at    timestamptz not null default now(),   -- 這個餘額是「什麼時間點」的
  balance     numeric     not null,                 -- 供應商幣別（見 ai_provider_settings）；負數代表欠款
  source      text        not null check (source in ('api', 'manual')),
  raw_value   numeric,                              -- DeepInfra API 回傳的原始數字（stripe_balance），單位如果判斷錯可以用它重算
  note        text,
  created_by  text,
  created_at  timestamptz not null default now()
);
create index if not exists ai_balance_snapshots_provider_taken_idx on public.ai_balance_snapshots (provider, taken_at desc);


-- ---------- 3. 每月實際花費 ----------
create table if not exists public.ai_monthly_spend (
  id          bigserial primary key,
  provider    text        not null references public.ai_provider_settings(provider),
  month       date        not null check (extract(day from month) = 1),  -- 該月 1 日
  key_name    text        not null,                 -- Key 名稱去掉前綴（SECRETARY / SHIPPING …），或 '__TOTAL__'
  amount      numeric     not null check (amount >= 0),                  -- 供應商幣別
  source      text        not null default 'manual' check (source in ('api', 'manual')),
  note        text,
  created_by  text,
  updated_at  timestamptz not null default now(),
  unique (provider, month, key_name)
);


-- ---------- RLS：只有 dashboard_admins 名單上的人能讀寫（網站的自動抓取用 service_role，不受 RLS 限制） ----------
alter table public.ai_provider_settings enable row level security;
alter table public.ai_balance_snapshots enable row level security;
alter table public.ai_monthly_spend     enable row level security;

drop policy if exists ai_provider_settings_admin_read on public.ai_provider_settings;
create policy ai_provider_settings_admin_read on public.ai_provider_settings
  for select to authenticated using (public.ai_dash_is_admin());

drop policy if exists ai_balance_snapshots_admin_all on public.ai_balance_snapshots;
create policy ai_balance_snapshots_admin_all on public.ai_balance_snapshots
  for all to authenticated using (public.ai_dash_is_admin()) with check (public.ai_dash_is_admin());

drop policy if exists ai_monthly_spend_admin_all on public.ai_monthly_spend;
create policy ai_monthly_spend_admin_all on public.ai_monthly_spend
  for all to authenticated using (public.ai_dash_is_admin()) with check (public.ai_dash_is_admin());


-- ---------- 儲值表調整 + 寫入兩筆儲值 ----------
-- 儲值金額一律用供應商幣別記（Gemini 台幣、DeepInfra 美金），換算美金欄位改成可以不填
alter table public.ai_credit_topups alter column amount_usd drop not null;

insert into public.ai_credit_topups (provider, topup_date, amount, currency, twd_per_usd, amount_usd, note, created_by)
select 'deepinfra', date '2026-08-27', 20, 'USD', null, 20, 'Michelle 2026-10-16 口述', 'SQL 匯入'
where not exists (select 1 from public.ai_credit_topups where provider = 'deepinfra' and topup_date = date '2026-08-27');

insert into public.ai_credit_topups (provider, topup_date, amount, currency, twd_per_usd, amount_usd, note, created_by)
select 'gemini', date '2026-09-18', 1000, 'TWD', null, null, 'Michelle 2026-10-16 口述', 'SQL 匯入'
where not exists (select 1 from public.ai_credit_topups where provider = 'gemini' and topup_date = date '2026-09-18');

-- 舊對帳表的資料搬過來（幣別和供應商幣別一樣的才搬；對帳日當天 23:59:59 台灣時間）
insert into public.ai_balance_snapshots (provider, taken_at, balance, source, note, created_by)
select c.provider, ((c.checked_on + 1)::timestamp - interval '1 second') at time zone 'Asia/Taipei',
       c.balance_amount, 'manual', coalesce(c.note || ' ', '') || '[從 ai_billing_checks#' || c.id || ' 搬入]', c.created_by
from public.ai_billing_checks c
join public.ai_provider_settings s on s.provider = c.provider and s.currency = c.currency
where not exists (select 1 from public.ai_balance_snapshots b where b.note like '%[從 ai_billing_checks#' || c.id || ' 搬入]%');


-- ---------- 5. 每日餘額（表二） ----------
-- 每一天、每家供應商一列：
--   topup   ：當天儲值金額
--   balance ：當天最後一筆「實際餘額紀錄」（沒有紀錄就是 null，畫面顯示「—」，不用估算去補）
--   spend   ：當天實際花費＝前一天餘額＋當天儲值−當天餘額（前一天或當天沒有紀錄就是 null）
-- 日期以台灣時間為準；最多 400 天。
create or replace function public.ai_daily_balance(p_start date, p_end date)
returns table (day date, provider text, currency text, topup numeric, balance numeric, balance_source text, balance_at timestamptz, spend numeric)
language sql
stable
security invoker
set search_path = public
as $$
  with days as (
    select d::date as day
    from generate_series(p_start - 1, least(p_end, p_start + 400), interval '1 day') d
  ),
  grid as (
    select days.day, s.provider, s.currency from days cross join public.ai_provider_settings s
  ),
  snap as (
    select distinct on (b.provider, (b.taken_at at time zone 'Asia/Taipei')::date)
           b.provider, (b.taken_at at time zone 'Asia/Taipei')::date as day, b.balance, b.source, b.taken_at
    from public.ai_balance_snapshots b
    where b.taken_at >= (p_start - 1)::timestamp at time zone 'Asia/Taipei'
      and b.taken_at <  (p_end + 1)::timestamp at time zone 'Asia/Taipei'
    order by b.provider, (b.taken_at at time zone 'Asia/Taipei')::date, b.taken_at desc
  ),
  tops as (
    select t.provider, t.topup_date as day, sum(t.amount) as amount
    from public.ai_credit_topups t
    join public.ai_provider_settings s on s.provider = t.provider and s.currency = t.currency
    group by 1, 2
  ),
  joined as (
    select g.day, g.provider, g.currency, coalesce(tp.amount, 0) as topup,
           sn.balance, sn.source as balance_source, sn.taken_at as balance_at,
           lag(sn.balance) over (partition by g.provider order by g.day) as prev_balance
    from grid g
    left join snap sn on sn.provider = g.provider and sn.day = g.day
    left join tops tp on tp.provider = g.provider and tp.day = g.day
  )
  select day, provider, currency, topup, balance, balance_source, balance_at,
         case when balance is not null and prev_balance is not null then prev_balance + topup - balance end as spend
  from joined
  where day >= p_start
  order by day, provider
$$;


-- ---------- 6. 最新實際餘額（提醒用） ----------
-- 剩餘＝最近一次實際餘額＋那之後的儲值；已用%＝(全部儲值−剩餘)÷全部儲值
create or replace function public.ai_latest_balance()
returns json
language sql
stable
security invoker
set search_path = public
as $$
  with s as (select * from public.ai_provider_settings),
  tops as (
    select t.provider, sum(t.amount) as total, min(t.topup_date) as first_date, max(t.topup_date) as last_date
    from public.ai_credit_topups t join s on s.provider = t.provider and s.currency = t.currency
    group by 1
  ),
  last_snap as (
    select distinct on (provider) provider, balance, taken_at, source
    from public.ai_balance_snapshots order by provider, taken_at desc, id desc
  ),
  calc as (
    select s.provider, s.currency, s.label,
           coalesce(tops.total, 0) as total_topup, tops.first_date, tops.last_date,
           ls.balance as snap_balance, ls.taken_at as snap_at, ls.source as snap_source,
           (select coalesce(sum(t.amount), 0) from public.ai_credit_topups t
             where t.provider = s.provider and t.currency = s.currency and ls.taken_at is not null
               and t.topup_date > (ls.taken_at at time zone 'Asia/Taipei')::date) as topup_after_snap
    from s
    left join tops on tops.provider = s.provider
    left join last_snap ls on ls.provider = s.provider
  )
  select coalesce(json_agg(json_build_object(
           'provider', provider, 'currency', currency, 'label', label,
           'total_topup', total_topup, 'first_topup_date', first_date, 'last_topup_date', last_date,
           'snap_balance', snap_balance, 'snap_at', snap_at, 'snap_source', snap_source,
           'remaining', case when snap_balance is not null then snap_balance + topup_after_snap end,
           'used_pct', case when snap_balance is not null and total_topup > 0
                            then round(((total_topup - (snap_balance + topup_after_snap)) / total_topup * 100)::numeric, 1) end,
           'days_since_snap', case when snap_at is not null then extract(epoch from (now() - snap_at)) / 86400 end
         ) order by provider), '[]'::json)
  from calc
$$;


-- ---------- 7. ai_usage_summary 加上「依系統 × 供應商」 ----------
create or replace function public.ai_usage_summary(p_start timestamptz default null, p_end timestamptz default null)
returns json
language sql
stable
security invoker
set search_path = public
as $$
  with ev as (
    select e.*,
           public.ai_norm_provider(e.ai_provider, e.api_key_name) as prov,
           nullif(upper(trim(coalesce(e.api_key_name, ''))), '') as keyn
    from public.ai_usage_events e
    where (p_start is null or e.created_at >= p_start)
      and (p_end   is null or e.created_at <  p_end)
  )
  select json_build_object(
    'totals', (
      select json_build_object(
        'count', count(*),
        'tokens', coalesce(sum(total_tokens), 0),
        'cost', coalesce(sum(estimated_cost_usd), 0),
        'cache_hits', count(*) filter (where cache_hit)
      ) from ev
    ),
    'by_system', (
      select coalesce(json_agg(t order by t.tokens desc), '[]'::json) from (
        select coalesce(system_name, '(未知)') as system_name,
               count(*) as cnt,
               coalesce(sum(total_tokens), 0) as tokens,
               coalesce(sum(estimated_cost_usd), 0) as cost,
               count(*) filter (where cache_hit) as cache_hits
        from ev group by 1
      ) t
    ),
    'by_asker', (
      select coalesce(json_agg(t order by t.tokens desc), '[]'::json) from (
        select coalesce(nullif(lower(trim(asker_email)), ''), '(未記錄)') as asker_email,
               count(*) as cnt,
               coalesce(sum(total_tokens), 0) as tokens,
               coalesce(sum(estimated_cost_usd), 0) as cost
        from ev group by 1
      ) t
    ),
    'by_key', (
      select coalesce(json_agg(t order by t.provider, t.tokens desc), '[]'::json) from (
        select prov as provider,
               coalesce(keyn, '(未記錄)') as key_name,
               array_agg(distinct coalesce(system_name, '(未知)')) as systems,
               array_remove(array_agg(distinct ai_model), null) as models,
               count(*) as cnt,
               coalesce(sum(total_tokens), 0) as tokens,
               coalesce(sum(estimated_cost_usd), 0) as cost,
               max(created_at) as last_used
        from ev group by 1, 2
      ) t
    ),
    'by_system_provider', (
      select coalesce(json_agg(t), '[]'::json) from (
        select coalesce(system_name, '(未知)') as system_name, prov as provider,
               count(*) as cnt, coalesce(sum(total_tokens), 0) as tokens
        from ev group by 1, 2
      ) t
    )
  )
$$;


-- ---------- 權限 ----------
revoke all on function public.ai_daily_balance(date, date) from public, anon;
revoke all on function public.ai_latest_balance() from public, anon;
revoke all on function public.ai_usage_summary(timestamptz, timestamptz) from public, anon;
grant execute on function public.ai_daily_balance(date, date) to authenticated;
grant execute on function public.ai_latest_balance() to authenticated;
grant execute on function public.ai_usage_summary(timestamptz, timestamptz) to authenticated;
grant select on public.ai_provider_settings to authenticated;
grant select, insert, update, delete on public.ai_balance_snapshots, public.ai_monthly_spend to authenticated;
grant usage, select on sequence public.ai_balance_snapshots_id_seq, public.ai_monthly_spend_id_seq to authenticated;
