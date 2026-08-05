-- ============================================================
-- 批次2修訂：費用明細改成「單據 + 品項」兩層結構
-- ============================================================
-- 這是破壞性變更：會刪除舊的 expenses 表（Eric 已確認裡面只是測試資料，
-- 可以直接清空重建，不需要搬移舊資料）。
-- 在 Supabase 專案的 SQL Editor 貼上執行一次即可。

drop table if exists expenses cascade;

-- ---------- 付款對象主檔 ----------
create table if not exists payees (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  bank_short_name text,
  bank_code text,
  branch text,
  check_no text,
  bank_account text,
  account_holder text,
  swift_code text,
  note text,
  created_at timestamptz default now()
);

-- ---------- 費用單據（header，一張發票/收據一筆） ----------
create table if not exists expense_documents (
  id uuid primary key default gen_random_uuid(),
  exhibition_id uuid references exhibitions(id),
  date date not null,
  category text not null,
  expense_type text not null check (expense_type in ('個人', '公用')),
  applicant_id uuid references profiles(id) not null,
  vendor text,
  route_from text,
  route_to text,
  currency text not null default 'TWD',
  rate numeric not null default 1,
  payment_method text,
  invoice_no text,
  payee_id uuid references payees(id),
  payment_terms text,
  expected_payment_date date,
  note text,
  attachments text[] default '{}',
  created_by uuid references profiles(id),
  created_at timestamptz default now()
);

-- ---------- 費用品項（一張單據可以有多筆） ----------
create table if not exists expense_items (
  id uuid primary key default gen_random_uuid(),
  document_id uuid references expense_documents(id) on delete cascade,
  item text not null,
  amount numeric not null,
  tax_amount numeric default 0,
  sort_order int default 0,
  created_at timestamptz default now()
);

-- ---------- 攤平 view：報表/匯出/儀表板都查這個，不要自己重新 join ----------
-- security_invoker = true：讓這個 view 遵循查詢者自己的 RLS 權限，不是 view
-- 擁有者的權限（Postgres 15 / Supabase 的已知眉角，不加這個可能會繞過 RLS）。
create or replace view expense_items_expanded
with (security_invoker = true) as
select
  ei.id as item_id,
  ei.document_id,
  ei.item,
  ei.amount,
  ei.tax_amount,
  (ei.amount * ed.rate) as twd_amount,
  ed.exhibition_id,
  ed.date,
  ed.category,
  ed.expense_type,
  ed.applicant_id,
  ed.vendor,
  ed.route_from,
  ed.route_to,
  ed.currency,
  ed.rate,
  ed.payment_method,
  ed.invoice_no,
  ed.payee_id,
  ed.payment_terms,
  ed.expected_payment_date,
  ed.note as document_note,
  ed.attachments
from expense_items ei
join expense_documents ed on ed.id = ei.document_id;

-- ---------- RLS ----------
alter table payees enable row level security;
alter table expense_documents enable row level security;
alter table expense_items enable row level security;

-- payees：所有登入者可讀；admin/editor 可寫
drop policy if exists payees_select on payees;
create policy payees_select on payees for select to authenticated using (true);
drop policy if exists payees_insert on payees;
create policy payees_insert on payees for insert to authenticated with check (get_my_role() in ('admin', 'editor'));
drop policy if exists payees_update on payees;
create policy payees_update on payees for update to authenticated using (get_my_role() in ('admin', 'editor')) with check (get_my_role() in ('admin', 'editor'));
drop policy if exists payees_delete on payees;
create policy payees_delete on payees for delete to authenticated using (get_my_role() in ('admin', 'editor'));

-- expense_documents：所有登入者可讀；admin/editor 可寫
drop policy if exists expense_documents_select on expense_documents;
create policy expense_documents_select on expense_documents for select to authenticated using (true);
drop policy if exists expense_documents_insert on expense_documents;
create policy expense_documents_insert on expense_documents for insert to authenticated with check (get_my_role() in ('admin', 'editor'));
drop policy if exists expense_documents_update on expense_documents;
create policy expense_documents_update on expense_documents for update to authenticated using (get_my_role() in ('admin', 'editor')) with check (get_my_role() in ('admin', 'editor'));
drop policy if exists expense_documents_delete on expense_documents;
create policy expense_documents_delete on expense_documents for delete to authenticated using (get_my_role() in ('admin', 'editor'));

-- expense_items：同上
drop policy if exists expense_items_select on expense_items;
create policy expense_items_select on expense_items for select to authenticated using (true);
drop policy if exists expense_items_insert on expense_items;
create policy expense_items_insert on expense_items for insert to authenticated with check (get_my_role() in ('admin', 'editor'));
drop policy if exists expense_items_update on expense_items;
create policy expense_items_update on expense_items for update to authenticated using (get_my_role() in ('admin', 'editor')) with check (get_my_role() in ('admin', 'editor'));
drop policy if exists expense_items_delete on expense_items;
create policy expense_items_delete on expense_items for delete to authenticated using (get_my_role() in ('admin', 'editor'));
