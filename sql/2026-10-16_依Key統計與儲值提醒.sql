-- ══════════════════════════════════════════════════════════════════════
-- 【AI用量統計】依 API Key 統計 + 儲值紀錄 + 餘額提醒（2026-10-16）
-- 貼到 Supabase 專案：TL_projects（bvuygyajzupeqpqfwmgi）→ SQL Editor → 整份貼上 → Run
-- 可以重複執行（都用 create or replace / if not exists），不會刪掉任何既有資料。
--
-- 這份做了什麼：
--   1. ai_norm_provider()   ：把供應商名稱統一（google / gemini 都算 gemini；舊資料沒填供應商就看 Key 名稱猜）
--   2. ai_usage_summary()   ：「大量雲端系統統計」分頁的加總（總計 / 依系統 / 依提問人 / 依 API Key），在資料庫算好才送到網頁
--   3. ai_usage_by_email()  ：「集團各公司統計」分頁要用的「每個人每個系統用了多少 tokens」，也在資料庫先加總
--      → 這兩個取代網頁原本 limit(2000) / limit(5000) 把逐筆紀錄抓下來自己算的做法（超過筆數會默默少算）
--   4. ai_credit_topups     ：儲值紀錄（供應商、日期、金額、幣別、匯率、換算美金）
--   5. ai_billing_checks    ：對帳紀錄（到供應商帳單頁看到的「實際剩餘餘額」，用來校正系統估算）
--   6. ai_credit_status()   ：依供應商算 已儲值 → 估計已用 → 剩餘 → 已用百分比
--
-- 權限：函式都是 security invoker（用「登入者自己的權限」去讀 ai_usage_events），
--       所以 ai_usage_events 原本的 RLS 規則照樣有效，看不到資料的人透過函式也看不到。
--       儲值 / 對帳兩張表只有 dashboard_admins 名單上的人能讀寫。
-- ══════════════════════════════════════════════════════════════════════


-- ---------- 1. 供應商名稱統一 ----------
-- ai_provider 歷史上有 'google' 和 'gemini' 兩種寫法（行動秘書 OCR 寫 google，其他寫 gemini），都是同一家。
-- 很早期的紀錄可能沒有 ai_provider，就從 Key 名稱開頭判斷（GEMINI_ / DEEPINFRA_）。
create or replace function public.ai_norm_provider(p_provider text, p_key text)
returns text
language sql
immutable
as $$
  select case
    when lower(trim(coalesce(p_provider, ''))) in ('google', 'gemini') then 'gemini'
    when lower(trim(coalesce(p_provider, ''))) <> '' then lower(trim(p_provider))
    when upper(coalesce(p_key, '')) like 'GEMINI%' then 'gemini'
    when upper(coalesce(p_key, '')) like 'DEEPINFRA%' then 'deepinfra'
    else 'unknown'
  end
$$;


-- ---------- 2. 「大量雲端系統統計」分頁的全部加總 ----------
-- p_start / p_end 可以是 null（代表不限）；p_end 不含。
-- api_key_name 一律轉大寫再分組（例：DEEPINFRA_API_KEY_Shipping 和 DEEPINFRA_API_KEY_SHIPPING 算同一把）。
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
    )
  )
$$;


-- ---------- 3. 「集團各公司統計」分頁：每個人 × 每個系統 的 tokens ----------
create or replace function public.ai_usage_by_email(p_start timestamptz, p_end timestamptz)
returns table (asker_email text, system_name text, total_tokens bigint)
language sql
stable
security invoker
set search_path = public
as $$
  select nullif(lower(trim(e.asker_email)), '') as asker_email,
         e.system_name,
         coalesce(sum(e.total_tokens), 0)::bigint as total_tokens
  from public.ai_usage_events e
  where e.created_at >= p_start and e.created_at < p_end
  group by 1, 2
$$;


-- ---------- 管理員判斷（給下面兩張表的 RLS 用） ----------
-- security definer：直接查 dashboard_admins，避免 RLS 規則互相引用卡住。
create or replace function public.ai_dash_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.dashboard_admins a
    where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  )
$$;


