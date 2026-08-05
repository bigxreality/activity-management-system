// 台灣銀行歷史匯率查詢 - Supabase Edge Function
// 取代原本 Google Apps Script 版本的 getBotRate()，邏輯完全比照：
// 資料來源 https://rate.bot.com.tw/xrt/flcsv/0/{日期} 這支 CSV，用欄位位置解析
// （不是文字標籤，因為中英文版本欄位標籤不同但位置固定）：
//   cols[2]=現金買入, cols[3]=即期買入, cols[12]=現金賣出, cols[13]=即期賣出
// 查無資料（例如假日銀行未營業）會自動往前找最近 7 天內的營業日。
//
// 部署：在專案根目錄執行 `supabase functions deploy bot-rate`
// 呼叫方式：GET {SUPABASE_URL}/functions/v1/bot-rate?date=YYYY-MM-DD&currency=USD

import { corsHeaders } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const dateStr = url.searchParams.get('date');
    const currency = (url.searchParams.get('currency') || 'USD').toUpperCase().trim();
    const result = await getBotRate(dateStr, currency);
    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});

async function getBotRate(dateStr: string | null, currency: string) {
  if (currency === 'TWD') {
    return { date: dateStr, currency: 'TWD', spotBuy: 1, spotSell: 1, cashBuy: 1, cashSell: 1 };
  }

  const d = dateStr ? new Date(dateStr + 'T00:00:00') : new Date();

  for (let tries = 0; tries < 7; tries++) {
    const tryDateStr = formatDate(d);
    const csvUrl = `https://rate.bot.com.tw/xrt/flcsv/0/${tryDateStr}`;
    try {
      const res = await fetch(csvUrl);
      if (res.ok) {
        const raw = await res.text();
        const text = raw.replace(/^﻿/, '');
        const lines = text.split('\n');
        for (let i = 1; i < lines.length; i++) {
          const cols = lines[i].split(',');
          if (cols.length < 14) continue;
          if (cols[0].trim().toUpperCase() === currency) {
            const cashBuy = parseFloat(cols[2]);
            const spotBuy = parseFloat(cols[3]);
            const cashSell = parseFloat(cols[12]);
            const spotSell = parseFloat(cols[13]);
            if (spotBuy || spotSell) {
              return {
                date: tryDateStr,
                requestedDate: dateStr,
                currency,
                cashBuy: cashBuy || null,
                spotBuy: spotBuy || null,
                cashSell: cashSell || null,
                spotSell: spotSell || null,
                usedFallback: tryDateStr !== dateStr,
              };
            }
          }
        }
      }
    } catch (_err) {
      // 忽略，繼續往前一天找
    }
    d.setDate(d.getDate() - 1);
  }

  return {
    error: `查無「${currency}」自 ${dateStr} 起前7天內的匯率資料，該幣別可能不支援或非本行牌告幣別`,
  };
}

function formatDate(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
