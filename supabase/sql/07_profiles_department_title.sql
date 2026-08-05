-- ============================================================
-- 批次3補充：使用者權限增加部門、職稱欄位
-- 職稱之後匯出請款單/差旅單時，申請人職稱直接從這裡帶出（批次6）
-- 在 Supabase 專案的 SQL Editor 貼上執行一次即可
-- ============================================================

alter table profiles add column if not exists department text;
alter table profiles add column if not exists title text;
