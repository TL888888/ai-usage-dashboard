// api/tl-sso.js
// 「AI用量統計」改成依人資系統權限免密碼登入（Michelle 2026-10-19；帳號密碼登入已完全拿掉）
// 做法照營業商務訊息（wechat-message-manager/api/tl-sso.js），並沿用它 2026-10-16 修漏洞的教訓：
//   找不到人、沒有權限一律拒絕，絕不預設成管理者；不留任何「用密碼登入」的緊急入口。
//
// 流程：
//  1. 使用者在 tl-home.com 首頁點「AI用量統計」卡片，首頁把「他在首頁的登入憑證」放在網址 # 後面帶過來
//     （# 後面的內容不會送到任何伺服器；直接打開本網址的人會被導回首頁 ?goto=ai-usage，首頁確認登入後再帶過來）
//  2. 本系統前端把憑證 POST 到這支 API
//  3. 這裡拿憑證去 TL_technology 的 Supabase 確認身分，讀人資系統 members 表的 ai_usage_role（人資系統的「AI用量統計」欄）
//       reader → 僅讀取：看得到全部統計，不能改
//       admin  → 管理員：可以改儲值、實際餘額、每月花費、上傳月報 Excel
//       none / 空白 / 找不到人 → 拒絕，並把他從 dashboard_admins 名單移除
//  4. 有權限：在本系統（TL_projects）找到/建立同 email 的帳號（不設密碼），把他寫進 dashboard_admins
//     （role＋sso_verified_at＝現在），產生一次性登入碼回傳，前端用它直接登入。
//     資料庫只認「12 小時內確認過」的名單（見 sql/2026-10-19_人資權限登入_權限改版.sql），所以人資取消權限最晚 12 小時失效；
//     前端也會在超過 12 小時時自動回首頁重新確認。
//
// 交接給 MIS：在人資系統把 MIS 的「AI用量統計」設成管理員、關掉 Michelle 的即可，不用改程式。
//
// 需要的 Vercel 環境變數：SUPABASE_SERVICE_ROLE_KEY（已有）。TL_technology 的連線設定讀首頁公開的 /api/env（anon key 屬公開金鑰）。

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://bvuygyajzupeqpqfwmgi.supabase.co';
const TL_ENV_URL = 'https://tl-home.com/api/env';
const ALLOWED_ROLES = ['reader', 'admin']; // 人資系統「AI用量統計」下拉選單的值

async function getTlTechConfig() {
  if (process.env.TL_TECH_SUPABASE_URL && process.env.TL_TECH_SUPABASE_KEY) {
    return { url: process.env.TL_TECH_SUPABASE_URL, key: process.env.TL_TECH_SUPABASE_KEY };
  }
  const r = await fetch(TL_ENV_URL);
  if (!r.ok) throw new Error('讀不到首頁系統設定');
  const j = await r.json();
  return { url: j.SUPABASE_URL, key: j.SUPABASE_KEY };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.status(405).json({ error: 'method not allowed' }); return; }
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) { res.status(500).json({ error: '伺服器未設定 SUPABASE_SERVICE_ROLE_KEY' }); return; }
  const token = req.body && req.body.token;
  if (!token || typeof token !== 'string') { res.status(400).json({ error: '缺少首頁登入憑證' }); return; }

  try {
    // 1. 向 TL_technology 確認身分與人資權限
    const tlCfg = await getTlTechConfig();
    const tl = createClient(tlCfg.url, tlCfg.key, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: ud, error: ue } = await tl.auth.getUser(token);
    if (ue || !ud || !ud.user || !ud.user.email) {
      res.status(401).json({ error: '首頁登入狀態已過期，請回首頁重新整理後再點一次卡片' });
      return;
    }
    const email = ud.user.email.trim().toLowerCase();
    const { data: member, error: me } = await tl.from('members').select('*').eq('id', ud.user.id).maybeSingle();
    if (me) throw new Error('讀取人資權限失敗：' + me.message);

    const svc = createClient(SUPABASE_URL, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const hrRole = member && member.ai_usage_role;
    if (!ALLOWED_ROLES.includes(hrRole)) {
      // 沒權限：順便移出名單，確保人資取消權限後不會殘留
      await svc.from('dashboard_admins').delete().eq('email', email);
      res.status(403).json({ error: '人資系統尚未開通您的「AI用量統計」權限，請洽人資或管理員' });
      return;
    }
    const name = ((member && member.name) || '').trim() || email.split('@')[0];

    // 2. 本系統：確保有同 email 的登入帳號（沒有就自動建立，不設密碼）
    const { error: ce } = await svc.auth.admin.createUser({ email, email_confirm: true });
    if (ce && !/already|registered|exists/i.test(ce.message || '')) throw ce;

    // 3. 寫進可以看儀表板的名單（資料庫權限依這份名單＋確認時間判斷）
    const { error: ae } = await svc.from('dashboard_admins').upsert(
      { email, display_name: name, role: hrRole, sso_verified_at: new Date().toISOString(), added_by: '人資權限自動登入' },
      { onConflict: 'email' });
    if (ae) throw new Error('寫入權限名單失敗：' + ae.message);

    // 4. 產生一次性登入碼，並把權限記在帳號上（前端用來決定畫面能不能改；只有伺服器能改 app_metadata）
    const { data: link, error: le } = await svc.auth.admin.generateLink({ type: 'magiclink', email });
    if (le) throw le;
    await svc.auth.admin.updateUserById(link.user.id, {
      app_metadata: Object.assign({}, link.user.app_metadata, { tl_ai_usage_role: hrRole, tl_ai_sso_at: Date.now() }),
    });

    res.status(200).json({ token_hash: link.properties.hashed_token, role: hrRole });
  } catch (e) {
    res.status(500).json({ error: '自動登入失敗：' + (e && e.message ? e.message : String(e)) });
  }
}
