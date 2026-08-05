# 活動管理系統

公司展覽/活動的費用管理工具。前端是純 HTML/JS（放在這個 repo，用 GitHub Pages 發布），
資料儲存在 **Supabase**（Postgres + Auth + Storage + Edge Functions）。

> 這個專案原本是 Google Sheet + Apps Script 架構，因為 Apps Script 的部署模型太反直覺
> （`/dev` vs `/exec` 網址搞混、CORS 要用 `text/plain` 繞過預檢請求、改權限要重新部署
> 版本才會生效……）反覆卡關，已經整個換成 Supabase。

## 目前狀態

- ✅ 費用明細 / 展覽總覽 / 儀表板（Supabase 版，含台銀歷史匯率查詢、PWA 基礎架構）
- ⏳ 權限系統細節（viewer 隱藏按鈕、管理員的使用者管理畫面）— 下一階段
- ⏳ 附件上傳（收據/票根，存進 Supabase Storage）— 下一階段
- ⏳ CRM 客戶名單模組 — 下一階段
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
- `supabase/functions/bot-rate/` — 台灣銀行歷史匯率查詢的 Supabase Edge Function，
  取代原本 Apps Script 的 `getBotRate`。

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

### 5. 部署 GitHub Pages

1. 這個 repo 的「Settings」→ 左側選單「Pages」
2. 「Build and deployment」→ Source 選「Deploy from a branch」
3. Branch 選 `main`，資料夾選 `/ (root)`，按 Save
4. 等 1-2 分鐘，畫面會顯示網址，格式類似：
   `https://bigxreality.github.io/activity-management-system/`
5. 打開這個網址，用剛剛在 Supabase 建立的帳號登入即可

## 更新網頁內容

之後每次功能更新，就是把新版檔案上傳覆蓋掉這個 repo 裡舊的檔案，GitHub Pages 會在
幾分鐘內自動套用新版本，不需要額外操作。
