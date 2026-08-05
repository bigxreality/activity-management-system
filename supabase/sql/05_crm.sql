-- ============================================================
-- 批次5：CRM 客戶名單模組
-- 在 Supabase 專案的 SQL Editor 貼上執行一次即可（可重複執行）
-- ============================================================

-- ---------- 權重設定（管理員可在前端「權重設定」畫面調整，不用改程式碼） ----------
create table if not exists identity_weights (
  category text primary key,
  weight numeric not null
);
insert into identity_weights (category, weight) values
  ('軍人', 10), ('警察', 10), ('消防員', 8), ('政府官員', 9),
  ('民間企業', 3), ('學術機構', 3), ('一般民眾', 1), ('其他', 1)
on conflict (category) do nothing;

-- ---------- 名單（CRM 主檔） ----------
create table if not exists leads (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  company text,
  title text,
  contact_info text,
  source_exhibition_id uuid references exhibitions(id),
  identity_category text references identity_weights(category),
  department_relevance int check (department_relevance between 1 and 5),
  enthusiasm int check (enthusiasm between 1 and 5),
  close_probability int check (close_probability between 1 and 5),
  card_photo_url text,
  avatar_photo_url text,
  status text not null default '新名單' check (status in ('新名單','追蹤中','已報價','已成交','已流失')),
  deal_amount numeric,
  deal_date date,
  owner_id uuid references profiles(id),
  note text,
  created_at timestamptz default now()
);

-- ---------- 聯繫紀錄（子表） ----------
create table if not exists contact_logs (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references leads(id) on delete cascade,
  date date not null,
  contact_method text,
  summary text,
  next_follow_up_date date,
  created_at timestamptz default now()
);

-- ---------- 名單價值分數：用 view 算，權重表改了立即反映，不存成固定值 ----------
-- 名單價值分數 = 身份權重 × 部門相關度 × (積極度 + 成交機率感覺) ÷ 2
create or replace view leads_with_score
with (security_invoker = true) as
select l.*,
  (coalesce(w.weight, 1) * l.department_relevance * (l.enthusiasm + l.close_probability) / 2.0) as lead_score
from leads l
left join identity_weights w on w.category = l.identity_category;

-- ---------- RLS ----------
alter table identity_weights enable row level security;
alter table leads enable row level security;
alter table contact_logs enable row level security;

-- identity_weights：所有登入者可讀；只有 admin 可寫
drop policy if exists identity_weights_select on identity_weights;
create policy identity_weights_select on identity_weights for select to authenticated using (true);
drop policy if exists identity_weights_update on identity_weights;
create policy identity_weights_update on identity_weights for update to authenticated using (get_my_role() = 'admin') with check (get_my_role() = 'admin');
drop policy if exists identity_weights_insert on identity_weights;
create policy identity_weights_insert on identity_weights for insert to authenticated with check (get_my_role() = 'admin');
drop policy if exists identity_weights_delete on identity_weights;
create policy identity_weights_delete on identity_weights for delete to authenticated using (get_my_role() = 'admin');

-- leads：所有登入者可讀；admin/editor 可寫
drop policy if exists leads_select on leads;
create policy leads_select on leads for select to authenticated using (true);
drop policy if exists leads_insert on leads;
create policy leads_insert on leads for insert to authenticated with check (get_my_role() in ('admin', 'editor'));
drop policy if exists leads_update on leads;
create policy leads_update on leads for update to authenticated using (get_my_role() in ('admin', 'editor')) with check (get_my_role() in ('admin', 'editor'));
drop policy if exists leads_delete on leads;
create policy leads_delete on leads for delete to authenticated using (get_my_role() in ('admin', 'editor'));

-- contact_logs：同上
drop policy if exists contact_logs_select on contact_logs;
create policy contact_logs_select on contact_logs for select to authenticated using (true);
drop policy if exists contact_logs_insert on contact_logs;
create policy contact_logs_insert on contact_logs for insert to authenticated with check (get_my_role() in ('admin', 'editor'));
drop policy if exists contact_logs_update on contact_logs;
create policy contact_logs_update on contact_logs for update to authenticated using (get_my_role() in ('admin', 'editor')) with check (get_my_role() in ('admin', 'editor'));
drop policy if exists contact_logs_delete on contact_logs;
create policy contact_logs_delete on contact_logs for delete to authenticated using (get_my_role() in ('admin', 'editor'));

-- ---------- 名片照片/客戶頭像用的 photos bucket ----------
insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

drop policy if exists photos_select on storage.objects;
create policy photos_select on storage.objects for select
  to authenticated using (bucket_id = 'photos');

drop policy if exists photos_insert on storage.objects;
create policy photos_insert on storage.objects for insert
  to authenticated with check (bucket_id = 'photos' and public.get_my_role() in ('admin', 'editor'));

drop policy if exists photos_update on storage.objects;
create policy photos_update on storage.objects for update
  to authenticated using (bucket_id = 'photos' and public.get_my_role() in ('admin', 'editor'));

drop policy if exists photos_delete on storage.objects;
create policy photos_delete on storage.objects for delete
  to authenticated using (bucket_id = 'photos' and public.get_my_role() in ('admin', 'editor'));
