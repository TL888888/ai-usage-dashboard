-- ══════════════════════════════════════════════════════════════════════
-- 【AI用量統計】Gemini 每日估算花費／餘額 + 每月實際帳單校正倍數（2026-10-19 第二份）
-- 貼到 Supabase 專案：TL_projects（bvuygyajzupeqpqfwmgi）→ SQL Editor → 整份貼上 → Run
-- 前提：已貼過 2026-10-16b_實際花費與每日餘額.sql、2026-10-19_人資權限登入_權限改版.sql。可以重複執行，不會刪資料。
--
-- Michelle 2026-10-19 決定（取代 10-16「完全不用 tokens 推算」的做法）：
--   Google 沒有任何方式能自動抓 Gemini 餘額，所以 Gemini 改用「tokens × 官方單價 × 匯率 × 校正倍數」估算每日花費，
--   從儲值金額往下扣；每月填一次 Gemini 實際帳單總額，系統用「實際 ÷ 估算」算出校正倍數，估算會越來越接近帳單。
--   DeepInfra 不變（每天自動抓實際餘額）。
--
-- 校正倍數怎麼套用：
--   - 有填實際帳單的月份：用該月自己的倍數（所以該月估算加總＝實際帳單）
--   - 還沒填的月份（例如本月）：用「最近一個有填帳單的月份」的倍數
--   - 一個月都還沒填：倍數＝1（純粹照官方單價）
-- 每月實際帳單存在 ai_monthly_spend（provider='gemini'、key_name='__TOTAL__'），金額用台幣（AI Studio 帳單幣別）。
-- ══════════════════════════════════════════════════════════════════════


-- ---------- 1. 官方單價（美金／每百萬 tokens），依模型名稱開頭比對，取最長的那個 ----------
create table if not exists public.ai_model_prices (
  provider          text    not null,
  model_prefix      text    not null,      -- '' 代表這家供應商沒對到任何模型時的預設單價
  input_per_m_usd   numeric not null,
  output_per_m_usd  numeric not null,      -- Gemini 2.5 的輸出單價包含思考 tokens
  note              text,
  primary key (provider, model_prefix)
);
insert into public.ai_model_prices (provider, model_prefix, input_per_m_usd, output_per_m_usd, note) values
  ('gemini', 'gemini-2.5-flash-lite', 0.10, 0.40, '2026-10 ai.google.dev/gemini-api/docs/pricing 付費層'),
  ('gemini', 'gemini-2.5-flash',      0.30, 2.50, '2026-10 ai.google.dev/gemini-api/docs/pricing 付費層'),
  ('gemini', '',                      0.30, 2.50, '沒記錄模型或對不到時，先當 2.5 Flash')
on conflict (provider, model_prefix) do nothing;
-- 官方調價時改這裡，例如：update public.ai_model_prices set output_per_m_usd = 3.00 where provider='gemini' and model_prefix='gemini-2.5-flash';

alter table public.ai_model_prices enable row level security;
drop policy if exists ai_model_prices_read on public.ai_model_prices;
create policy ai_model_prices_read on public.ai_model_prices for select to authenticated using (public.ai_dash_can_read());
grant select on public.ai_model_prices to authenticated;


-- ---------- 2. 匯率：美金 → 供應商記帳幣別（Gemini 帳單是台幣） ----------
alter table public.ai_provider_settings add column if not exists usd_to_currency numeric not null default 1;
update public.ai_provider_settings set usd_to_currency = 32 where provider = 'gemini' and usd_to_currency = 1;
-- 匯率要改時：update public.ai_provider_settings set usd_to_currency = 31.5 where provider = 'gemini';


-- ---------- 3. 一筆用量照官方單價算多少錢（供應商幣別，未乘校正倍數） ----------
create or replace function public.ai_list_cost(p_provider text, p_model text, p_prompt bigint, p_completion bigint)
returns numeric language sql stable security invoker set search_path = public as $$
  select (coalesce(p_prompt, 0) * pr.input_per_m_usd + coalesce(p_completion, 0) * pr.output_per_m_usd) / 1e6
         * coalesce((select usd_to_currency from public.ai_provider_settings s where s.provider = p_provider), 1)
  from public.ai_model_prices pr
  where pr.provider = p_provider and lower(coalesce(p_model, '')) like pr.model_prefix || '%'
  order by length(pr.model_prefix) desc
  limit 1
$$;


-- ---------- 4. 每月：官方單價估算 vs 實際帳單 → 校正倍數 ----------
-- 回傳每個月一列：月份、估算（未校正）、實際帳單、該月倍數、實際套用的倍數
create or replace function public.ai_gemini_month_factors()
returns table (month date, raw_estimate numeric, actual numeric, own_factor numeric, applied_factor numeric, factor_from date)
language sql stable security invoker set search_path = public as $$
  with months as (
    select date_trunc('month', (e.created_at at time zone 'Asia/Taipei'))::date as month,
           sum(public.ai_list_cost('gemini', e.ai_model, e.prompt_tokens, e.completion_tokens)) as raw_estimate
    from public.ai_usage_events e
    where public.ai_norm_provider(e.ai_provider, e.api_key_name) = 'gemini'
    group by 1
  ),
  bills as (
    select m.month::date as month, m.amount as actual from public.ai_monthly_spend m
    where m.provider = 'gemini' and m.key_name = '__TOTAL__'
  ),
  allm as (
    select coalesce(mo.month, b.month) as month, coalesce(mo.raw_estimate, 0) as raw_estimate, b.actual,
           case when b.actual is not null and coalesce(mo.raw_estimate, 0) > 0 then b.actual / mo.raw_estimate end as own_factor
    from months mo full join bills b on b.month = mo.month
  )
  select a.month, a.raw_estimate, a.actual, a.own_factor,
         coalesce(a.own_factor,
                  (select x.own_factor from allm x where x.own_factor is not null and x.month < a.month order by x.month desc limit 1),
                  (select x.own_factor from allm x where x.own_factor is not null order by x.month desc limit 1),
                  1) as applied_factor,
         case when a.own_factor is not null then a.month
              else coalesce((select x.month from allm x where x.own_factor is not null and x.month < a.month order by x.month desc limit 1),
                            (select x.month from allm x where x.own_factor is not null order by x.month desc limit 1)) end as factor_from
  from allm a
  order by a.month
