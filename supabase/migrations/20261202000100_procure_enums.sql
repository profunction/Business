-- =============================================================================
-- 第八步（准备）：公司采购要用的旧枚举新值（docs/08-procurement-spec.md 3.1 节最后一段）
-- 枚举加的新值要等这个交易提交后才能用，所以单独放一个迁移，
-- 下一个迁移（20261202000200_company_accounts.sql）才用它。
--   order_source    + procurement（采购单的订单，第 2 期才会建）
--   payer_type      + company（公司付公司方案）
--   payment_purpose + company_plan（reference_id = company_invoices.id）
-- =============================================================================

alter type public.order_source add value if not exists 'procurement';
alter type public.payer_type add value if not exists 'company';
alter type public.payment_purpose add value if not exists 'company_plan';
