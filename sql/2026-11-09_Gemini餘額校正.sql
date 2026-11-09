-- ══════════════════════════════════════════════════════════════════════
-- 【AI用量統計】Gemini 校正倍數改用「相鄰兩次實際餘額」算（2026-11-09）
-- 貼到 Supabase 專案：TL_projects（bvuygyajzupeqpqfwmgi）→ SQL Editor → 整份貼上 → Run
-- 連結：https://supabase.com/dashboard/project/bvuygyajzupeqpqfwmgi/sql/new
-- 前提：已貼過 2026-10-19b_Gemini估算與校正倍數.sql。可以重複執行，不會刪任何資料、不會改任何資料表。
--
-- Michelle 2026-11-09 決定：Gemini 後台看到的是「餘額 Credit balance」，不是當月帳單，
-- 所以校正倍數改成用餘額算，可以任意區間、可以重疊：
--   一段（前一次餘額 → 這一次餘額）的實際花費 ＝ 前次餘額 ＋ 這段期間的儲值 − 這次餘額
--   這段的校正倍數 ＝ 實際花費 ÷ 同一段期間我們用官方單價估的金額
--   第一筆餘額只當起點，沒有倍數。
-- 倍數怎麼套用到每一筆用量（ai_gemini_costed）：
--   1. 落在某一段（有效）裡的用量 → 用那一段的倍數
--   2. 最後一段之後的用量 → 用最新一段的倍數
--   3. 其他（第一筆餘額之前、或被判定「請確認」的段）→ 備援：舊的整月帳單倍數（沒有就 ×1）
-- 防呆（段的狀態 status）：
--   ok     ：有效，倍數可用
--   merged ：這段估算不到 NT$3（倍數會亂跳），不當起點，併進下一次餘額一起算
--   check  ：實際花費 ≤ 0（餘額比預期高，常見原因是漏登儲值），這段不算倍數，請 Michelle 確認儲值紀錄
-- 儲值日期只有「日」沒有時間：儲值日 > 前次餘額那天、且 ≤ 這次餘額那天，算在這一段。
-- 舊的整月帳單表（ai_monthly_spend）與 ai_gemini_month_factors() 完全保留，當備援。
-- Gemini 每日估算餘額（ai_gemini_daily）本來就是「從最近一次實際餘額往後扣」，這份只是把每天扣的金額換成新倍數。
-- ══════════════════════════════════════════════════════════════════════

-- ★ 專案檢查：貼錯專案會在這裡停下，什麼都不會改
do $$ begin if to_regclass('public.ai_usage_events') is null then raise exception '貼錯專案！這段要貼到 TL_projects，請換專案重貼（什麼都沒改到）'; end if; end $$;


-- ---------- 1. 相鄰兩次實際餘額 → 每一段的實際花費與校正倍數 ----------
create or replace function public.ai_gemini_segments()
returns table (seg_start timestamptz, seg_end timestamptz, start_balance numeric, end_balance numeric,
               topups numeric, actual_spend numeric, raw_estimate numeric, factor numeric, status text)
language plpgsql stable security invoker set search_path = public as $$
declare
  r      record;
  a_at   timestamptz;   -- 目前的起點（上一個被採用的餘額時間）
  a_bal  numeric;
  v_cur  text := (select currency from public.ai_provider_settings where provider = 'gemini');
begin
  a_at := null;
  for r in select b.taken_at, b.balance from public.ai_balance_snapshots b
           where b.provider = 'gemini' order by b.taken_at, b.id loop
    if a_at is null then
      a_at := r.taken_at; a_bal := r.balance;
      continue;
    end if;
    seg_start := a_at; seg_end := r.taken_at; start_balance := a_bal; end_balance := r.balance;
    select coalesce(sum(t.amount), 0) into topups from public.ai_credit_topups t
      where t.provider = 'gemini' and t.currency = v_cur
        and t.topup_date >  (a_at       at time zone 'Asia/Taipei')::date
        and t.topup_date <= (r.taken_at at time zone 'Asia/Taipei')::date;
    select coalesce(sum(public.ai_list_cost('gemini', e.ai_model, e.prompt_tokens, e.completion_tokens)), 0) into raw_estimate
      from public.ai_usage_events e
      where public.ai_norm_provider(e.ai_provider, e.api_key_name) = 'gemini'
        and e.created_at > a_at and e.created_at <= r.taken_at;
    actual_spend := a_bal + topups - r.balance;
    if actual_spend <= 0 then
      factor := null; status := 'check';
      a_at := r.taken_at; a_bal := r.balance;       -- 起點往前移（這次餘額當新起點）
    elsif raw_estimate < 3 then
      factor := null; status := 'merged';           -- 起點不動，等下一次餘額一起算
    else
      factor := actual_spend / raw_estimate; status := 'ok';
      a_at := r.taken_at; a_bal := r.balance;
    end if;
    return next;
  end loop;
