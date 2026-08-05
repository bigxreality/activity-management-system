// 名片辨識 - Supabase Edge Function
// 前端把拍好/選好的名片照片轉成 base64 傳進來，這裡呼叫 Google Gemini
// (多模態、看得懂圖片) 把名片上的文字整理成結構化 JSON 回傳給前端，
// 前端再把結果拿去預填「新增聯絡人」表單，使用者確認/修改後才真的存檔。
//
// 需要在 Supabase 專案設定 GEMINI_API_KEY 這個 secret 才能用：
//   supabase secrets set GEMINI_API_KEY=你的金鑰
// （或在 Supabase 後台「Edge Functions」→ 這個函式的「Secrets」分頁設定，
// 不一定要用 CLI）
//
// 部署：在專案根目錄執行 `supabase functions deploy card-ocr`
// 呼叫方式：POST {SUPABASE_URL}/functions/v1/card-ocr
//   body: { imageBase64: string, mimeType: string }
//   需要帶登入者的 Authorization: Bearer <access_token>，只有 admin/editor 能用
//   （這支會呼叫 Gemini API 產生費用，不開放 viewer 使用）

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// CORS 設定直接寫在這裡（不用 ../_shared/cors.ts），這樣整支函式是單一檔案，
// 可以直接複製貼到 Supabase 後台的 Edge Functions 編輯器部署，不用裝 CLI。
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY');
const GEMINI_MODEL = 'gemini-2.0-flash';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

// 用 responseSchema 強制 Gemini 回傳固定形狀的 JSON，比純靠 prompt 要求可靠很多。
const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    detected_language: { type: 'STRING', description: '名片主要文字使用的語言，用中文描述，例如：中文、英文、日文、阿拉伯文、希伯來文、韓文' },
    name_original: { type: 'STRING' },
    name_english: { type: 'STRING' },
    company_name_original: { type: 'STRING' },
    company_name_english: { type: 'STRING' },
    department_original: { type: 'STRING' },
    department_english: { type: 'STRING' },
    title_original: { type: 'STRING' },
    title_english: { type: 'STRING' },
    country: { type: 'STRING' },
    address_original: { type: 'STRING' },
    address_english: { type: 'STRING' },
    contact_methods: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          type: {
            type: 'STRING',
            enum: ['email', 'mobile', 'office_phone', 'fax', 'website', 'LINE', 'WhatsApp', 'WeChat', 'LinkedIn', 'other'],
          },
          value: { type: 'STRING' },
        },
        required: ['type', 'value'],
      },
    },
  },
  required: ['name_original', 'contact_methods'],
};

const PROMPT = `你是名片辨識助手，請仔細閱讀這張名片圖片上的所有文字，整理成結構化 JSON。

規則：
1. name_original / company_name_original / title_original / department_original / address_original 一律填「名片上印刷的原文」，維持原本語言與文字，不要自己翻譯。
2. 只有名片上真的印有對應的英文版本時，才把 *_english 欄位填上；名片上完全沒有英文就留空字串，不要自己翻譯生成。
3. contact_methods 把名片上所有電話、傳真、Email、網站、通訊軟體 ID 等聯絡方式都列出來，type 從指定的列舉值裡選最接近的，看不出來就用 other，value 填實際的號碼/帳號/網址原文。
4. 名片上沒有的欄位一律留空字串（或空陣列），不要自己編造內容。
5. 只輸出符合 schema 的 JSON，不要有任何其他文字或說明。`;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }
  if (!GEMINI_API_KEY) {
    return json({ error: 'Edge Function 尚未設定 GEMINI_API_KEY，請聯絡管理員在 Supabase 後台設定這個 secret' }, 500);
  }

  try {
    const authHeader = req.headers.get('Authorization') || '';
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: '請先登入' }, 401);
    }

    const { data: profile, error: profErr } = await supabase
      .from('profiles')
      .select('role')
      .eq('id', userData.user.id)
      .maybeSingle();
    if (profErr || !profile || (profile.role !== 'admin' && profile.role !== 'editor')) {
      return json({ error: '沒有權限使用名片辨識功能' }, 403);
    }

    const body = await req.json();
    const imageBase64: string | undefined = body.imageBase64;
    const mimeType: string = body.mimeType || 'image/webp';
    if (!imageBase64) {
      return json({ error: '缺少圖片內容' }, 400);
    }

    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                { text: PROMPT },
                { inline_data: { mime_type: mimeType, data: imageBase64 } },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: 'application/json',
            responseSchema: RESPONSE_SCHEMA,
          },
        }),
      }
    );

    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      return json({ error: `Gemini API 錯誤（${geminiRes.status}）：${errText}` }, 502);
    }

    const geminiData = await geminiRes.json();
    const text = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text || '';
    let parsed: unknown = null;
    try {
      parsed = JSON.parse(text);
    } catch (_e) {
      parsed = null;
    }
    if (!parsed) {
      return json({ error: 'AI 回傳的內容無法解析成 JSON，請重新掃描一次' }, 502);
    }

    const usage = geminiData?.usageMetadata || {};
    return json({
      result: parsed,
      raw_text: text,
      ai_model: GEMINI_MODEL,
      token_usage: usage.totalTokenCount ?? null,
    });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
