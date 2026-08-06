# 活動管理系統

公司展覽/活動的費用管理工具。前端是純 HTML/JS（放在這個 repo，用 GitHub Pages 發布），
資料儲存在 **Supabase**（Postgres + Auth + Storage + Edge Functions）。

> 這個專案原本是 Google Sheet + Apps Script 架構，因為 Apps Script 的部署模型太反直覺
> （`/dev` vs `/exec` 網址搞混、CORS 要用 `text/plain` 繞過預檢請求、改權限要重新部署
> 版本才會生效……）反覆卡關，已經整個換成 Supabase。

## 目前狀態

- ✅ 費用明細 / 展覽總覽 / 儀表板（Supabase 版，含台銀歷史匯率查詢、PWA 基礎架構）
- ✅ 權限系統細節（viewer 隱藏按鈕、管理員的使用者管理畫面）
- ✅ 附件上傳（收據/票根/發票，存進 Supabase Storage 的 `attachments` bucket）
- ✅ 費用明細改成「單據（一張發票/收據）+ 品項（可多筆）」兩層結構，含付款對象主檔
- ✅ CRM 模組重新設計（公司／聯絡人取代名單、聯絡方式、參展紀錄、聯繫紀錄、待辦事項、
  產品管理、多語系欄位＋RTL 文字方向偵測）
- ✅ 儀表板改成合併總覽（費用＋CRM 統計都在同一頁），費用管理／客戶名單 CRM 拆成
  兩個入口，使用者管理維持獨立可隨時進入
- ✅ 名片 AI 掃描辨識（用 Google Gemini，拍照/上傳名片後自動預填聯絡人表單，
  名片上的公司會自動比對／自動建檔，同一張名片重複掃描會沿用上次結果、不重複計費）
- ✅ 公司分類（客戶／供應商／媒體／合作夥伴／社團組織）與產業類別，行銷可以用
  同一套系統建立禮贈品、印刷、電視台、報社等供應商與媒體人脈；同一家公司的
  成員會歸類在一起，展開公司即可看到人員清單與各自的負責項目
- ✅ 一人多重身分：同一個聯絡人可以同時是 A 公司總經理、B 公司總裁、扶輪社社長，
  每一段身分各自有自己的職稱、部門、負責項目
- ⏳ 離線掃描佇列、重複聯絡人偵測、客戶自填表單、草稿暫存 — 下一階段
- ⏳ 請款單／差旅報告單匯出 — 下一階段
- ⏳ 整體改名與入口首頁、分析儀表板擴充 — 下一階段

## 檔案說明

- `index.html` — 前端網頁本體，GitHub Pages 會自動把它當首頁。用 `supabase-js`
  （透過 CDN 的 ESM 版本引入）直接跟 Supabase 溝通，沒有任何中間層後端程式碼。
- `manifest.json` / `sw.js` / `icons/` — PWA 基礎架構，可以把網站加到手機主畫面，
  離線時至少能開啟介面（資料讀寫仍需要網路）。
- `supabase/sql/01_schema_and_rls.sql` — 資料表結構 + Row Level Security 規則，
  在 Supabase 專案的 SQL Editor 貼上執行一次即可（可重複執行）。
- `supabase/sql/02_set_initial_roles.sql` — 一次性設定五位使用者角色的腳本，
  **要等 Supabase Auth 帳號都建立好之後才能跑**。
- `supabase/sql/03_attachments_storage.sql` — 建立費用明細附件用的 `attachments`
  Storage bucket（私有）與權限規則。
- `supabase/sql/04_expense_documents.sql` — **破壞性變更**：把費用明細改成
  「單據 `expense_documents` + 品項 `expense_items`」兩層結構，新增 `payees`
  付款對象主檔，會先刪除舊的 `expenses` 表（含裡面的資料）再重建。
- `supabase/sql/05_crm.sql` — CRM 模組：`leads`（名單）、`contact_logs`（聯繫紀錄）、
  `identity_weights`（身份權重設定，含初始資料）三張表、`leads_with_score` view，
  以及名片/頭像照片用的 `photos` Storage bucket（私有）。
