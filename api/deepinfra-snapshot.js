// api/deepinfra-snapshot.js
// 「AI用量統計」每天自動記錄 DeepInfra 的實際餘額（2026-10-16 建立）。
//
// 為什麼要這支：Michelle 決定「費用一律看供應商實際數字」。DeepInfra 有官方 API 可以查餘額，
// 但沒有「每天花多少」的 API，所以每天記一次餘額，「前一天餘額 + 當天儲值 − 當天餘額」就是當天實際花費
// （計算在資料庫函式 ai_daily_balance()，見 sql/2026-10-16b_實際花費與每日餘額.sql）。
//
// 呼叫的 DeepInfra 官方 API（文件：docs.deepinfra.com/api-reference/account/me.md、billing/usage.md）：
//   GET https://api.deepinfra.com/v1/me?checklist=true → checklist.stripe_balance
//       官方說明：負數＝可以用的錢（ready-to-spend），正數＝欠款。所以「餘額」＝ −stripe_balance。
//       ⚠️ 官方沒寫單位是美金還是美分。STRIPE_BALANCE_DIVISOR 控制換算（1＝美金，100＝美分），
//          第一次實測後依實際數字決定；原始數字一律存在 raw_value，判斷錯了可以用 SQL 重算。
//   GET https://api.deepinfra.com/payment/usage?from=YYYY.MM → months[].total_cost（官方註明單位是美分）
//       用來存「每月實際花費總計」（ai_monthly_spend，key_name='__TOTAL__'，source='api'）。
//
// 誰可以呼叫：
//   1. Vercel 每日排程（vercel.json 的 crons，每天台灣時間約 23:50）。有設 CRON_SECRET 就比對它；
//      沒設的話只認 Vercel 排程的 user-agent（較弱，但這支只會「讀餘額、寫一筆紀錄」，被亂打也不會造成損害）。
//   2. 儀表板管理員按「立即抓 DeepInfra 餘額」：帶 Supabase 登入憑證，這裡確認是 dashboard_admins 名單上的人。
//      加上 ?dry=1 只回傳 DeepInfra 原始數字、不寫資料庫（第一次實測用）。
//
// 需要的 Vercel 環境變數：
//   DEEPINFRA_API_KEY_BILLING  DeepInfra 金鑰（只放在 Vercel，網頁上看不到）
//   SUPABASE_SERVICE_ROLE_KEY  已經有（auto-import 也在用）
//   CRON_SECRET                （選填）Vercel 排程的通關密語

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://bvuygyajzupeqpqfwmgi.supabase.co';
const STRIPE_BALANCE_DIVISOR = Number(process.env.DEEPINFRA_BALANCE_DIVISOR || 1); // 實測後確認：1＝美金、100＝美分

function monthKey(d) { return d.getUTCFullYear() + '.' + String(d.getUTCMonth() + 1).padStart(2, '0'); }

async function deepinfraGet(path, key) {
  const r = await fetch('https://api.deepinfra.com' + path, { headers: { Authorization: 'Bearer ' + key } });
  const text = await r.text();
  let json = null;
  try { json = JSON.parse(text); } catch (_) { /* 不是 JSON 就留原文 */ }
  return { ok: r.ok, status: r.status, json, text: text.slice(0, 300) };
}

async function whoCalls(req, sb) {
  const auth = String(req.headers.authorization || '');
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret && auth === 'Bearer ' + cronSecret) return { kind: 'cron' };
  if (!cronSecret && /vercel-cron/i.test(String(req.headers['user-agent'] || ''))) return { kind: 'cron' };
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return null;
  const { data, error } = await sb.auth.getUser(token);
  if (error || !data || !data.user || !data.user.email) return null;
  const { data: admin } = await sb.from('dashboard_admins').select('email').eq('email', data.user.email.toLowerCase()).maybeSingle();
  return admin ? { kind: 'admin', email: data.user.email } : null;
}

export default async function handler(req, res) {
  const key = process.env.DEEPINFRA_API_KEY_BILLING;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key || !serviceKey) {
    res.status(500).json({ error: '伺服器尚未設定 DEEPINFRA_API_KEY_BILLING 或 SUPABASE_SERVICE_ROLE_KEY' });
    return;
  }
  const sb = createClient(SUPABASE_URL, serviceKey, { auth: { persistSession: false } });
  const caller = await whoCalls(req, sb);
  if (!caller) { res.status(401).json({ error: '沒有權限' }); return; }
  const dry = String(req.query?.dry || '') === '1';

  const me = await deepinfraGet('/v1/me?checklist=true', key);
  const now = new Date();
  const prevMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  const usage = await deepinfraGet(`/payment/usage?from=${monthKey(prevMonth)}&to=${monthKey(now)}`, key);

  const checklist = me.json && me.json.checklist;
  const raw = checklist && typeof checklist.stripe_balance === 'number' ? checklist.stripe_balance : null;
  const result = {
    caller: caller.kind,
    me_status: me.status,
    usage_status: usage.status,
    raw_stripe_balance: raw,
    raw_recent: checklist ? checklist.recent : null,
    divisor: STRIPE_BALANCE_DIVISOR,
    balance_usd: raw == null ? null : -raw / STRIPE_BALANCE_DIVISOR,
    usage_months: usage.json && Array.isArray(usage.json.months)
      ? usage.json.months.map(m => ({ period: m.period, total_cost_cents: m.total_cost, invoice_id: m.invoice_id }))
      : null,
  };
  if (!me.ok) result.me_error = me.text;
  if (!usage.ok) result.usage_error = usage.text;
  if (dry) { res.status(200).json({ dry: true, ...result }); return; }

  const errors = [];
  if (raw != null) {
    const { error } = await sb.from('ai_balance_snapshots').insert({
      provider: 'deepinfra', taken_at: now.toISOString(), balance: result.balance_usd, source: 'api', raw_value: raw,
      note: 'DeepInfra API /v1/me stripe_balance', created_by: caller.kind === 'admin' ? caller.email : 'Vercel 排程',
    });
    if (error) errors.push('寫入餘額失敗：' + error.message);
  } else {
    errors.push('DeepInfra 沒有回傳 stripe_balance（狀態碼 ' + me.status + '）');
  }
  if (result.usage_months) {
    for (const m of result.usage_months) {
      if (!/^\d{4}\.\d{2}$/.test(String(m.period)) || typeof m.total_cost_cents !== 'number') continue;
      const month = String(m.period).replace('.', '-') + '-01';
      const { error } = await sb.from('ai_monthly_spend').upsert({
        provider: 'deepinfra', month, key_name: '__TOTAL__', amount: m.total_cost_cents / 100, source: 'api',
        note: 'DeepInfra API /payment/usage（' + (m.invoice_id === 'NOT_FINAL' ? '本月尚未結算' : '已結算') + '）',
        created_by: 'Vercel 排程', updated_at: now.toISOString(),
      }, { onConflict: 'provider,month,key_name' });
      if (error) errors.push(`寫入 ${m.period} 月花費失敗：` + error.message);
    }
  }
  res.status(errors.length ? 207 : 200).json({ ...result, errors });
}
