-- ============================================================
-- 批次4：費用明細附件（收據/發票）用的 Storage bucket 與權限規則
-- 在 Supabase 專案的 SQL Editor 貼上執行一次即可（可重複執行）
-- ============================================================

-- 建立私有 bucket。如果這個 insert 在你的專案權限下跑不過，改成手動在
-- 「Storage」頁面按「New bucket」，名稱填 attachments，Public 開關保持關閉即可，
-- 效果一樣，後面的 RLS policy 照樣套用。
insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

-- 所有登入者都能讀取（要能點開自己或同事上傳的附件連結）
drop policy if exists attachments_select on storage.objects;
create policy attachments_select on storage.objects for select
  to authenticated using (bucket_id = 'attachments');

-- 只有 admin/editor 能上傳，viewer 不能上傳檔案
drop policy if exists attachments_insert on storage.objects;
create policy attachments_insert on storage.objects for insert
  to authenticated with check (bucket_id = 'attachments' and public.get_my_role() in ('admin', 'editor'));

-- 更新/刪除同樣限 admin/editor（例如編輯費用時換掉附件）
drop policy if exists attachments_update on storage.objects;
create policy attachments_update on storage.objects for update
  to authenticated using (bucket_id = 'attachments' and public.get_my_role() in ('admin', 'editor'));

drop policy if exists attachments_delete on storage.objects;
create policy attachments_delete on storage.objects for delete
  to authenticated using (bucket_id = 'attachments' and public.get_my_role() in ('admin', 'editor'));