end $$;


-- ---------- 2. 每一筆 Gemini 用量：官方單價估算 × 該筆適用的倍數 ----------
create or replace function public.ai_gemini_costed(p_from timestamptz, p_to timestamptz)
returns table (created_at timestamptz, system_name text, raw_cost numeric, factor numeric)
language sql stable security invoker set search_path = public as $$
  with seg as (select s.seg_start, s.seg_end, s.factor from public.ai_gemini_segments() s where s.factor is not null),
  last_ok as (select s.seg_end, s.factor from seg s order by s.seg_end desc limit 1),
  mf as (select m.month, m.applied_factor from public.ai_gemini_month_factors() m),
  ev as (
    select e.created_at, e.system_name,
           public.ai_list_cost('gemini', e.ai_model, e.prompt_tokens, e.completion_tokens) as raw_cost
    from public.ai_usage_events e
    where public.ai_norm_provider(e.ai_provider, e.api_key_name) = 'gemini'
      and (p_from is null or e.created_at >= p_from)
      and (p_to   is null or e.created_at <  p_to)
  )
  select ev.created_at, ev.system_name, ev.raw_cost,
         coalesce(
           (select s.factor from seg s where ev.created_at > s.seg_start and ev.created_at <= s.seg_end limit 1),
           (select l.factor from last_ok l where ev.created_at > l.seg_end),
           (select m.applied_factor from mf m where m.month = date_trunc('month', (ev.created_at at time zone 'Asia/Taipei'))::date),
           (select m.applied_factor from mf m order by m.month desc limit 1),
           1)
  from ev
$$;


-- ---------- 3. 各系統估算花費（任意日期區間；函式名稱、欄位不變） ----------
create or replace function public.ai_gemini_by_system(p_start timestamptz, p_end timestamptz)
returns table (system_name text, est_spend numeric)
language sql stable security invoker set search_path = public as $$
  select coalesce(c.system_name, '(未知)'), round(sum(c.raw_cost * c.factor), 2)
  from public.ai_gemini_costed(p_start, p_end) c
  group by 1
$$;


-- ---------- 4. 每月估算金額（總覽「依月份」柱狀圖用） ----------
create or replace function public.ai_gemini_month_est()
returns table (month date, est_spend numeric)
language sql stable security invoker set search_path = public as $$
  select date_trunc('month', (c.created_at at time zone 'Asia/Taipei'))::date, round(sum(c.raw_cost * c.factor), 2)
  from public.ai_gemini_costed(null, null) c
  group by 1
  order by 1
$$;


-- ---------- 5. 每日估算花費與估算餘額（函式名稱、欄位不變；扣的金額改用新倍數） ----------
-- 餘額：有手動填過實際餘額 → 從最近一次實際餘額往下扣（填餘額那天＝填的數字）；還沒填過 → 從儲值金額往下扣。日期以台灣時間為準。
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
    select (c.created_at at time zone 'Asia/Taipei')::date as day,
           sum(c.raw_cost * c.factor) as est, sum(c.raw_cost) as raw_cost
    from first_day,
         lateral public.ai_gemini_costed(first_day.d::timestamp at time zone 'Asia/Taipei',
                                         (p_end + 1)::timestamp at time zone 'Asia/Taipei') c
    group by 1
  ),
  latest_factor as (
    select coalesce((select s.factor from public.ai_gemini_segments() s where s.factor is not null order by s.seg_end desc limit 1),
                    (select m.applied_factor from public.ai_gemini_month_factors() m order by m.month desc limit 1), 1) as v
  ),
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
           coalesce(r.est, 0) as est_spend,
           coalesce(r.est / nullif(r.raw_cost, 0), (select v from latest_factor)) as applied_factor,
           coalesce(t.amount, 0) as topup,
           s.balance as snap
    from days d
    left join raw r on r.day = d.day
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


-- ---------- 權限（跟其他 ai_ 函式一樣：登入者才能執行） ----------
revoke all on function public.ai_gemini_segments() from public, anon;
revoke all on function public.ai_gemini_costed(timestamptz, timestamptz) from public, anon;
revoke all on function public.ai_gemini_by_system(timestamptz, timestamptz) from public, anon;
revoke all on function public.ai_gemini_month_est() from public, anon;
revoke all on function public.ai_gemini_daily(date, date) from public, anon;
grant execute on function public.ai_gemini_segments() to authenticated;
grant execute on function public.ai_gemini_costed(timestamptz, timestamptz) to authenticated;
grant execute on function public.ai_gemini_by_system(timestamptz, timestamptz) to authenticated;
grant execute on function public.ai_gemini_month_est() to authenticated;
grant execute on function public.ai_gemini_daily(date, date) to authenticated;

-- 確認：看每一段（目前如果只有一筆餘額，這裡會是空的，正常）
select * from public.ai_gemini_segments();
