-- ══════════════════════════════════════════════════════════════════════
-- 【AI用量統計】改用「人資系統權限」免密碼登入：資料庫權限改版（2026-10-19）
-- 貼到 Supabase 專案：TL_projects（bvuygyajzupeqpqfwmgi）→ SQL Editor → 整份貼上 → Run
-- 可以重複執行。不會刪掉任何統計資料。
-- 前提：TL_technology 專案已貼 TL_technology\sql\2026-10-19_ai_usage_role.sql（人資系統的「AI用量統計」權限欄）。
--
-- 改了什麼：
--   1. dashboard_admins（可以看儀表板的名單）改成由登入程式 api/tl-sso.js 自動維護：
--      每次從首頁點卡片進來，依人資「AI用量統計」權限寫入 role（reader 僅讀取 / admin 管理員）與 sso_verified_at（確認時間）；
--      人資改成「無權限」的人，下次點進來會被移出名單。網頁上的「帳號管理」拿掉了，不再手動加人。
--   2. 誰能看、誰能改，一律由兩個函式判斷（資料庫層級，不只是畫面）：
--        ai_dash_can_read()  名單上（reader 或 admin），而且 12 小時內跟人資確認過
--        ai_dash_is_admin()  名單上是 admin，而且 12 小時內跟人資確認過
--      → 人資取消權限後，最晚 12 小時失效。舊函式 is_dashboard_admin(email) 也改成同一套規則（舊表原本用它）。
--   3. 所有相關資料表的規則重寫：讀＝ai_dash_can_read()；新增/修改/刪除＝ai_dash_is_admin()。
--   4. org_directory（email→公司/部門對照）原本「任何人都讀得到」，收緊成只有能看儀表板的人才讀得到。
--      （2026-10-17 搜尋過所有 repo，只有 ai-usage-dashboard 讀這張表；貼完隔天請確認各系統 AI 用量照常記錄。）
--   不受影響：每月自動上傳（api/auto-import.js）、DeepInfra 每日排程、各系統回報用量——都用伺服器金鑰，不受這些規則限制。
-- ══════════════════════════════════════════════════════════════════════


-- ---------- 1. 名單表加欄位 ----------
alter table public.dashboard_admins add column if not exists role text not null default 'admin';
alter table public.dashboard_admins add column if not exists sso_verified_at timestamptz;
do $$ begin
  alter table public.dashboard_admins add constraint dashboard_admins_role_chk check (role in ('reader', 'admin'));
exception when duplicate_object then null; end $$;
-- 登入程式用 email 找人（upsert），email 要是唯一值；原本已經是唯一值的話這行不會做任何事
do $$ begin
  if not exists (
    select 1 from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
    where i.indrelid = 'public.dashboard_admins'::regclass and i.indisunique and i.indnatts = 1 and a.attname = 'email'
  ) then
    create unique index dashboard_admins_email_uidx on public.dashboard_admins (email);
  end if;
end $$;


-- ---------- 2. 判斷函式 ----------
create or replace function public.ai_dash_can_read()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.dashboard_admins a
    where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and a.role in ('reader', 'admin')
      and a.sso_verified_at > now() - interval '12 hours'
  )
$$;

create or replace function public.ai_dash_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.dashboard_admins a
    where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and a.role = 'admin'
      and a.sso_verified_at > now() - interval '12 hours'
  )
$$;

revoke all on function public.ai_dash_can_read() from public, anon;
grant execute on function public.ai_dash_can_read() to authenticated;


-- ---------- 3. 資料表規則重寫：讀＝can_read，改＝is_admin ----------
-- 小工具：把某張表的舊規則全部刪掉，換成「讀 / 改」兩條（只在這份 SQL 裡用）
create or replace function pg_temp.reset_policies(t text, writable boolean) returns void language plpgsql as $$
declare p record;
begin
  execute format('alter table public.%I enable row level security', t);
  for p in select polname from pg_policy where polrelid = ('public.' || t)::regclass loop
    execute format('drop policy %I on public.%I', p.polname, t);
  end loop;
  execute format('create policy %I on public.%I for select to authenticated using (public.ai_dash_can_read())', t || '_read', t);
  if writable then
    execute format('create policy %I on public.%I for insert to authenticated with check (public.ai_dash_is_admin())', t || '_admin_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.ai_dash_is_admin()) with check (public.ai_dash_is_admin())', t || '_admin_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.ai_dash_is_admin())', t || '_admin_delete', t);
  end if;
end $$;

select pg_temp.reset_policies('ai_usage_events', false);          -- 只能讀（寫入由各系統透過伺服器金鑰）
select pg_temp.reset_policies('org_directory', false);            -- 只能讀（原本任何人都讀得到）
select pg_temp.reset_policies('ai_provider_settings', false);     -- 只能讀（幣別改設定請用 SQL）
select pg_temp.reset_policies('manual_ai_usage_monthly', true);   -- 月報明細：管理員才能上傳 Excel
select pg_temp.reset_policies('ai_credit_topups', true);          -- 儲值紀錄
select pg_temp.reset_policies('ai_balance_snapshots', true);      -- 實際餘額
select pg_temp.reset_policies('ai_monthly_spend', true);          -- 每月依 Key 實際花費
select pg_temp.reset_policies('ai_billing_checks', true);         -- 舊對帳表（已停用，一併收緊）

-- 名單表本身：只有管理員看得到名單；新增/修改/刪除一律由登入程式（伺服器金鑰）處理，網頁不能改
do $$ declare p record; begin
  for p in select polname from pg_policy where polrelid = 'public.dashboard_admins'::regclass loop
    execute format('drop policy %I on public.dashboard_admins', p.polname);
  end loop;
end $$;
alter table public.dashboard_admins enable row level security;
create policy dashboard_admins_admin_read on public.dashboard_admins
  for select to authenticated using (public.ai_dash_is_admin());

-- 舊函式 is_dashboard_admin(email)：上面的規則已經不再用它；保留同名函式但改成同一套規則，萬一還有別處呼叫也不會放寬
-- （原本的參數名稱不確定，所以先刪掉再建；如果有其他東西依賴它刪不掉，就跳過、保留原樣）
do $$ begin
  drop function if exists public.is_dashboard_admin(text);
  create function public.is_dashboard_admin(check_email text)
  returns boolean language sql stable security definer set search_path = public as
  'select lower(coalesce(check_email, '''')) = lower(coalesce(auth.jwt() ->> ''email'', '''')) and public.ai_dash_can_read()';
exception when others then raise notice 'is_dashboard_admin 保留原樣：%', sqlerrm;
end $$;


-- ---------- 確認結果：每張表應該只剩「_read」（和管理員的 insert/update/delete） ----------
select c.relname as 資料表, p.polname as 規則名稱,
       case p.polcmd when 'r' then 'SELECT' when 'a' then 'INSERT' when 'w' then 'UPDATE' when 'd' then 'DELETE' else 'ALL' end as 動作,
       pg_get_expr(p.polqual, p.polrelid) as 可讀條件, pg_get_expr(p.polwithcheck, p.polrelid) as 可寫條件
from pg_policy p join pg_class c on c.oid = p.polrelid
where c.relname in ('ai_usage_events', 'manual_ai_usage_monthly', 'org_directory', 'dashboard_admins',
                    'ai_credit_topups', 'ai_billing_checks', 'ai_balance_snapshots', 'ai_monthly_spend', 'ai_provider_settings')
order by 1, 2;
