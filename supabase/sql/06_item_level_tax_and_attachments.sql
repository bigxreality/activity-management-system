-- ============================================================
-- 品項欄位重構：附件改掛在品項上（不是單據），稅額改成用稅率自動算
-- 在 Supabase 專案的 SQL Editor 貼上執行一次即可
-- ============================================================

-- 稅率（%），手動輸入，例如填 5 代表 5%
alter table expense_items add column if not exists tax_rate numeric not null default 0;

-- 稅額改成自動算出來的（= 金額 × 稅率 ÷ 100），不再手動輸入
-- 先把舊的手動欄位丟掉，用同名字重建成 generated column
alter table expense_items drop column if exists tax_amount;
alter table expense_items add column tax_amount numeric generated always as (round(amount * tax_rate / 100, 2)) stored;

-- 附件改掛在品項上，一個品項可以有自己的收據/發票照片
alter table expense_items add column if not exists attachments text[] default '{}';

-- 單據層級不再需要附件欄位
alter table expense_documents drop column if exists attachments;

-- 攤平 view 要跟著改：twd_amount、tax_amount、attachments 都是品項層級的東西
create or replace view expense_items_expanded
with (security_invoker = true) as
select
  ei.id as item_id,
  ei.document_id,
  ei.item,
  ei.amount,
  ei.tax_rate,
  ei.tax_amount,
  (ei.amount * ed.rate) as twd_amount,
  ei.attachments,
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
  ed.note as document_note
from expense_items ei
join expense_documents ed on ed.id = ei.document_id;