$$;


-- ---------- 5. Gemini 每日估算花費與估算餘額 ----------
-- 餘額：有手動填過實際餘額 → 從最近一次實際餘額往下扣；還沒填過 → 從儲值金額往下扣。日期以台灣時間為準。
create or replace function public.ai_gemini_daily(p_start date, p_end date)
returns table (day date, est_spend numeric, topup numeric, balance numeric, balance_is_actual boolean, applied_factor numeric)
language sql stable security invoker set search_path = public as $$
  with first_day as (
    select least(coalesce((select min(topup_date) from public.ai_credit_topups where provider = 'gemini'), p_start), p_start) as d
  ),
  days as (
    select g::date as day from first_day, generate_series(first_day.d, p_end, interval '1 day') g
  ),
  raw as (
    select (e.created_at at time zone 'Asia/Taipei')::date as day,
           sum(public.ai_list_cost('gemini', e.ai_model, e.prompt_tokens, e.completion_tokens)) as raw_cost
    from public.ai_usage_events e, first_day
    where public.ai_norm_provider(e.ai_provider, e.api_key_name) = 'gemini'
      and e.created_at >= first_day.d::timestamp at time zone 'Asia/Taipei'
      and e.created_at <  (p_end + 1)::timestamp at time zone 'Asia/Taipei'
    group by 1
  ),
  f as (select month, applied_factor from public.ai_gemini_month_factors()),
  latest_factor as (select coalesce((select applied_factor from f order by month desc limit 1), 1) as v),
  tops as (
    select topup_date as day, sum(amount) as amount from public.ai_credit_topups
    where provider = 'gemini' and currency = (select currency from public.ai_provider_settings where provider = 'gemini')
    group by 1
  ),
  snaps as (
    select distinct on ((taken_at at time zone 'Asia/Taipei')::date) (taken_at at time zone 'Asia/Taipei')::date as day, balance
    from public.ai_balance_snapshots where provider = 'gemini'
    order by (taken_at at time zone 'Asia/Taipei')::date, taken_at desc
  ),
  joined as (
    select d.day,
           coalesce(r.raw_cost, 0) * coalesce(f.applied_factor, (select v from latest_factor)) as est_spend,
           coalesce(f.applied_factor, (select v from latest_factor)) as applied_factor,
           coalesce(t.amount, 0) as topup,
           s.balance as snap
    from days d
    left join raw r on r.day = d.day
    left join f on f.month = date_trunc('month', d.day)::date
    left join tops t on t.day = d.day
    left join snaps s on s.day = d.day
  ),
  grp as (
    select j.*, count(j.snap) over (order by j.day) as g from joined j
  ),
  bal as (
    select grp.*,
           coalesce(max(snap) over (partition by g), 0)
           + sum(case when snap is null then topup - est_spend else 0 end) over (partition by g order by day) as balance
    from grp
  )
  select day, round(est_spend, 2), topup, round(balance, 2), snap is not null, round(applied_factor, 3)
  from bal
  where day >= p_start
  order by day
$$;


-- ---------- 6. Gemini 各系統估算花費（任意日期區間；每筆用該月套用的倍數） ----------
create or replace function public.ai_gemini_by_system(p_start timestamptz, p_end timestamptz)
returns table (system_name text, est_spend numeric)
language sql stable security invoker set search_path = public as $$
  with f as (select month, applied_factor from public.ai_gemini_month_factors())
  select coalesce(e.system_name, '(未知)'),
         round(sum(public.ai_list_cost('gemini', e.ai_model, e.prompt_tokens, e.completion_tokens)
                   * coalesce(f.applied_factor, (select applied_factor from f order by month desc limit 1), 1)), 2)
  from public.ai_usage_events e
  left join f on f.month = date_trunc('month', (e.created_at at time zone 'Asia/Taipei'))::date
  where public.ai_norm_provider(e.ai_provider, e.api_key_name) = 'gemini'
    and (p_start is null or e.created_at >= p_start)
    and (p_end is null or e.created_at < p_end)
  group by 1
$$;


-- ---------- 權限 ----------
revoke all on function public.ai_list_cost(text, text, bigint, bigint) from public, anon;
revoke all on function public.ai_gemini_month_factors() from public, anon;
revoke all on function public.ai_gemini_daily(date, date) from public, anon;
revoke all on function public.ai_gemini_by_system(timestamptz, timestamptz) from public, anon;
grant execute on function public.ai_list_cost(text, text, bigint, bigint) to authenticated;
grant execute on function public.ai_gemini_month_factors() to authenticated;
grant execute on function public.ai_gemini_daily(date, date) to authenticated;
grant execute on function public.ai_gemini_by_system(timestamptz, timestamptz) to authenticated;

-- 確認：應該看到每個月的估算（官方單價），還沒填帳單的月份倍數是 1
select * from public.ai_gemini_month_factors();
