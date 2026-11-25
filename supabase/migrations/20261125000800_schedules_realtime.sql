-- =============================================================================
-- 8/8 定时任务（pg_cron）和实时更新（Realtime）
-- 本机没有 pg_cron / Realtime 时自动跳过，不会报错。
-- pg_cron 用 UTC 时间：马来西亚时间 = UTC + 8
-- =============================================================================

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;

    -- 每天 00:15（马来西亚时间）：试用 / 订阅到期处理
    perform cron.schedule(
      'subscription-maintenance',
      '15 16 * * *',
      'select public.run_subscription_maintenance()'
    );

    -- 每月 1 号 08:00（马来西亚时间）：生成上个月的佣金草稿账单
    perform cron.schedule(
      'monthly-commission-invoices',
      '0 0 1 * *',
      'select public.generate_commission_invoices()'
    );
  else
    raise notice 'pg_cron 不可用，跳过定时任务';
  end if;
end;
$$;

-- 订单状态、通知用 Realtime 推到 App（RLS 照样生效，买家只收到自己的）
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.orders, public.order_status_events, public.notifications;
  else
    raise notice '没有 supabase_realtime publication，跳过';
  end if;
end;
$$;