- `supabase/sql/06_item_level_tax_and_attachments.sql` — 品項欄位重構：附件改掛在
  品項上（不是單據），稅額改成用稅率自動算（`amount × tax_rate ÷ 100` 的
  generated column），移除單據層級的 `attachments` 欄位。
- `supabase/sql/07_profiles_department_title.sql` — `profiles` 表新增部門、職稱
  欄位，管理員可以在「使用者管理」畫面直接編輯。
- `supabase/sql/08_crm_v2.sql` — **破壞性變更**：CRM 模組整個重新設計，`companies`
  （公司）＋ `contacts`（聯絡人，取代 `leads`）＋ `contact_methods`（聯絡方式）＋
  `event_contacts`（展覽 × 聯絡人）＋ `interactions`（聯繫紀錄，取代
  `contact_logs`）＋ `tasks`（待辦事項）＋ `products`（感興趣產品清單，含初始
  資料）＋ `business_cards` / `public_lead_submissions`（先建表，之後幾批才會接
  上實際畫面），會先刪除舊的 `leads`／`contact_logs` 表（含裡面的資料）再重建。
- `supabase/sql/09_company_types_and_responsibility.sql` — `companies` 新增類型
  （客戶／供應商／媒體／合作夥伴／其他）、產業類別、備註欄位，`contacts` 新增
  「負責項目／功能」欄位，讓 CRM 除了客戶之外也能管理供應商與媒體人脈。
- `supabase/sql/10_contact_affiliations.sql` — 一人多重身分：新增
  `contact_affiliations` 中間表（人 ↔ 單位多對多），職稱／部門／負責項目改成掛在
  「這一段身分」上；公司類型多一個「社團組織」（扶輪社、獅子會等）。腳本會自動
  把舊資料搬進新表，再移除 `contacts` 上的 `company_id`／職稱／部門欄位。
- `supabase/functions/bot-rate/` — 台灣銀行歷史匯率查詢的 Supabase Edge Function，
  取代原本 Apps Script 的 `getBotRate`。
- `supabase/functions/card-ocr/` — 名片辨識的 Supabase Edge Function，前端把名片
  照片轉成 base64 傳進來，這裡呼叫 Google Gemini（多模態）辨識成結構化 JSON 再
  回傳，只有 admin/editor 能呼叫（會產生 Gemini API 費用，不開放 viewer）。

## 部署步驟（第一次設定）

### 1. 建立 Supabase 專案

