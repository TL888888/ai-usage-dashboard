// 自動產生:內容與 index.html 裡「Excel 匯入」使用的解析函式完全相同(parseTokenAmount / parseReportMonth /
// findHeaderRowAndCols / parseWorkbook)。如果要改匯入規則,請同時修改 index.html 與這個檔案。
// 檔名開頭的底線代表這不是對外的 API 入口,只是給 auto-import.js 共用的程式。
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const XLSX = require('xlsx');

// 把 "1.3B" "912M" "60K" "935.4K" 或純數字，轉成實際token數字；
// 也支援 "29.4K+8.974K" 這種用加號合併多筆的寫法，會自動加總；解析不出來回傳 null
function parseTokenAmount(raw) {
  if (raw === null || raw === undefined) return null;
  if (typeof raw === 'number') return Math.round(raw);
  const s = String(raw).trim();
  if (!s) return null;

  const parseSingle = (piece) => {
    const p = piece.trim();
    if (!p) return null;
    const m = p.match(/^([\d.]+)\s*([KkMmBb])$/);
    if (m) {
      const num = parseFloat(m[1]);
      if (isNaN(num)) return null;
      const mult = { k: 1e3, m: 1e6, b: 1e9 }[m[2].toLowerCase()];
      return num * mult;
    }
    const plain = parseFloat(p.replace(/,/g, ''));
    if (!isNaN(plain) && /^[\d.,]+$/.test(p)) return plain;
    return null;
  };

  if (s.includes('+')) {
    const parts = s.split('+').map(parseSingle);
    if (parts.some(v => v === null)) return null; // 只要有一段看不懂，整筆就當作無法解析，避免漏算
    return Math.round(parts.reduce((a, b) => a + b, 0));
  }

  const single = parseSingle(s);
  return single === null ? null : Math.round(single);
}

// 把 Excel 儲存格的月份值（可能是 Date 物件、Excel序號、或 "2026/08" 這種字串）轉成該月1號的 "YYYY-MM-01"
function parseReportMonth(raw) {
  if (raw === null || raw === undefined) return null;
  if (raw instanceof Date) {
    return raw.getFullYear() + '-' + String(raw.getMonth() + 1).padStart(2, '0') + '-01';
  }
  if (typeof raw === 'number') {
    // Excel 序號日期
    const d = XLSX.SSF.parse_date_code(raw);
    if (d) return d.y + '-' + String(d.m).padStart(2, '0') + '-01';
    return null;
  }
  const s = String(raw).trim();
  const m = s.match(/^(\d{4})[\/\-](\d{1,2})/);
  if (m) return m[1] + '-' + m[2].padStart(2, '0') + '-01';
  return null;
}

function findHeaderRowAndCols(sheetRows) {
  for (let r = 0; r < sheetRows.length; r++) {
    const row = sheetRows[r] || [];
    const idx = row.findIndex(c => String(c || '').trim() === '統計月份');
    if (idx !== -1) {
      const cols = {};
      row.forEach((cell, ci) => {
        const t = String(cell || '').trim();
        if (t === '統計月份') cols.month = ci;
        else if (t === '公司') cols.company = ci;
        else if (t === '部門') cols.department = ci;
        else if (t === '姓名') cols.person = ci;
        else if (t.startsWith('使用AI')) cols.tool = ci;
        else if (t.startsWith('方案')) cols.plan = ci;
        else if (t.startsWith('使用API')) cols.api = ci;
        else if (t.startsWith('本月token用量')) cols.token = ci;
        else if (t.startsWith('導入工作應用')) cols.usage = ci;
        else if (t.startsWith('備註')) cols.remark = ci;
      });
      return { headerRow: r, cols };
    }
  }
  return null;
}

