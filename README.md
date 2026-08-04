# 活動管理系統

公司展覽/活動的費用管理工具，資料儲存在 Google Sheet，透過 Google Apps Script 當後端 API，
前端是純 HTML/JS（放在這個 repo，用 GitHub Pages 發布）。

## 目前狀態（Phase 1）

- ✅ 費用明細 / 展覽總覽 / 儀表板（含台銀歷史匯率自動查詢）
- ⏳ 權限系統（管理員/編輯者/檢視者，Google 帳號登入）— 下一階段
- ⏳ CRM 客戶名單模組 — 下一階段
- ⏳ 附件上傳（收據/票根）— 下一階段
- ⏳ 活動照片模組 — 下一階段
- ⏳ 請款單／差旅報告單匯出（保留公司原本 Excel 格式）— 下一階段

## 檔案說明

- `index.html` — 前端網頁本體，GitHub Pages 會自動把它當首頁
- `AppsScript-後端程式碼.gs` — 後端程式碼，**不是放在這個 repo 裡執行的**，是要貼到 Google Apps Script
  編輯器裡的（放在這裡純粹是留存版本紀錄、方便追蹤異動）

## 部署 GitHub Pages（第一次設定）

1. 這個 repo 的「Settings」→ 左側選單「Pages」
2. 「Build and deployment」→ Source 選「Deploy from a branch」
3. Branch 選 `main`，資料夾選 `/ (root)`，按 Save
4. 等 1-2 分鐘，畫面會顯示網址，格式類似：
   `https://bigxreality.github.io/activity-management-system/`
5. 打開這個網址，右上角應該會自動顯示「已連線」（因為 `index.html` 裡已經寫死了
   Google Apps Script 的網址）

## 後端設定（Google Sheet + Apps Script）

後端已經部署好，網址寫死在 `index.html` 裡的 `DEFAULT_APPS_SCRIPT_URL`。如果要換一個新的
Google Sheet 或重新部署：

1. 開一個 Google 試算表 → 擴充功能 → Apps Script
2. 貼上 `AppsScript-後端程式碼.gs` 的內容並存檔
3. 執行一次 `setupSheets` 函式並授權
4. 部署 → 新增部署作業 → 網頁應用程式 → 存取權設定依需求（目前為「任何人」，
   下一階段加權限系統後會改成「限 Google 帳戶」）
5. 把新的 `/exec` 網址更新到 `index.html` 的 `DEFAULT_APPS_SCRIPT_URL`，重新上傳到這個 repo

## 更新網頁內容

之後每次功能更新，就是把新版 `index.html` 上傳覆蓋掉這個 repo 裡舊的檔案（GitHub 網頁
介面直接拖曳上傳、選擇覆蓋原檔案即可），GitHub Pages 會在幾分鐘內自動套用新版本，
不需要額外操作。
