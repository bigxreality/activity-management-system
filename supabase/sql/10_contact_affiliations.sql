-- ============================================================
-- 一人多重身分：聯絡人 ↔ 單位改成多對多
-- ============================================================
-- 為什麼要改：原本 contacts.company_id 是單一欄位，一個人只能綁一家公司。
-- 實際上很多人同時是 A 公司總經理、B 公司總裁、C 公司共同創辦人；名片上也常
-- 出現扶輪社、獅子會這類社團身分。這些都是「同一個人的多段身分」，每段各自
-- 有自己的職稱、部門、負責項目，塞不進單一欄位，也不該塞進備註。
--
-- 改法：新增 contact_affiliations 中間表，職稱/部門/負責項目都掛在「這一段
-- 身分」上，而不是掛在人身上。社團就是 company_type = '社團組織' 的單位。
--
-- 這個腳本會自動把現有資料搬過去再移除舊欄位，可重複執行。
-- 在 Supabase 專案的 SQL Editor 貼上執行一次即可。

-- ---------- 公司類型多一個「社團組織」 ----------
alter table companies drop constraint if exists companies_company_type_check;
alter table companies add constraint companies_company_type_check
  check (company_type in ('客戶', '供應商', '媒體', '合作夥伴', '社團組織', '其他'));

-- ---------- 聯絡人的每一段身分 ----------
-- company_id 允許為空：有些人名片上只有職稱沒有單位，或單位還沒建檔，
-- 這種情況也要能保留他的職稱，不能因為沒有公司就整段資料不見。
create table if not exists contact_affiliations (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references contacts(id) on delete cascade,
  company_id uuid references companies(id) on delete cascade,
  title_original text,
  title_english text,
  department_original text,
  department_english text,
  responsibility text,
  is_primary boolean not null default false,
  created_at timestamptz default now()
);

-- 同一個人在同一個單位只會有一段身分（company_id 為 null 的不受此限，
-- Postgres 的 unique 把多個 null 視為互不相同）
create unique index if not exists contact_affiliations_unique
  on contact_affiliations(contact_id, company_id);

-- ---------- 把現有資料搬進新表 ----------
-- 只在舊欄位還存在時執行，這樣腳本重跑第二次不會出錯
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'contacts' and column_name = 'company_id'
  ) then
    execute $mig$
      insert into contact_affiliations
        (contact_id, company_id, title_original, title_english,
         department_original, department_english, responsibility, is_primary)
      select c.id, c.company_id, c.title_original, c.title_english,
             c.department_original, c.department_english, c.responsibility, true
      from contacts c
      where c.company_id is not null
         or nullif(trim(coalesce(c.title_original, '')), '') is not null
         or nullif(trim(coalesce(c.title_english, '')), '') is not null
         or nullif(trim(coalesce(c.department_original, '')), '') is not null
         or nullif(trim(coalesce(c.department_english, '')), '') is not null
      on conflict do nothing
    $mig$;
  end if;
end $$;

-- ---------- 移除搬走的舊欄位 ----------
-- view 依賴 contacts.*，要先拆掉才能改欄位，改完再重建
drop view if exists contacts_with_score;

alter table contacts drop column if exists company_id;
alter table contacts drop column if exists title_original;
alter table contacts drop column if exists title_english;
alter table contacts drop column if exists department_original;
alter table contacts drop column if exists department_english;
alter table contacts drop column if exists responsibility;

create or replace view contacts_with_score
with (security_invoker = true) as
select c.*,
  (coalesce(w.weight, 1) * c.department_relevance * (c.enthusiasm + c.close_probability) / 2.0) as contact_score
from contacts c
left join identity_weights w on w.category = c.identity_category;

-- ---------- RLS：跟其他業務表同一套規則 ----------
alter table contact_affiliations enable row level security;

drop policy if exists contact_affiliations_select on contact_affiliations;
create policy contact_affiliations_select on contact_affiliations for select
  to authenticated using (true);
drop policy if exists contact_affiliations_insert on contact_affiliations;
create policy contact_affiliations_insert on contact_affiliations for insert
  to authenticated with check (get_my_role() in ('admin', 'editor'));
drop policy if exists contact_affiliations_update on contact_affiliations;
create policy contact_affiliations_update on contact_affiliations for update
  to authenticated using (get_my_role() in ('admin', 'editor')) with check (get_my_role() in ('admin', 'editor'));
drop policy if exists contact_affiliations_delete on contact_affiliations;
create policy contact_affiliations_delete on contact_affiliations for delete
  to authenticated using (get_my_role() in ('admin', 'editor'));
