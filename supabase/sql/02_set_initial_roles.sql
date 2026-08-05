-- ============================================================
-- 一次性設定：把定案的五位使用者角色寫進 profiles
-- ============================================================
-- 執行順序很重要：
-- 1. 先跑完 01_schema_and_rls.sql
-- 2. 在 Supabase 後台「Authentication」頁面手動建立/邀請這五個 Email 帳號
--    （建立帳號時會自動觸發 handle_new_user()，在 profiles 生一筆 role='viewer' 的資料）
-- 3. 最後才執行這個檔案，把角色改成定案的樣子
-- 這個腳本用 email 比對，不需要知道 auth.users 的 uuid，可以重複執行。
-- ============================================================

update profiles set role = 'admin'  where email = 'eric.chen@gptt.com.tw';
update profiles set role = 'editor' where email = 'grace@gptt.com.tw';
update profiles set role = 'editor' where email = 'lina.liu@gptt.com.tw';
update profiles set role = 'editor' where email = 'albert.chen@gptt.com.tw';
update profiles set role = 'viewer' where email = 'hanson@gptt.com.tw';

-- 執行完可以用這個查一下結果對不對
select email, name, role from profiles order by role, email;
