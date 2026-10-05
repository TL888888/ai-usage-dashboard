// api/auto-import.js
// 「AI用量統計」每月自動上傳入口:給 Michelle 電腦上的排程(每月6日下午5點)把月報 Excel 送進來。
//
// 流程:電腦排程 → POST 這個網址(Excel 檔當作原始內容、標頭帶通關密語 x-upload-token)
//        → 這裡用「與手動匯入完全相同」的規則解析(api/_parse.js)→ 寫進資料庫 manual_ai_usage_monthly。
// 規則與手動匯入一致:同一家公司、同一個月份,先刪掉舊資料再寫入新資料(重複執行不會重複累加)。
//
// 需要的 Vercel 環境變數(只放在 Vercel,不放進程式碼或 GitHub):
//   AUTO_IMPORT_TOKEN          通關密語。只能用來呼叫這個入口,不能做其他事
//   SUPABASE_SERVICE_ROLE_KEY  資料庫(TL_projects)的 service_role 金鑰,伺服器端寫入資料用
//   SUPABASE_URL               (選填)預設 https://bvuygyajzupeqpqfwmgi.supabase.co
//
// 注意:Vercel 單次請求上限約 4.5MB;超過會被拒絕(回 413),此時請手動匯入,或先縮小 Excel。

import { createClient } from '@supabase/supabase-js';
import crypto from 'crypto';
import { XLSX, parseWorkbook } from './_parse.js';

export const config = { api: { bodyParser: false }, maxDuration: 60 };

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://bvuygyajzupeqpqfwmgi.supabase.co';
const MAX_BYTES = 4.4 * 1024 * 1024;

function sameSecret(a, b) {
  // 先各自轉成固定長度的雜湊再比較,避免長度不同或比對時間洩漏資訊
  const ha = crypto.createHash('sha256').update(String(a || '')).digest();
  const hb = crypto.createHash('sha256').update(String(b || '')).digest();
  return crypto.timingSafeEqual(ha, hb);
}

async function readBody(req) {
  const chunks = []; let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > MAX_BYTES) { const e = new Error('檔案太大'); e.code = 413; throw e; }
    chunks.push(c);
  }
  return Buffer.concat(chunks);
}

export default async function handler(req, res) {
  const token = process.env.AUTO_IMPORT_TOKEN;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  // 健康檢查:只回報「設定好了沒」,不回報任何密碼
  if (req.method === 'GET') { res.status(200).json({ ok: true, configured: !!(token && serviceKey) }); return; }
  if (req.method !== 'POST') { res.status(405).json({ error: 'Method not allowed' }); return; }
  if (!token || !serviceKey) { res.status(500).json({ error: '伺服器尚未設定 AUTO_IMPORT_TOKEN 或 SUPABASE_SERVICE_ROLE_KEY' }); return; }
  if (!sameSecret(req.headers['x-upload-token'], token)) { res.status(401).json({ error: '通關密語不正確' }); return; }

  let buf;
  try { buf = await readBody(req); } catch (e) {
    res.status(e.code === 413 ? 413 : 400).json({ error: e.code === 413 ? '檔案超過 4.4MB,請改用手動匯入' : '讀取檔案失敗' }); return;
  }
  if (!buf.length) { res.status(400).json({ error: '沒有收到檔案內容' }); return; }

  let parsed;
  try {
    const wb = XLSX.read(buf, { type: 'buffer', cellDates: true });
    parsed = parseWorkbook(wb);
  } catch (e) { res.status(422).json({ error: '無法讀取這個 Excel:' + (e && e.message ? e.message : e) }); return; }
  const { rows, warnings } = parsed;
  if (!rows.length) { res.status(422).json({ error: '檔案裡找不到可匯入的資料(需要有「統計月份」「公司」「部門」等標準表頭)', warnings }); return; }
  const noMonth = rows.filter(r => !r.report_month).length;
  if (noMonth) { res.status(422).json({ error: `有 ${noMonth} 筆沒有統計月份,為避免寫錯月份已全部取消`, warnings }); return; }

  const sb = createClient(SUPABASE_URL, serviceKey, { auth: { persistSession: false } });
  const combos = new Set(rows.map(r => r.company + '|' + r.report_month));
  try {
    for (const combo of combos) {
      const [company, month] = combo.split('|');
      const { error } = await sb.from('manual_ai_usage_monthly').delete().eq('company', company).eq('report_month', month);
      if (error) throw new Error('刪除舊資料失敗:' + error.message);
    }
    const toInsert = rows.map(r => ({ ...r, imported_by: 'auto-import(本機排程)' }));
    for (let i = 0; i < toInsert.length; i += 500) {
      const { error } = await sb.from('manual_ai_usage_monthly').insert(toInsert.slice(i, i + 500));
      if (error) throw new Error('寫入資料失敗:' + error.message);
    }
  } catch (e) {
    console.error('auto-import 失敗:', e);
    res.status(500).json({ error: String(e.message || e), hint: '舊資料可能已被刪除,請再執行一次(或手動匯入)即可補齊' });
    return;
  }

  const months = [...new Set(rows.map(r => r.report_month))].sort();
  const companies = [...new Set(rows.map(r => r.company))];
  res.status(200).json({ ok: true, inserted: rows.length, months, companies, warnings });
}
