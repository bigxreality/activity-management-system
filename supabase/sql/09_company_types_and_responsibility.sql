-- ============================================================
-- 公司分類（客戶／供應商／媒體…）與聯絡人負責項目
-- ============================================================
-- 目的：CRM 不只放客戶，行銷也要能建立自己的供應商/媒體人脈網絡
-- （禮贈品採購、印刷廠、展場設計、新聞台、報社…），而且同一家公司的
-- 成員要能歸類在一起，看得出每個人各自負責什麼。
-- 在 Supabase 專案的 SQL Editor 貼上執行一次即可（可重複執行）。

-- ---------- 公司分類 ----------
-- 用 text + check 而不是 enum，之後要加類別直接改 check 條件就好，不用處理型別遷移
alter table companies add column if not exists company_type text not null default '客戶';
alter table companies drop constraint if exists companies_company_type_check;
alter table companies add constraint companies_company_type_check
  check (company_type in ('客戶', '供應商', '媒體', '合作夥伴', '其他'));

-- 產業/類別：自由填寫，前端用 datalist 給常見選項（禮贈品、印刷、展場設計、
-- 電視台、報社、雜誌…），但不限制只能選這些
alter table companies add column if not exists industry text;
alter table companies add column if not exists note text;

-- ---------- 聯絡人負責項目 ----------
-- 例如「負責禮贈品報價」「跑國防線記者」「採購決策者」，方便之後看一家公司的
-- 人員清單時知道各自的功能
alter table contacts add column if not exists responsibility text;

-- ---------- 讓聯絡人分數 view 跟著帶新欄位 ----------
-- 一定要先 drop 再建，不能用 create or replace：contacts 多了 responsibility 欄位之後，
-- select c.* 展開的欄位順序會變，contact_score 被往後擠，而 create or replace view
-- 不允許改變既有欄位的位置或名稱，會報 42P16 cannot change name of view column
drop view if exists contacts_with_score;

create or replace view contacts_with_score
with (security_invoker = true) as
select c.*,
  (coalesce(w.weight, 1) * c.department_relevance * (c.enthusiasm + c.close_probability) / 2.0) as contact_score
from contacts c
left join identity_weights w on w.category = c.identity_category;
