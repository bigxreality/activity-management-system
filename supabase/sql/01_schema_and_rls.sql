-- ============================================================
-- 活動管理系統 - Supabase 初始化 SQL（批次2：profiles / exhibitions / expenses）
-- 在 Supabase 專案的 SQL Editor 貼上、執行一次即可（可重複執行，都有 if not exists / or replace 防呆）
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- profiles：對應 auth.users，決定角色 ----------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  name text not null,
  role text not null default 'viewer' check (role in ('admin', 'editor', 'viewer')),
  created_at timestamptz default now()
);

-- 新的 auth 帳號建立時自動帶一筆 profiles（預設 viewer）。
-- 正確角色（admin/editor）要靠下方「02_set_initial_roles.sql」一次性設定，
-- 之後管理員也可以在前端「使用者管理」畫面調整（批次3）。
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)),
    'viewer'
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- 目前登入者的角色，所有 RLS policy 都靠這個函式判斷
create or replace function get_my_role()
returns text as $$
  select role from public.profiles where id = auth.uid();
$$ language sql stable security definer set search_path = public;

-- ---------- exhibitions（展覽總覽） ----------
create table if not exists exhibitions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  budget numeric not null default 0,
  country text,
  year int,
  series text,
  note text,
  created_at timestamptz default now()
);

-- ---------- expenses（費用明細） ----------
create table if not exists expenses (
  id uuid primary key default gen_random_uuid(),
  exhibition_id uuid references exhibitions(id),
  date date not null,
  category text not null,
  expense_type text not null check (expense_type in ('個人', '公用')),
  applicant_id uuid references profiles(id),
  item text not null,
  vendor text,
  currency text not null default 'TWD',
  amount numeric not null,
  rate numeric not null default 1,
  twd_amount numeric generated always as (amount * rate) stored,
  payment_method text,
  invoice text,
  note text,
  attachments text[] default '{}',
  created_by uuid references profiles(id),
  created_at timestamptz default now()
);

-- ---------- RLS ----------
alter table profiles enable row level security;
alter table exhibitions enable row level security;
alter table expenses enable row level security;

-- profiles：所有登入者可讀（前端要知道自己是什麼角色），只有 admin 可寫
drop policy if exists profiles_select on profiles;
create policy profiles_select on profiles for select
  to authenticated using (true);

drop policy if exists profiles_update on profiles;
create policy profiles_update on profiles for update
  to authenticated using (get_my_role() = 'admin') with check (get_my_role() = 'admin');

drop policy if exists profiles_delete on profiles;
create policy profiles_delete on profiles for delete
  to authenticated using (get_my_role() = 'admin');

-- exhibitions：所有登入者可讀；admin/editor 可寫，viewer 不能寫
drop policy if exists exhibitions_select on exhibitions;
create policy exhibitions_select on exhibitions for select
  to authenticated using (true);

drop policy if exists exhibitions_insert on exhibitions;
create policy exhibitions_insert on exhibitions for insert
  to authenticated with check (get_my_role() in ('admin', 'editor'));

drop policy if exists exhibitions_update on exhibitions;
create policy exhibitions_update on exhibitions for update
  to authenticated using (get_my_role() in ('admin', 'editor')) with check (get_my_role() in ('admin', 'editor'));

drop policy if exists exhibitions_delete on exhibitions;
create policy exhibitions_delete on exhibitions for delete
  to authenticated using (get_my_role() in ('admin', 'editor'));

-- expenses：同上
drop policy if exists expenses_select on expenses;
create policy expenses_select on expenses for select
  to authenticated using (true);

drop policy if exists expenses_insert on expenses;
create policy expenses_insert on expenses for insert
  to authenticated with check (get_my_role() in ('admin', 'editor'));

drop policy if exists expenses_update on expenses;
create policy expenses_update on expenses for update
  to authenticated using (get_my_role() in ('admin', 'editor')) with check (get_my_role() in ('admin', 'editor'));

drop policy if exists expenses_delete on expenses;
create policy expenses_delete on expenses for delete
  to authenticated using (get_my_role() in ('admin', 'editor'));