-- ---------- 4. 儲值紀錄 ----------
create table if not exists public.ai_credit_topups (
  id           bigserial primary key,
  provider     text        not null,              -- 用 ai_norm_provider 統一後的名稱：gemini / deepinfra
  topup_date   date        not null,              -- 儲值日期（從這天開始算估計用量）
  amount       numeric     not null check (amount > 0),  -- 儲值金額（原幣）
  currency     text        not null default 'USD' check (currency in ('USD', 'TWD')),
  twd_per_usd  numeric,                           -- 幣別是 TWD 時填的匯率（1 美金 = 幾台幣）
  amount_usd   numeric     not null check (amount_usd > 0),  -- 換算成美金（網頁自動算好存進來）
  note         text,
  created_by   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ---------- 5. 對帳紀錄（依實際帳單校正） ----------
-- 到 Google AI Studio / DeepInfra 帳單頁看到「目前剩多少錢」就記一筆。
-- 有對帳紀錄之後，餘額改成：最近一次對帳的實際餘額 + 之後的儲值 − 之後的系統估算花費。
create table if not exists public.ai_billing_checks (
  id              bigserial primary key,
  provider        text        not null,
  checked_on      date        not null,           -- 對帳日期（帳單頁顯示的是這天結束時的餘額）
  balance_amount  numeric     not null check (balance_amount >= 0),
  currency        text        not null default 'USD' check (currency in ('USD', 'TWD')),
  twd_per_usd     numeric,
  balance_usd     numeric     not null check (balance_usd >= 0),
  note            text,
  created_by      text,
  created_at      timestamptz not null default now()
);

alter table public.ai_credit_topups  enable row level security;
alter table public.ai_billing_checks enable row level security;

drop policy if exists ai_credit_topups_admin_all on public.ai_credit_topups;
create policy ai_credit_topups_admin_all on public.ai_credit_topups
  for all to authenticated
  using (public.ai_dash_is_admin()) with check (public.ai_dash_is_admin());

drop policy if exists ai_billing_checks_admin_all on public.ai_billing_checks;
create policy ai_billing_checks_admin_all on public.ai_billing_checks
  for all to authenticated
  using (public.ai_dash_is_admin()) with check (public.ai_dash_is_admin());


-- ---------- 6. 依供應商算餘額 ----------
-- 用量起算日：沒有對帳紀錄 → 最早一筆儲值日；有對帳紀錄 → 最近一次對帳日的隔天。
-- 日期以台灣時間（Asia/Taipei）為準。
-- 注意：estimated_cost_usd 是 Edge Function「stats-ai-usage-push」用單價估算的，不是供應商帳單，會有落差。
create or replace function public.ai_credit_status()
returns json
language sql
stable
security invoker
set search_path = public
as $$
  with providers as (
    select distinct provider from public.ai_credit_topups
  ),
  last_check as (
    select distinct on (provider) provider, checked_on, balance_amount, currency, balance_usd
    from public.ai_billing_checks
    order by provider, checked_on desc, id desc
  ),
  calc as (
    select p.provider,
           (select coalesce(sum(amount_usd), 0) from public.ai_credit_topups t where t.provider = p.provider) as topup_usd,
           (select coalesce(sum(amount), 0)     from public.ai_credit_topups t where t.provider = p.provider) as topup_amount,
           (select case when count(distinct currency) = 1 then min(currency) end
              from public.ai_credit_topups t where t.provider = p.provider) as currency,
           (select min(topup_date) from public.ai_credit_topups t where t.provider = p.provider) as first_topup_date,
           c.checked_on, c.balance_usd as check_balance_usd,
           case when c.checked_on is null
                then (select min(topup_date) from public.ai_credit_topups t where t.provider = p.provider)::timestamp at time zone 'Asia/Taipei'
                else (c.checked_on + 1)::timestamp at time zone 'Asia/Taipei'
           end as since_ts
    from providers p
    left join last_check c on c.provider = p.provider
  ),
  calc2 as (
    select calc.*,
           (select coalesce(sum(e.estimated_cost_usd), 0) from public.ai_usage_events e
             where public.ai_norm_provider(e.ai_provider, e.api_key_name) = calc.provider
               and e.created_at >= calc.since_ts) as est_cost_since,
           (select coalesce(sum(t.amount_usd), 0) from public.ai_credit_topups t
             where t.provider = calc.provider and calc.checked_on is not null and t.topup_date > calc.checked_on) as topup_after_check_usd
    from calc
  ),
  calc3 as (
    select calc2.*,
           case when checked_on is null then topup_usd - est_cost_since
                else check_balance_usd + topup_after_check_usd - est_cost_since
           end as remaining_usd
    from calc2
  )
  select coalesce(json_agg(json_build_object(
           'provider', provider,
           'topup_usd', topup_usd,
           'topup_amount', topup_amount,
           'currency', currency,
           'first_topup_date', first_topup_date,
           'checked_on', checked_on,
           'check_balance_usd', check_balance_usd,
           'est_cost_since', est_cost_since,
           'since', since_ts,
           'remaining_usd', remaining_usd,
           'used_usd', topup_usd - remaining_usd,
           'used_pct', case when topup_usd > 0 then round(((topup_usd - remaining_usd) / topup_usd * 100)::numeric, 1) end
         ) order by provider), '[]'::json)
  from calc3
$$;


-- ---------- 權限：只有登入的人能呼叫 ----------
revoke all on function public.ai_usage_summary(timestamptz, timestamptz) from public, anon;
revoke all on function public.ai_usage_by_email(timestamptz, timestamptz) from public, anon;
revoke all on function public.ai_credit_status() from public, anon;
revoke all on function public.ai_dash_is_admin() from public, anon;
grant execute on function public.ai_usage_summary(timestamptz, timestamptz) to authenticated;
grant execute on function public.ai_usage_by_email(timestamptz, timestamptz) to authenticated;
grant execute on function public.ai_credit_status() to authenticated;
grant execute on function public.ai_dash_is_admin() to authenticated;
grant execute on function public.ai_norm_provider(text, text) to authenticated;
grant select, insert, update, delete on public.ai_credit_topups, public.ai_billing_checks to authenticated;
grant usage, select on sequence public.ai_credit_topups_id_seq, public.ai_billing_checks_id_seq to authenticated;
