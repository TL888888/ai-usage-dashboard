// api/usage-report.js
// 讓「不在我們雲端系統裡」的程式回報 AI 用量到 AI用量統計（2026-10-19 建立，第一個使用者：同事的 Guard system／掛號包裹登記）。
//
// 為什麼不用各系統共用的 Edge Function stats-ai-usage-push：那邊的通關密語是我們自家系統共用的，
// 不適合交給外部同事。這裡給每個外部程式一組「專用回報密語」，而且：
//   - 只能寫入一筆用量，讀不到任何資料
//   - 系統名稱、Key 名稱、供應商由這裡固定，對方改不了（不會冒充成別的系統）
//   - 回報失敗不影響對方原本的功能（對方程式要用 try/catch 包起來，說明文件有寫）
//
// 呼叫方式（POST，JSON）：
//   標頭 x-report-token: <專用回報密語>
//   內容 { "model": "gemini-2.5-flash", "prompt_tokens": 1234, "candidates_tokens": 56, "thoughts_tokens": 78, "asker": "晚班" }
//   thoughts_tokens（思考 tokens）照輸出單價計費，所以這裡把它加進 completion_tokens。
//
// 回報來源設定（要新增外部程式時，在 SOURCES 加一筆，並在 Vercel 設對應的環境變數）：
const SOURCES = {
  guard: {
    tokenEnv: 'GUARD_REPORT_TOKEN',   // Vercel 環境變數名稱（密語本身只放在 Vercel，由 Michelle 另外交給同事）
    system_name: 'guard',
    api_key_name: 'Guard system',
    ai_provider: 'gemini',
  },
};
// 需要的 Vercel 環境變數：GUARD_REPORT_TOKEN、SUPABASE_SERVICE_ROLE_KEY（已有）

import { createClient } from '@supabase/supabase-js';
import crypto from 'crypto';

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://bvuygyajzupeqpqfwmgi.supabase.co';
const MAX_TOKENS = 5000000; // 單次回報的合理上限，超過視為格式錯誤

function sameSecret(a, b) {
  const ha = crypto.createHash('sha256').update(String(a || '')).digest();
  const hb = crypto.createHash('sha256').update(String(b || '')).digest();
  return crypto.timingSafeEqual(ha, hb);
}
function tokenCount(v) {
  const n = Number(v || 0);
  return Number.isFinite(n) && n >= 0 && n <= MAX_TOKENS ? Math.round(n) : null;
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.status(405).json({ error: 'method not allowed' }); return; }
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const given = req.headers['x-report-token'];
  // 用密語找出是哪個來源（每個來源一組密語）
  const sourceKey = Object.keys(SOURCES).find(k => {
    const expected = process.env[SOURCES[k].tokenEnv];
    return expected && given && sameSecret(given, expected);
  });
  if (!sourceKey) { res.status(401).json({ error: '回報密語不正確' }); return; }
  if (!serviceKey) { res.status(500).json({ error: '伺服器未設定 SUPABASE_SERVICE_ROLE_KEY' }); return; }

  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch (_) { body = null; } }
  if (!body || typeof body !== 'object') { res.status(400).json({ error: '內容格式不對，要是 JSON' }); return; }
  const prompt = tokenCount(body.prompt_tokens);
  const candidates = tokenCount(body.candidates_tokens);
  const thoughts = tokenCount(body.thoughts_tokens);
  if (prompt == null || candidates == null || thoughts == null) { res.status(400).json({ error: 'tokens 數字不正確' }); return; }

  const src = SOURCES[sourceKey];
  const completion = candidates + thoughts;
  const sb = createClient(SUPABASE_URL, serviceKey, { auth: { persistSession: false } });
  const { error } = await sb.from('ai_usage_events').insert({
    system_name: src.system_name,
    api_key_name: src.api_key_name,
    ai_provider: src.ai_provider,
    ai_model: String(body.model || '').slice(0, 80) || null,
    asker_email: null,
    asker_name: String(body.asker || '').slice(0, 60) || null,
    prompt_tokens: prompt,
    completion_tokens: completion,
    total_tokens: prompt + completion,
    cache_hit: false,
    estimated_cost_usd: 0, // 費用不在這裡算：Gemini 花費由 AI用量統計 用 tokens × 官方單價 × 校正倍數估算
  });
  if (error) { res.status(500).json({ error: '寫入失敗：' + error.message }); return; }
  res.status(200).json({ ok: true });
}
