-- ============================================================
-- 批次5-1：CRM 模組重新設計
-- ============================================================
-- 這是破壞性變更：contacts 取代原本的 leads，interactions 取代原本的
-- contact_logs，資料結構完全不同、無法自動轉換。舊的 leads/contact_logs
-- 是這幾天才剛做出來的測試功能，直接砍掉重建。
-- 在 Supabase 專案的 SQL Editor 貼上執行一次即可。

drop view if exists leads_with_score;
drop table if exists contact_logs cascade;
drop table if exists leads cascade;

-- ---------- 感興趣產品清單（可在前端「產品管理」畫面增修，不寫死在程式碼） ----------
create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order int default 0,
  active boolean default true
);
insert into products (name, sort_order) values
  ('SUT BOX', 1), ('POLICE BOX', 2), ('AI Military Training', 3),
  ('UAV Training', 4), ('USV Training', 5), ('CQB Training', 6),
  ('Firearms Training', 7), ('Disaster Prevention Training', 8),
  ('XR Training Solution', 9), ('其他', 99)
on conflict (name) do nothing;

-- ---------- 公司主檔 ----------
create table if not exists companies (
  id uuid primary key default gen_random_uuid(),
  name_original text,
  name_english text,
  website text,
  email_domain text,
  country text,
  address_original text,
  address_english text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ---------- 聯絡人（CRM 主檔，取代 leads） ----------
create table if not exists contacts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id),
  name_original text,
  name_english text,
  department_original text,
  department_english text,
  title_original text,
  title_english text,
  country text,
  address_original text,
  address_english text,
  importance text not null default '未分類' check (importance in ('A', 'B', 'C', '未分類')),
  customer_type text,
  identity_category text references identity_weights(category),
  department_relevance int check (department_relevance between 1 and 5),
  enthusiasm int check (enthusiasm between 1 and 5),
  close_probability int check (close_probability between 1 and 5),
  avatar_photo_url text,
  owner_id uuid references profiles(id),
  status text not null default '新名單' check (status in ('新名單','追蹤中','已報價','已成交','已流失')),
  deal_amount numeric,
  deal_date date,
  note text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ---------- 聯絡方式（一個聯絡人可以有多筆） ----------
create table if not exists contact_methods (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references contacts(id) on delete cascade,
  type text not null,
  value_original text not null,
  value_normalized text,
  is_primary boolean default false,
  created_at timestamptz default now()
);

-- ---------- 名片掃描紀錄（批次5-2/5-3 才會實際用到，這批先建表） ----------
create table if not exists business_cards (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references contacts(id) on delete cascade,
  exhibition_id uuid references exhibitions(id),
  image_path text not null,
  image_hash text not null,
  raw_ocr_text text,
  recognition_json jsonb,
  detected_languages text[],
  ai_model text,
  recognition_status text not null default 'pending'
    check (recognition_status in ('pending', 'processing', 'done', 'failed')),
  recognition_error text,
  token_usage int,
  estimated_cost numeric,
  uploaded_by uuid references profiles(id),
  created_at timestamptz default now()
);
create unique index if not exists business_cards_hash_unique on business_cards(image_hash);

-- ---------- 展覽 × 聯絡人（多對多，同一人不同展覽疊加不覆蓋） ----------
create table if not exists event_contacts (
  id uuid primary key default gen_random_uuid(),
  exhibition_id uuid references exhibitions(id),
  contact_id uuid references contacts(id) on delete cascade,
  interested_products text[],
  onsite_notes text,
  next_action text,
  scanned_by uuid references profiles(id),
  created_at timestamptz default now(),
  unique (exhibition_id, contact_id)
);

-- ---------- 聯繫紀錄（取代 contact_logs） ----------
create table if not exists interactions (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references contacts(id) on delete cascade,
  exhibition_id uuid references exhibitions(id),
  interaction_type text,
  interaction_date date not null,
  content text,
  customer_needs text,
  next_action text,
  next_follow_up_date date,
  created_by uuid references profiles(id),
  created_at timestamptz default now()
);

-- ---------- 待辦事項 ----------
create table if not exists tasks (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references contacts(id) on delete cascade,
  exhibition_id uuid references exhibitions(id),
  title text not null,
  description text,
  due_date date,
  status text not null default '待處理' check (status in ('待處理', '進行中', '已完成')),
  assigned_to uuid references profiles(id),
  created_by uuid references profiles(id),
  created_at timestamptz default now()
);

-- ---------- 客戶自填表單暫存區（批次5-8 才會有實際頁面，這批先建表+權限） ----------
create table if not exists public_lead_submissions (
  id uuid primary key default gen_random_uuid(),
  exhibition_id uuid references exhibitions(id),
  name text,
  company text,
  title text,
  contact_info text,
  needs_note text,
  language text,
  status text not null default '待處理' check (status in ('待處理', '已轉入名單')),
  converted_contact_id uuid references contacts(id) on delete set null,
  submitted_at timestamptz default now()
);

-- ---------- 聯絡人價值分數：view 算，權重表改了立即反映 ----------
create or replace view contacts_with_score
with (security_invoker = true) as
select c.*,
  (coalesce(w.weight, 1) * c.department_relevance * (c.enthusiasm + c.close_probability) / 2.0) as contact_score
from contacts c
left join identity_weights w on w.category = c.identity_category;

-- ---------- RLS：一般業務表統一規則（SELECT 所有登入者；寫入 admin/editor） ----------
alter table products enable row level security;
alter table companies enable row level security;
alter table contacts enable row level security;
alter table contact_methods enable row level security;
alter table business_cards enable row level security;
alter table event_contacts enable row level security;
alter table interactions enable row level security;
alter table tasks enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['products','companies','contacts','contact_methods','business_cards','event_contacts','interactions','tasks']
  loop
    execute format('drop policy if exists %I_select on %I', t, t);
    execute format('create policy %I_select on %I for select to authenticated using (true)', t, t);
    execute format('drop policy if exists %I_insert on %I', t, t);
    execute format('create policy %I_insert on %I for insert to authenticated with check (get_my_role() in (''admin'', ''editor''))', t, t);
    execute format('drop policy if exists %I_update on %I', t, t);
    execute format('create policy %I_update on %I for update to authenticated using (get_my_role() in (''admin'', ''editor'')) with check (get_my_role() in (''admin'', ''editor''))', t, t);
    execute format('drop policy if exists %I_delete on %I', t, t);
    execute format('create policy %I_delete on %I for delete to authenticated using (get_my_role() in (''admin'', ''editor''))', t, t);
  end loop;
end $$;

-- ---------- public_lead_submissions：客戶免登入單向寫入，只有 editor/admin 能讀/審核 ----------
alter table public_lead_submissions enable row level security;

drop policy if exists public_lead_submissions_insert on public_lead_submissions;
create policy public_lead_submissions_insert on public_lead_submissions for insert
  to public with check (true);

drop policy if exists public_lead_submissions_select on public_lead_submissions;
create policy public_lead_submissions_select on public_lead_submissions for select
  to authenticated using (get_my_role() in ('admin', 'editor'));

drop policy if exists public_lead_submissions_update on public_lead_submissions;
create policy public_lead_submissions_update on public_lead_submissions for update
  to authenticated using (get_my_role() in ('admin', 'editor')) with check (get_my_role() in ('admin', 'editor'));