1. 到 [supabase.com](https://supabase.com) 建立一個新專案
2. 「Project Settings」→「API」，複製 **Project URL** 和 **anon public key**
3. 把這兩個值填進 `index.html` 裡的 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY` 常數
   （anon key 是設計成可以公開放在前端程式碼裡的，安全性由 RLS 把關；
   **千萬不要**把 service role key 放進來或 commit 進 repo）

### 2. 建立資料表與權限規則

1. Supabase 後台左側「SQL Editor」
2. 貼上 `supabase/sql/01_schema_and_rls.sql` 的全部內容，執行

### 3. 建立使用者帳號

1. Supabase 後台「Authentication」→「Users」→手動新增五位使用者的 Email（可以先設一個
   暫時密碼，之後請同事自己改，或用「邀請使用者」讓對方收信設定密碼）
2. 建立帳號時會自動在 `profiles` 表生一筆資料（預設角色是 `viewer`）
3. 回到「SQL Editor」，貼上並執行 `supabase/sql/02_set_initial_roles.sql`，
   把角色改成正確的 admin / editor / viewer

### 4. 部署台銀匯率查詢的 Edge Function

需要先安裝 [Supabase CLI](https://supabase.com/docs/guides/cli) 並登入、連結專案：

```bash
supabase login
supabase link --project-ref <你的 project ref>
supabase functions deploy bot-rate
```

### 5. 建立附件用的 Storage bucket

1. Supabase 後台左側「SQL Editor」
2. 貼上 `supabase/sql/03_attachments_storage.sql` 的全部內容，執行
3. 如果 `insert into storage.buckets` 那段因為權限跑不過，改成手動在「Storage」頁面
   按「New bucket」，名稱填 `attachments`，「Public bucket」開關**保持關閉**，
   後面的權限規則（RLS policy）一樣會生效

### 6. 費用明細改成單據＋品項兩層結構（破壞性變更）

1. Supabase 後台左側「SQL Editor」
2. 貼上 `supabase/sql/04_expense_documents.sql` 的全部內容，執行
3. **這會刪除舊的 `expenses` 表**，如果裡面有不想遺失的資料要先自己備份

### 7. 建立 CRM 模組的資料表

1. Supabase 後台左側「SQL Editor」
2. 貼上 `supabase/sql/05_crm.sql` 的全部內容，執行
3. 如果 `insert into storage.buckets` 那段權限跑不過，改成手動在「Storage」頁面
   建立名為 `photos` 的私有 bucket（做法同附件 bucket）

### 8. 品項欄位重構（附件改掛在品項上、稅額改用稅率算）

1. Supabase 後台左側「SQL Editor」
2. 貼上 `supabase/sql/06_item_level_tax_and_attachments.sql` 的全部內容，執行
3. 如果之前有測試品項填過稅額，這次執行後稅額會變成用稅率重新算，之前手動填的
   稅額數字會不見（稅率預設 0）

### 9. 使用者權限加部門/職稱

1. Supabase 後台左側「SQL Editor」
2. 貼上 `supabase/sql/07_profiles_department_title.sql` 的全部內容，執行

### 10. CRM 模組重新設計（破壞性變更，會刪除舊的名單資料）

1. Supabase 後台左側「SQL Editor」
2. 貼上 `supabase/sql/08_crm_v2.sql` 的全部內容，執行
3. **這會刪除舊的 `leads`、`contact_logs` 表**，如果裡面有不想遺失的資料要先自己備份
   （這兩張表是這幾天才剛做出來的測試功能，資料結構跟新版完全不同，無法自動轉換）

### 11. 部署名片辨識的 Edge Function（需要 Google Gemini API 金鑰）

1. 到 [Google AI Studio](https://aistudio.google.com/apikey) 申請一組 Gemini API
   金鑰（免費額度就能用，量大才會收費）
2. 部署這支 Edge Function，有兩種做法都可以：
   - **用 CLI**（跟第 4 步一樣要先裝好 Supabase CLI）：
     ```bash
     supabase functions deploy card-ocr
     supabase secrets set GEMINI_API_KEY=你的金鑰
     ```
   - **不裝 CLI，直接在網頁後台操作**：Supabase 後台左側「Edge Functions」→
     「Create a new function」，名稱填 `card-ocr`，把 `supabase/functions/card-ocr/index.ts`
     的內容貼進去部署；接著到這支函式的「Secrets」分頁新增一筆
     `GEMINI_API_KEY`，值填你申請到的金鑰
3. 這支函式只有 admin/editor 能呼叫，而且每次辨識都會呼叫 Gemini API 產生費用
   （同一張名片重複掃描會直接沿用上次的辨識結果，不會重複呼叫）

### 12. 公司分類與聯絡人負責項目

1. Supabase 後台左側「SQL Editor」
2. 貼上 `supabase/sql/09_company_types_and_responsibility.sql` 的全部內容，執行
3. 既有的公司資料會自動歸到「客戶」這個類型，之後可以在畫面上逐筆改成
   供應商／媒體／合作夥伴

### 13. 一人多重身分（人 ↔ 單位改成多對多）

1. Supabase 後台左側「SQL Editor」
2. 貼上 `supabase/sql/10_contact_affiliations.sql` 的全部內容，執行
3. 腳本會自動把每個聯絡人現有的公司、職稱、部門搬進新的 `contact_affiliations`
   表（標記為「主要身分」），再移除 `contacts` 上的舊欄位，不需要手動搬資料

### 14. 部署 GitHub Pages

1. 這個 repo 的「Settings」→ 左側選單「Pages」
2. 「Build and deployment」→ Source 選「Deploy from a branch」
3. Branch 選 `main`，資料夾選 `/ (root)`，按 Save
4. 等 1-2 分鐘，畫面會顯示網址，格式類似：
   `https://bigxreality.github.io/activity-management-system/`
5. 打開這個網址，用剛剛在 Supabase 建立的帳號登入即可

## 更新網頁內容

之後每次功能更新，就是把新版檔案上傳覆蓋掉這個 repo 裡舊的檔案，GitHub Pages 會在
幾分鐘內自動套用新版本，不需要額外操作。