function parseWorkbook(workbook) {
  const rows = [];
  const deptTotals = [];
  const warnings = [];
  let skippedNoReportCount = 0; // token沒填（視為當月沒回報）而被跳過的列數

  workbook.SheetNames.forEach(sheetName => {
    const ws = workbook.Sheets[sheetName];
    const sheetRows = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: null });
    const found = findHeaderRowAndCols(sheetRows);
    if (!found || found.cols.department === undefined || found.cols.token === undefined) {
      warnings.push(`分頁「${sheetName}」找不到標準表頭，已略過`);
      return;
    }
    const { headerRow, cols } = found;
    let currentDept = null, currentCompany = null, currentMonth = null;
    const sheetMonthMatch = String(sheetName).match(/(\d{1,2})\s*月/);
    const sheetMonthNum = sheetMonthMatch ? Number(sheetMonthMatch[1]) : null; // 工作表名稱裡的月份(例如「南京9月」→ 9),以它為準

    for (let r = headerRow + 1; r < sheetRows.length; r++) {
      const row = sheetRows[r] || [];
      const apiCell = cols.api !== undefined ? row[cols.api] : null;
      const isTotalRow = String(apiCell || '').includes('統計tokens');
      const person = cols.person !== undefined ? row[cols.person] : null;
      const dept = cols.department !== undefined ? row[cols.department] : null;
      const company = cols.company !== undefined ? row[cols.company] : null;

      if (isTotalRow) {
        const totalRaw = row[cols.token];
        const totalVal = parseTokenAmount(totalRaw);
        if (currentDept && currentCompany) {
          deptTotals.push({
            company: String(currentCompany).trim(),
            department: String(currentDept).trim(),
            report_month: currentMonth,
            token_amount: totalVal,
            token_amount_raw: totalRaw != null ? String(totalRaw) : null,
          });
        }
        currentDept = null;
        continue;
      }

      if (!dept && !person) continue; // 空白列跳過

      if (dept) currentDept = dept;
      if (company) currentCompany = company;
      const monthVal = cols.month !== undefined ? row[cols.month] : null;
      let parsedMonth = parseReportMonth(monthVal);
      // 工作表名稱寫幾月,就當作幾月(避免有人在「8月」的表裡把統計月份填成 9 月)
      if (parsedMonth && sheetMonthNum && Number(parsedMonth.slice(5, 7)) !== sheetMonthNum) parsedMonth = parsedMonth.slice(0, 4) + '-' + String(sheetMonthNum).padStart(2, '0') + '-01';
      if (parsedMonth) currentMonth = parsedMonth;

      if (!currentCompany || !currentDept) continue;

      // token欄位沒填、或換算出來是0:這個人仍然有使用AI(多半是網頁版或免費工具,沒有token數字),
      // 一樣列入並存成0,這樣「使用人數」「導入工作應用」「使用工具」才統計得到他。部門token小計不受影響(加0)。
      const tokenAmount = cols.token !== undefined ? parseTokenAmount(row[cols.token]) : null;
      if (!tokenAmount) skippedNoReportCount++;

      rows.push({
        report_month: currentMonth,
        company: String(currentCompany).trim(),
        department: String(currentDept).trim(),
        person_name: person ? String(person).trim() : null,
        ai_tool_name: cols.tool !== undefined && row[cols.tool] ? String(row[cols.tool]).trim() : null,
        plan_type: cols.plan !== undefined && row[cols.plan] ? String(row[cols.plan]).trim() : null,
        api_names: cols.api !== undefined && row[cols.api] ? String(row[cols.api]).trim() : null,
        token_amount: tokenAmount || 0,
        token_amount_raw: cols.token !== undefined && row[cols.token] != null ? String(row[cols.token]) : null,
        usage_note: cols.usage !== undefined && row[cols.usage] ? String(row[cols.usage]).trim() : null,
        remark: cols.remark !== undefined && row[cols.remark] ? String(row[cols.remark]).trim() : null,
      });
    }
  });

  if (skippedNoReportCount > 0) {
    warnings.push(`有 ${skippedNoReportCount} 筆沒有token數字（使用網頁版或免費工具），仍會列入使用人數與工作應用統計，token以0計`);
  }

  return { rows, deptTotals, warnings };
}

export { XLSX, parseWorkbook, parseTokenAmount };
