-- 第四步加固：price_list_runs、reserve_price_list_run（用量 / 占位）、price_list_imports 的保护、
-- fail_stuck_price_list_imports（卡住的导入）、release_notification、定时任务、权限
begin;
\ir _helpers.psql
select plan(211);
select tests.setup_world();

-- W4（待审核）加一个员工（staff）：测「还没审核的用量比较少」，也测 staff 一样算成员
\set seller4 'aaaaaaaa-0000-4000-8000-000000000014'
insert into auth.users (id, phone) values (:'seller4', '60111000014');
update public.profiles set role = 'seller' where id = :'seller4';
insert into public.wholesaler_members (wholesaler_id, user_id, member_role) values (tests.uid('W4'), :'seller4', 'staff');

-- ---------- 这个文件用的小工具 ----------

-- 用 postgres 身份建一份导入（绕过 RLS 和保护，方便准备测试数据）；p_age = 多久以前建的（也是最后改的时间）
create function tests.new_import(
  p_wholesaler text,
  p_status public.import_status default 'processing',
  p_ai_raw jsonb default null,
  p_age interval default '0 seconds'
) returns uuid language sql as $$
  insert into public.price_list_imports (wholesaler_id, file_path, file_type, status, ai_raw, created_at, updated_at)
  values (tests.uid(p_wholesaler), tests.uid(p_wholesaler) || '/' || gen_random_uuid() || '.jpg', 'image',
          p_status, p_ai_raw, now() - p_age, now() - p_age)
  returning id;
$$;

-- 建一份新的导入，马上占位（用量测试用）
create function tests.try_reserve(p_wholesaler text, p_user uuid) returns jsonb language sql as $$
  select public.reserve_price_list_run(tests.new_import(p_wholesaler), p_user, gen_random_uuid());
$$;

-- 以前跑过几次（p_ages：多久以前）
create function tests.add_runs(p_wholesaler text, p_ages interval[]) returns void language sql as $$
  insert into public.price_list_runs (wholesaler_id, run_id, created_at)
  select tests.uid(p_wholesaler), gen_random_uuid(), now() - t.a from unnest(p_ages) as t(a);
$$;

-- Edge Function 用 secret key 连进来的身份（PostgREST 的 service_role）
create function tests.login_as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform set_config('role', 'service_role', true);
end;
$$;

-- 批发商（App）新增一份 W1 的导入，可以多填 / 改几栏；回传错误「代码:detail」，没错就 null
create function tests.app_insert(p_extra jsonb) returns text language plpgsql as $$
declare
  v jsonb := jsonb_build_object(
    'wholesaler_id', tests.uid('W1'),
    'file_path', tests.uid('W1') || '/' || gen_random_uuid() || '.jpg',
    'file_type', 'image',
    'status', 'processing') || p_extra;
begin
  return tests.error_of(format(
    'insert into public.price_list_imports (%s) select %s from jsonb_populate_record(null::public.price_list_imports, %L) r',
    (select string_agg(quote_ident(k), ', ' order by k) from jsonb_object_keys(v) as t(k)),
    (select string_agg('r.' || quote_ident(k), ', ' order by k) from jsonb_object_keys(v) as t(k)),
    v));
end;
$$;

-- 执行一句 SQL，回传改了几行
create function tests.row_count(p_sql text) returns int language plpgsql as $$
declare
  n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- 跟 new_import / try_reserve 一样，但批发商用 id（register_wholesaler 新建的、测试里另外建的）
create function tests.new_import_for(p_wholesaler uuid) returns uuid language sql as $$
  insert into public.price_list_imports (wholesaler_id, file_path, file_type)
  values (p_wholesaler, p_wholesaler || '/' || gen_random_uuid() || '.jpg', 'image')
  returning id;
$$;
create function tests.try_reserve_for(p_wholesaler uuid, p_user uuid) returns jsonb language sql as $$
  select public.reserve_price_list_run(tests.new_import_for(p_wholesaler), p_user, gen_random_uuid());
$$;

-- =============================================================================
-- 权限
-- =============================================================================
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.price_list_runs'::regclass), 'price_list_runs 开着 RLS');
select is(
  (select count(*)::int from pg_policies where schemaname = 'public' and tablename = 'price_list_runs'),
  0, 'price_list_runs 没有任何规则（只给服务器）'
);
select is(has_table_privilege('authenticated', 'public.price_list_runs', 'select,insert,update,delete'), false,
  '登录用户对 price_list_runs 没有任何权限');
select is(has_table_privilege('anon', 'public.price_list_runs', 'select,insert,update,delete'), false,
  'anon 对 price_list_runs 没有任何权限');
select ok(has_table_privilege('service_role', 'public.price_list_runs', 'select'), 'service_role 读得到 price_list_runs');

\set new_fns '''_price_list_run_limits'', ''_try_timestamptz'', ''reserve_price_list_run'', ''price_list_imports_guard'', ''fail_stuck_price_list_imports'', ''_claim_notifications_batch'', ''claim_notifications'', ''complete_notification'', ''release_notification'', ''_schedule_seller_hardening_jobs'''
select is(
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '')
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (:new_fns)
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('public', p.oid, 'execute'))),
  '', '新函数：登录用户、anon、public 一个都不能调用'
);
select is(
  (select string_agg(p.proname, ',' order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (:new_fns) and has_function_privilege('service_role', p.oid, 'execute')),
  '_price_list_run_limits,_try_timestamptz,claim_notifications,complete_notification,fail_stuck_price_list_imports,release_notification,reserve_price_list_run',
  'service_role 只能调用服务器用的函数（trigger 函数、建定时任务的、旧的 claim_notifications 不行）'
);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (:new_fns)),
  10, '（上面检查的函数都存在）'
);
select is(
  (select string_agg(p.oid::regprocedure::text, ', ' order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('claim_notifications', 'complete_notification', 'release_notification')),
  'claim_notifications(integer,uuid), '
  || 'complete_notification(uuid,notification_status,notification_channel,text,text,boolean,uuid), '
  || 'release_notification(uuid,uuid)',
  '通知的三个函数都多了 claim id（旧的参数版本删掉了，不会重载混乱）'
);
select ok(has_function_privilege('authenticated', 'public.register_wholesaler(text, uuid, uuid, text, text, text)', 'execute'),
  'register_wholesaler 照样给 App 叫（改过之后权限没变）');

select tests.new_import('W1') as imp_priv \gset
select tests.login_as(tests.uid('seller1'));
select throws_ok(format('select public.reserve_price_list_run(%L, %L, %L)', :'imp_priv', tests.uid('seller1'), gen_random_uuid()),
  '42501', null, '批发商不能自己占位（绕过用量）');
select throws_ok(format('select public.release_notification(%L)', gen_random_uuid()), '42501', null, '批发商不能放回通知');
select throws_ok('select public.fail_stuck_price_list_imports()', '42501', null, '批发商不能跑「卡住的导入」');
select throws_ok('select count(*) from public.price_list_runs', '42501', null, '批发商读不到用量记录');
select throws_ok(
  format('insert into public.price_list_runs (wholesaler_id, run_id) values (%L, %L)', tests.uid('W1'), gen_random_uuid()),
  '42501', null, '批发商不能自己写用量记录'
);
select tests.login_as(tests.uid('admin'));
select throws_ok(format('select public.reserve_price_list_run(%L, %L, %L)', :'imp_priv', tests.uid('admin'), gen_random_uuid()),
  '42501', null, '客服也不能直接占位（只给服务器）');
-- 就算有 service_role 的权限，身份是普通用户也不行（函数第一行检查）
do $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', tests.uid('seller1'), 'role', 'authenticated')::text, true);
  perform set_config('role', 'service_role', true);
end;
$$;
select throws_ok(format('select public.reserve_price_list_run(%L, %L, %L)', :'imp_priv', tests.uid('seller1'), gen_random_uuid()),
  '42501', 'NOT_ALLOWED', 'reserve_price_list_run 自己检查是不是服务器');
select throws_ok(format('select public.release_notification(%L)', gen_random_uuid()), '42501', 'NOT_ALLOWED',
  'release_notification 自己检查是不是服务器');
select throws_ok('select public.fail_stuck_price_list_imports()', '42501', 'NOT_ALLOWED',
  'fail_stuck_price_list_imports 自己检查是不是服务器');
select tests.logout();
select is((select ai_raw from public.price_list_imports where id = :'imp_priv'), null, '（被挡下来的没有占位）');

-- =============================================================================
-- reserve_price_list_run：每一种结果
-- =============================================================================
select tests.new_import('W1') as imp_a \gset
-- 客服手动改回 processing 的导入可能还留着旧的错误
update public.price_list_imports set error_message = 'OLD_ERROR' where id = :'imp_a';
\set run_a '77777777-0000-4000-8000-000000000001'
\set run_b '77777777-0000-4000-8000-000000000002'

select is(public.reserve_price_list_run(gen_random_uuid(), tests.uid('seller1'), gen_random_uuid()),
  '{"result": "not_found"}'::jsonb, '没有这份导入 → not_found');
select is(public.reserve_price_list_run(:'imp_a', tests.uid('seller2'), gen_random_uuid()),
  '{"result": "not_member"}'::jsonb, '别家批发商的人 → not_member');
select is(public.reserve_price_list_run(:'imp_a', tests.uid('buyer1'), gen_random_uuid()),
  '{"result": "not_member"}'::jsonb, '买家 → not_member');
select is(public.reserve_price_list_run(:'imp_a', null, gen_random_uuid()),
  '{"result": "not_member"}'::jsonb, '没有用户 → not_member');
select throws_ok(format('select public.reserve_price_list_run(%L, %L, null)', :'imp_a', tests.uid('seller1')),
  'P0001', 'INVALID_RUN_ID', '没有 run_id → INVALID_RUN_ID');
select ok(
  (select ai_raw is null and error_message = 'OLD_ERROR' from public.price_list_imports where id = :'imp_a')
  and (select count(*) from public.price_list_runs) = 0,
  '被拒绝的不改导入、不算次数'
);

-- 真的用 service_role 身份叫（Edge Function 就是这样）
select tests.login_as_service();
select public.reserve_price_list_run(:'imp_a', tests.uid('seller1'), :'run_a') as res_a \gset
select tests.logout();
select is(
  :'res_a'::jsonb - 'claimed_at',
  jsonb_build_object(
    'result', 'ok', 'run_id', :'run_a'::uuid, 'wholesaler_id', tests.uid('W1'), 'wholesaler_status', 'active',
    'import_id', :'imp_a'::uuid, 'file_type', 'image',
    'file_path', (select file_path from public.price_list_imports where id = :'imp_a')),
  'service_role 占位成功：回传 run_id、批发商和它的状态、档案'
);
select is((:'res_a'::jsonb ->> 'claimed_at')::timestamptz, now(), 'claimed_at 是数据库的现在时间');
select is(
  (select ai_raw from public.price_list_imports where id = :'imp_a'),
  jsonb_build_object('version', 1, 'state', 'running', 'run_id', :'run_a'::uuid, 'claimed_at', now(),
                     'claimed_by', tests.uid('seller1')),
  'ai_raw 记下占位：version、state = running、run_id、claimed_at、claimed_by'
);
select is((select error_message from public.price_list_imports where id = :'imp_a'), null, '旧的 error_message 清掉');
select is(
  (select wholesaler_id || '/' || import_id || '/' || user_id || '/' || (created_at = now())
   from public.price_list_runs where run_id = :'run_a'),
  tests.uid('W1') || '/' || :'imp_a' || '/' || tests.uid('seller1') || '/true',
  '记了一笔 price_list_runs（批发商、导入、谁叫的、时间）'
);
select throws_ok(format('select public.reserve_price_list_run(%L, %L, %L)', tests.new_import('W1'), tests.uid('seller1'), :'run_a'),
  'P0001', 'RUN_ID_USED', '同一个 run_id 不能用两次');

select is(public.reserve_price_list_run(:'imp_a', tests.uid('seller1'), gen_random_uuid()),
  '{"result": "already_running"}'::jsonb, '有人在跑 → already_running');
update public.price_list_imports set ai_raw = jsonb_set(ai_raw, '{claimed_at}', to_jsonb(now() - interval '9 minutes'))
where id = :'imp_a';
select is(public.reserve_price_list_run(:'imp_a', tests.uid('admin'), gen_random_uuid()),
  '{"result": "already_running"}'::jsonb, '9 分钟前开始跑的：还当成在跑');
select is((select count(*)::int from public.price_list_runs where import_id = :'imp_a'), 1, 'already_running 不算次数');

update public.price_list_imports set ai_raw = jsonb_set(ai_raw, '{claimed_at}', to_jsonb(now() - interval '11 minutes'))
where id = :'imp_a';
select is(public.reserve_price_list_run(:'imp_a', tests.uid('seller1'), :'run_b') ->> 'result', 'ok',
  '在跑超过 10 分钟（worker 死掉了）→ 可以重新占位');
select is(
  (select (ai_raw ->> 'run_id') || '/' || ((ai_raw ->> 'claimed_at')::timestamptz = now()) from public.price_list_imports where id = :'imp_a'),
  :'run_b' || '/true', '重新占位：换成新的 run_id、claimed_at'
);
select is((select count(*)::int from public.price_list_runs where import_id = :'imp_a'), 2, '重新占位也算一次');
update public.price_list_imports set ai_raw = '{"version": 1, "state": "running", "claimed_at": "not a time"}'
where id = :'imp_a';
select is(public.reserve_price_list_run(:'imp_a', tests.uid('seller1'), gen_random_uuid()) ->> 'result', 'ok',
  'claimed_at 读不懂：当成死掉了，可以重新占位');
-- W1 10 分钟内已经跑了 3 次（都是「现在」）：第 4 次要等最旧那次过 10 分钟
select is(tests.try_reserve('W1', tests.uid('seller1')),
  '{"result": "quota", "window": "burst", "retry_after_sec": 600}'::jsonb,
  '10 分钟内第 4 次 → quota burst，600 秒后再试');

select tests.new_import('W2', 'review') as imp_r \gset
select is(public.reserve_price_list_run(:'imp_r', tests.uid('seller2'), gen_random_uuid()),
  '{"result": "not_processing", "status": "review"}'::jsonb, '不是 processing → not_processing（附上现在的状态）');

update public.wholesalers set status = 'suspended' where id = tests.uid('W3');
select tests.new_import('W3') as imp_s \gset
select is(public.reserve_price_list_run(:'imp_s', tests.uid('seller3'), gen_random_uuid()),
  '{"result": "suspended"}'::jsonb, '停权的批发商 → suspended');
select is(public.reserve_price_list_run(:'imp_s', tests.uid('seller1'), gen_random_uuid()),
  '{"result": "not_member"}'::jsonb, '不是成员先回 not_member（不透露别家停权）');
select ok(
  (select ai_raw is null from public.price_list_imports where id = :'imp_s')
  and not exists (select 1 from public.price_list_runs where wholesaler_id = tests.uid('W3')),
  '停权的没有占位、不算次数'
);

select is(tests.try_reserve('W2', tests.uid('admin')) ->> 'result', 'ok', '客服可以代批发商叫（算这家批发商的次数）');
select is(
  (select r ->> 'result' || '/' || (r ->> 'wholesaler_status') from (select tests.try_reserve('W4', :'seller4'::uuid) as r) x),
  'ok/pending', '待审核批发商的员工（staff）也可以叫'
);

-- ---------- 用量：审核通过（active）3 / 10 / 30 ----------
delete from public.price_list_runs where wholesaler_id = tests.uid('W2');
select tests.add_runs('W2', array['9 minutes', '5 minutes']::interval[]);
select is(tests.try_reserve('W2', tests.uid('seller2')) ->> 'result', 'ok', '10 分钟内第 3 次：可以');
select is(tests.try_reserve('W2', tests.uid('seller2')),
  '{"result": "quota", "window": "burst", "retry_after_sec": 60}'::jsonb,
  '10 分钟内第 4 次 → burst；最旧那次（9 分钟前）1 分钟后离开');
select is((select count(*)::int from public.price_list_runs where wholesaler_id = tests.uid('W2')), 3, '被挡下来的不算次数');

delete from public.price_list_runs where wholesaler_id = tests.uid('W2');
insert into public.price_list_runs (wholesaler_id, run_id, created_at)
select tests.uid('W2'), gen_random_uuid(), now() - interval '11 minutes' - k * interval '3 minutes' from generate_series(0, 8) as k;
select is(tests.try_reserve('W2', tests.uid('seller2')) ->> 'result', 'ok', '1 小时内第 10 次：可以');
select is(tests.try_reserve('W2', tests.uid('seller2')),
  '{"result": "quota", "window": "hour", "retry_after_sec": 1500}'::jsonb,
  '1 小时内第 11 次 → hour；最旧那次（35 分钟前）25 分钟后离开');

delete from public.price_list_runs where wholesaler_id = tests.uid('W2');
insert into public.price_list_runs (wholesaler_id, run_id, created_at)
select tests.uid('W2'), gen_random_uuid(), now() - interval '2 hours' - k * interval '10 minutes' from generate_series(0, 28) as k;
select is(tests.try_reserve('W2', tests.uid('seller2')) ->> 'result', 'ok', '1 天内第 30 次：可以');
select is(tests.try_reserve('W2', tests.uid('seller2')),
  '{"result": "quota", "window": "day", "retry_after_sec": 62400}'::jsonb,
  '1 天内第 31 次 → day；最旧那次（6 小时 40 分前）17 小时 20 分后离开');
select tests.add_runs('W2', array['1 minute', '2 minutes']::interval[]);
select is(tests.try_reserve('W2', tests.uid('seller2')),
  '{"result": "quota", "window": "day", "retry_after_sec": 63600}'::jsonb,
  '10 分钟和 1 天都满了：回传要等最久的那段；超过上限 2 次就要等第 3 旧那次离开');

delete from public.price_list_runs where wholesaler_id = tests.uid('W2');
insert into public.price_list_runs (wholesaler_id, run_id, created_at)
select tests.uid('W2'), gen_random_uuid(), now() - interval '25 hours' from generate_series(1, 40);
select is(tests.try_reserve('W2', tests.uid('seller2')) ->> 'result', 'ok', '一天以前跑的不算');

delete from public.price_list_runs where wholesaler_id = tests.uid('W2');
select tests.add_runs('W2', array['10 minutes', '1 minute', '2 minutes']::interval[]);
select is(tests.try_reserve('W2', tests.uid('seller2')) ->> 'result', 'ok', '刚好 10 分钟前那次已经不算');
delete from public.price_list_runs where wholesaler_id = tests.uid('W2');
select tests.add_runs('W2', array['9 minutes 59.5 seconds', '1 minute', '2 minutes']::interval[]);
select is(tests.try_reserve('W2', tests.uid('seller2')) ->> 'retry_after_sec', '1', '再半秒就有位置：retry_after_sec 至少 1');

-- ---------- 用量：还没审核（pending）2 / 4 / 8 ----------
delete from public.price_list_runs where wholesaler_id = tests.uid('W4');
select tests.add_runs('W4', array['8 minutes', '2 minutes']::interval[]);
select is(tests.try_reserve('W4', :'seller4'::uuid),
  '{"result": "quota", "window": "burst", "retry_after_sec": 120}'::jsonb, '待审核：10 分钟内第 3 次 → burst');
delete from public.price_list_runs where wholesaler_id = tests.uid('W4');
select tests.add_runs('W4', array['15 minutes', '20 minutes', '25 minutes', '30 minutes']::interval[]);
select is(tests.try_reserve('W4', :'seller4'::uuid),
  '{"result": "quota", "window": "hour", "retry_after_sec": 1800}'::jsonb, '待审核：1 小时内第 5 次 → hour');
delete from public.price_list_runs where wholesaler_id = tests.uid('W4');
insert into public.price_list_runs (wholesaler_id, run_id, created_at)
select tests.uid('W4'), gen_random_uuid(), now() - k * interval '1 hour' from generate_series(2, 9) as k;
select is(tests.try_reserve('W4', :'seller4'::uuid),
  '{"result": "quota", "window": "day", "retry_after_sec": 54000}'::jsonb, '待审核：1 天内第 9 次 → day');
delete from public.price_list_runs where wholesaler_id = tests.uid('W4');
select tests.add_runs('W4', array['15 minutes', '20 minutes', '25 minutes']::interval[]);
select is(tests.try_reserve('W4', :'seller4'::uuid) ->> 'result', 'ok', '待审核：1 小时内第 4 次还可以');
select is(
  (select string_agg(x.window_name || ':' || x.max_runs, ',') from public._price_list_run_limits('suspended') x), null,
  '停权：没有可以用的次数'
);

-- ---------- 检查的顺序、retry_after_sec 进位（Edge Function 测试的假 reserve 照这个顺序） ----------
select tests.new_import('W3', 'review') as imp_s_review \gset
select is(public.reserve_price_list_run(:'imp_s_review', tests.uid('seller3'), gen_random_uuid()),
  '{"result": "suspended"}'::jsonb, '停权 + 已经不是 processing → 先回 suspended');
delete from public.price_list_runs where wholesaler_id = tests.uid('W2');
select tests.add_runs('W2', array['1 minute', '2 minutes', '3 minutes']::interval[]);
select tests.new_import('W2', 'processing', jsonb_build_object('version', 1, 'state', 'running', 'run_id', gen_random_uuid(),
  'claimed_at', now())) as imp_running_full \gset
select is(public.reserve_price_list_run(:'imp_running_full', tests.uid('seller2'), gen_random_uuid()),
  '{"result": "already_running"}'::jsonb, '在跑 + 用量满了 → 先回 already_running');
select is(tests.try_reserve('W2', tests.uid('seller2')) ->> 'window', 'burst', '（W2 的 10 分钟真的满了）');
delete from public.price_list_runs where wholesaler_id = tests.uid('W2');
select tests.add_runs('W2', array['9 minutes 58.5 seconds', '1 minute', '2 minutes']::interval[]);
select is(tests.try_reserve('W2', tests.uid('seller2')) ->> 'retry_after_sec', '2',
  '还要 1.5 秒才有位置 → 2（进位；等 N 秒再叫才不会又被挡）');

-- ---------- 用量也按「人」算：叫的人、建这家批发商的人（一直注册新的批发商不会多出用量） ----------
delete from public.price_list_runs;
\set reg_region 'bbbbbbbb-0000-4000-8000-000000000001'
\set reg_industry 'bbbbbbbb-0000-4000-8000-000000000021'
select tests.login_as(tests.uid('seller1'));
select public.register_wholesaler('W5 seller1 新注册的', :'reg_region', :'reg_industry') as w5 \gset
select is(tests.error_of(format('select public.register_wholesaler(%L, %L, %L)', 'W5b 再注册一家', :'reg_region', :'reg_industry')),
  'WHOLESALER_ALREADY_PENDING:' || :'w5', '已经有一家待审核的：不能再注册（detail 是那一家）');
select tests.logout();
select is(
  (select w.status || '/' || w.created_by || '/' || m.member_role
   from public.wholesalers w join public.wholesaler_members m on m.wholesaler_id = w.id and m.user_id = tests.uid('seller1')
   where w.id = :'w5'),
  'pending/' || tests.uid('seller1') || '/owner', '（W5：待审核，seller1 建的、是老板；只有一家）'
);
select is(tests.try_reserve_for(:'w5', tests.uid('seller1')) ->> 'result', 'ok', 'W5（待审核）第 1 次');
select is(tests.try_reserve_for(:'w5', tests.uid('seller1')) ->> 'result', 'ok', 'W5 第 2 次');
select is(tests.try_reserve_for(:'w5', tests.uid('seller1')) ->> 'window', 'burst', 'W5 第 3 次 → 待审核的 10 分钟 2 次满了');
select is(tests.try_reserve('W1', tests.uid('seller1')) ->> 'result', 'ok', 'seller1 回到 W1（审核通过，3 次）：加起来第 3 次，可以');
select is(tests.try_reserve('W1', tests.uid('seller1')),
  '{"result": "quota", "window": "burst", "retry_after_sec": 600}'::jsonb,
  '叫的人在别家跑的也算：W1 才 1 次，seller1 加起来已经 3 次 → quota');
select is(tests.try_reserve('W1', tests.uid('admin')) ->> 'result', 'ok', '客服不算「人」的用量（W1 自己才 1 次）');

-- seller1 以前建的另一家（已经审核通过）W6，员工 seller5 来叫：seller1 建的每一家加起来算
\set seller5 'aaaaaaaa-0000-4000-8000-000000000015'
\set w6 'cccccccc-0000-4000-8000-000000000006'
insert into auth.users (id, phone) values (:'seller5', '60111000015');
update public.profiles set role = 'seller' where id = :'seller5';
insert into public.wholesalers (id, name, industry_id, region_id, status, created_by)
values (:'w6', 'W6 seller1 以前建的', :'reg_industry', :'reg_region', 'active', tests.uid('seller1'));
insert into public.wholesaler_members (wholesaler_id, user_id, member_role) values (:'w6', :'seller5', 'staff');
select is(tests.try_reserve_for(:'w6', :'seller5'::uuid) ->> 'result', 'ok', '员工在 W6：seller1 建的 W5、W6 加起来第 3 次，可以');
select is(tests.try_reserve_for(:'w6', :'seller5'::uuid),
  '{"result": "quota", "window": "burst", "retry_after_sec": 600}'::jsonb,
  '同一个人建的批发商加起来算：W6 才 1 次、员工自己才 1 次，seller1 建的已经 3 次 → quota');
select is((select count(*)::int from public.price_list_runs), 5, '（挡下来的都没算次数：W5 2 次、W1 2 次、W6 1 次）');

-- 审核通过之后才能再注册；客服不限制
update public.wholesalers set status = 'active' where id = :'w5';
select tests.login_as(tests.uid('seller1'));
select is(tests.error_of(format('select public.register_wholesaler(%L, %L, %L)', 'W7 seller1 第二家', :'reg_region', :'reg_industry')),
  null, 'W5 审核通过之后可以再注册一家');
select tests.login_as(tests.uid('admin'));
select is(
  coalesce(tests.error_of(format('select public.register_wholesaler(%L, %L, %L)', '客服建的 1', :'reg_region', :'reg_industry')), '-')
  || '/' || coalesce(tests.error_of(format('select public.register_wholesaler(%L, %L, %L)', '客服建的 2', :'reg_region', :'reg_industry')), '-'),
  '-/-', '客服不限制待审核的家数'
);
select tests.logout();
select is(
  (select count(*)::int from public.wholesalers where created_by = tests.uid('admin') and status = 'pending'), 2,
  '（客服建了两家待审核的）'
);

-- 停权的老板注册一家新的：一样不能跑；新的那家的员工也不能跑
select tests.login_as(tests.uid('seller3'));
select public.register_wholesaler('W8 停权老板新注册的', :'reg_region', :'reg_industry') as w8 \gset
select tests.logout();
insert into public.wholesaler_members (wholesaler_id, user_id, member_role) values (:'w8', :'seller5', 'staff');
select is(tests.try_reserve_for(:'w8', tests.uid('seller3')), '{"result": "suspended"}'::jsonb,
  '停权批发商（W3）的老板注册一家新的（W8，待审核）：也是 suspended');
select is(tests.try_reserve_for(:'w8', :'seller5'::uuid), '{"result": "suspended"}'::jsonb,
  '员工替 W8 叫也不行（W8 是停权的老板建的）');
-- 建过一家停权的（不是老板）也算
\set w9 'cccccccc-0000-4000-8000-000000000009'
insert into public.wholesalers (id, name, industry_id, region_id, status, created_by)
values (:'w9', 'W9 seller2 建的（停权）', :'reg_industry', :'reg_region', 'suspended', tests.uid('seller2'));
select is(tests.try_reserve('W2', tests.uid('seller2')), '{"result": "suspended"}'::jsonb,
  '叫的人建过一家停权的批发商：在自己审核通过的 W2 也是 suspended');
delete from public.wholesalers where id = :'w9';
select is(tests.try_reserve('W2', tests.uid('seller2')) ->> 'result', 'ok', '（W9 删掉之后 W2 又可以）');
select is(
  (select count(*) filter (where wholesaler_id = :'w8') || '/' || count(*) filter (where wholesaler_id = tests.uid('W2'))
   from public.price_list_runs),
  '0/1', '停权挡下来的没算次数（W8 0 次；W2 只有最后那一次）'
);

-- ---------- 批发商删掉自己的导入：用量记录留着（不然删了再传就没有限制） ----------
delete from public.price_list_runs;
select tests.new_import('W1') as del_1 \gset
select tests.new_import('W1') as del_2 \gset
select tests.new_import('W1') as del_3 \gset
select tests.new_import('W1') as del_4 \gset
select is(
  (select string_agg(public.reserve_price_list_run(t.x, tests.uid('seller1'), gen_random_uuid()) ->> 'result', ',' order by t.o)
   from unnest(array[:'del_1', :'del_2', :'del_3']::uuid[]) with ordinality as t(x, o)),
  'ok,ok,ok', '（W1 跑了 3 次）'
);
select tests.login_as(tests.uid('seller1'));
select is(tests.row_count(format('delete from public.price_list_imports where id in (%L, %L, %L)', :'del_1', :'del_2', :'del_3')),
  3, '批发商可以删掉自己的导入（RLS）');
select tests.logout();
select is(
  (select count(*)::int || '/' || count(import_id) from public.price_list_runs where wholesaler_id = tests.uid('W1')), '3/0',
  '用量记录留着（import_id 变成空的）'
);
select is(public.reserve_price_list_run(:'del_4', tests.uid('seller1'), gen_random_uuid()) ->> 'window', 'burst',
  '删掉导入之后再叫：照样算之前的 3 次 → quota');

-- =============================================================================
-- price_list_imports 的保护
-- =============================================================================
\set app_imp '99999999-0000-4000-8000-000000000701'
\set imp702 '99999999-0000-4000-8000-000000000702'
\set imp703 '99999999-0000-4000-8000-000000000703'
\set imp704 '99999999-0000-4000-8000-000000000704'
\set imp705 '99999999-0000-4000-8000-000000000705'
\set imp706 '99999999-0000-4000-8000-000000000706'
select tests.new_import('W1', 'processing', jsonb_build_object('version', 1, 'state', 'running', 'run_id', gen_random_uuid(),
  'claimed_at', now(), 'claimed_by', tests.uid('seller1'))) as imp_claimed \gset
select tests.new_import('W1', 'review') as imp_review \gset
select tests.new_import('W1', 'review') as imp_apply \gset
insert into public.price_list_import_rows (import_id, row_no, name, unit, pack_qty, price_sen, action)
values (:'imp_apply', 1, '保护测试 新商品', 'carton', 10, 1000, 'create');

select tests.login_as(tests.uid('seller1'));
-- App 的 createImport：{wholesaler_id, file_path, file_type, status: processing, created_by: 自己}
select lives_ok(
  format('insert into public.price_list_imports (id, wholesaler_id, file_path, file_type, status, created_by) values (%L, %L, %L, %L, %L, %L)',
         :'app_imp', tests.uid('W1'), tests.uid('W1') || '/00000000-0000-4000-8000-000000000701.jpg', 'image', 'processing',
         tests.uid('seller1')),
  'App 建导入（createImport：processing、created_by 自己）'
);
select is(
  (select status || '/' || created_by || '/' || (created_at = now()) || '/' || (ai_raw is null) from public.price_list_imports where id = :'app_imp'),
  'processing/' || tests.uid('seller1') || '/true/true', '建好了，批发商读得到'
);
select is(
  tests.app_insert(jsonb_build_object('id', :'imp702'::uuid, 'file_type', 'excel', 'created_at', now() - interval '1 day')),
  null, '没填 created_by 也可以'
);
select is(
  (select created_by || '/' || (created_at = now()) from public.price_list_imports where id = :'imp702'),
  tests.uid('seller1') || '/true', 'created_by 设成自己；created_at 不能自己填以前的时间（设成现在）'
);
select is(tests.app_insert(jsonb_build_object('id', :'imp705'::uuid, 'updated_at', now() - interval '1 day')), null,
  '（自己填以前的 updated_at）');
select is(tests.app_insert(jsonb_build_object('id', :'imp706'::uuid, 'updated_at', now() + interval '10 years')), null,
  '（自己填以后的 updated_at）');
select is(
  (select string_agg((updated_at = now())::text, ',' order by id) from public.price_list_imports where id in (:'imp705', :'imp706')),
  'true,true', 'updated_at 也设成现在（定时任务看它：不然可以让导入马上被标失败，或永远不会）'
);
select is(tests.app_insert(jsonb_build_object('created_by', tests.uid('seller2'))), 'COLUMN_PROTECTED:created_by',
  '新增：created_by 不能写别人');
select is(tests.app_insert('{"status": "review"}'), 'COLUMN_PROTECTED:status', '新增：只能是 processing（不能直接 review）');
select is(tests.app_insert('{"status": "applied"}'), 'COLUMN_PROTECTED:status', '新增：也不能直接 applied');
select is(tests.app_insert('{"ai_raw": {"state": "running", "claimed_at": "2000-01-01T00:00:00Z"}}'), 'COLUMN_PROTECTED:ai_raw',
  '新增：ai_raw 要是空的（不能自己写占位）');
select is(tests.app_insert('{"error_message": "AI_TIMEOUT"}'), 'COLUMN_PROTECTED:error_message', '新增：error_message 要是空的');
select is(tests.app_insert(jsonb_build_object('applied_at', now())), 'COLUMN_PROTECTED:applied_at', '新增：applied_at 要是空的');
select is(tests.app_insert(jsonb_build_object('id', :'imp703'::uuid)), null, '（再建两份）');
select is(tests.app_insert(jsonb_build_object('id', :'imp704'::uuid)), null, '（再建两份）');

-- App 的 markImportFailed：update {status: failed, error_message: code} where id = ? and status = processing
select lives_ok(
  format('update public.price_list_imports set status = %L, error_message = %L where id = %L and status = %L',
         'failed', 'START_FAILED', :'app_imp', 'processing'),
  'App 标失败（markImportFailed START_FAILED）'
);
select is((select status || '/' || error_message from public.price_list_imports where id = :'app_imp'), 'failed/START_FAILED',
  '标成失败了');
select lives_ok(
  format('update public.price_list_imports set status = %L, error_message = %L where id = %L and status = %L',
         'failed', 'NETWORK', :'imp702', 'processing'),
  'App 标失败（NETWORK）'
);
select lives_ok(
  format('update public.price_list_imports set status = %L, error_message = %L where id = %L and status = %L',
         'failed', 'AUTH', :'imp703', 'processing'),
  'App 标失败（AUTH）'
);
select is(
  tests.row_count(format('update public.price_list_imports set status = %L, error_message = %L where id = %L and status = %L',
                         'failed', 'NETWORK', :'app_imp', 'processing')),
  0, '已经不是 processing：App 的条件对不上，不改、不报错'
);
select lives_ok(format('update public.price_list_imports set status = status where id = %L', :'imp704'),
  '没改到什么的 update 可以');

-- 不能做的
select is(tests.error_of(format('update public.price_list_imports set status = %L, error_message = %L where id = %L', 'failed', 'AI_TIMEOUT', :'imp704')),
  'COLUMN_PROTECTED:error_message', '标失败只能用 App 的代码（START_FAILED / NETWORK / AUTH）');
select is(tests.error_of(format('update public.price_list_imports set status = %L where id = %L', 'failed', :'imp704')),
  'COLUMN_PROTECTED:error_message', '标失败一定要有代码');
select is(tests.error_of(format('update public.price_list_imports set status = %L where id = %L', 'review', :'imp704')),
  'COLUMN_PROTECTED:status', 'processing 不能自己改成 review');
select is(tests.error_of(format('update public.price_list_imports set status = %L, applied_at = null where id = %L', 'applied', :'imp_review')),
  'COLUMN_PROTECTED:status', 'review 不能自己改成 applied（要用 apply_price_list_import）');
select is(tests.error_of(format('update public.price_list_imports set status = %L, error_message = null where id = %L', 'processing', :'app_imp')),
  'COLUMN_PROTECTED:status', '失败的不能自己改回 processing 重跑');
select is(tests.error_of(format('update public.price_list_imports set status = %L, error_message = %L where id = %L', 'failed', 'START_FAILED', :'imp_review')),
  'COLUMN_PROTECTED:status', '只有 processing 可以标失败');
select is(tests.error_of(format('update public.price_list_imports set ai_raw = null where id = %L', :'imp_claimed')),
  'COLUMN_PROTECTED:ai_raw', '不能清掉别人的占位（抢着重跑）');
select is(tests.error_of(format('update public.price_list_imports set ai_raw = jsonb_set(ai_raw, %L, %L) where id = %L',
                                '{claimed_at}', to_jsonb(now() - interval '1 hour'), :'imp_claimed')),
  'COLUMN_PROTECTED:ai_raw', '不能把占位时间改旧');
select is(tests.error_of(format('update public.price_list_imports set error_message = %L where id = %L', 'NETWORK', :'app_imp')),
  'COLUMN_PROTECTED:error_message', '不能单独改 error_message');
select is(tests.error_of(format('update public.price_list_imports set wholesaler_id = %L where id = %L', tests.uid('W2'), :'imp704')),
  'COLUMN_PROTECTED:wholesaler_id', 'wholesaler_id 不能改');
select is(tests.error_of(format('update public.price_list_imports set file_path = %L where id = %L',
                                tests.uid('W1') || '/00000000-0000-4000-8000-000000000799.jpg', :'imp704')),
  'COLUMN_PROTECTED:file_path', 'file_path 不能改（就算是自己文件夹里的）');
select is(tests.error_of(format('update public.price_list_imports set file_type = %L where id = %L', 'pdf', :'imp704')),
  'COLUMN_PROTECTED:file_type', 'file_type 不能改');
select is(tests.error_of(format('update public.price_list_imports set applied_at = now() where id = %L', :'imp704')),
  'COLUMN_PROTECTED:applied_at', 'applied_at 不能改');
select is(tests.error_of(format('update public.price_list_imports set created_by = null where id = %L', :'imp704')),
  'COLUMN_PROTECTED:created_by', 'created_by 不能改');
select is(tests.error_of(format('update public.price_list_imports set created_at = %L where id = %L', now() - interval '1 day', :'imp704')),
  'COLUMN_PROTECTED:created_at', 'created_at 不能改');
select is(tests.error_of(format('update public.price_list_imports set id = gen_random_uuid() where id = %L', :'imp704')),
  'COLUMN_PROTECTED:id', 'id 不能改');
select is(
  (select status || '/' || coalesce(error_message, '-') || '/' || (ai_raw is null) || '/' || file_type
   from public.price_list_imports where id = :'imp704'),
  'processing/-/true/image', '上面那些都没改到'
);

-- 上架照样可以（security definer 函数不检查）
select lives_ok(format('select public.apply_price_list_import(%L)', :'imp_apply'), '批发商确认上架（apply_price_list_import）');
select is((select status || '/' || (applied_at is not null) from public.price_list_imports where id = :'imp_apply'), 'applied/true',
  '上架：status = applied、applied_at 有值');

-- 客服不检查（跟 protect_columns 一样）
select tests.login_as(tests.uid('admin'));
select lives_ok(
  format('update public.price_list_imports set status = %L, error_message = null where id = %L', 'processing', :'app_imp'),
  '客服可以手动把失败的改回 processing'
);

-- Edge Function（service_role）自己的写入照样可以
select tests.new_import('W1', 'processing', '{"version": 1, "state": "running", "run_id": "77777777-0000-4000-8000-000000000708"}') as imp_e \gset
select tests.new_import('W1', 'processing', '{"version": 1, "state": "running", "run_id": "77777777-0000-4000-8000-000000000709"}') as imp_f \gset
select tests.login_as_service();
select is(
  tests.row_count(format(
    'update public.price_list_imports set status = %L, error_message = null, ai_raw = %L where id = %L and status = %L and ai_raw ->> %L = %L',
    'review', '{"version": 1, "state": "done", "run_id": "77777777-0000-4000-8000-000000000708"}', :'imp_e', 'processing', 'run_id',
    '77777777-0000-4000-8000-000000000708')),
  1, 'Edge Function：写回结果、改成 review（用 run_id 过滤）'
);
select is(
  tests.row_count(format(
    'update public.price_list_imports set status = %L, error_message = %L, ai_raw = %L where id = %L and ai_raw ->> %L = %L',
    'failed', 'AI_FAILED', '{"version": 1, "state": "failed", "error": "AI_FAILED", "run_id": "77777777-0000-4000-8000-000000000709"}',
    :'imp_f', 'run_id', '77777777-0000-4000-8000-000000000709')),
  1, 'Edge Function：标 failed（任何代码）、换 ai_raw'
);
select is(
  tests.row_count(format('update public.price_list_imports set status = %L, error_message = %L where id = %L and ai_raw ->> %L = %L',
                         'failed', 'AI_TIMEOUT', :'imp_e', 'run_id', '77777777-0000-4000-8000-000000000999')),
  0, '（别次的 run_id 对不上：不改）'
);
select tests.logout();

-- =============================================================================
-- fail_stuck_price_list_imports：卡住的导入
-- =============================================================================
delete from public.price_list_imports;
delete from public.price_list_runs;
\set sw_run '77777777-0000-4000-8000-000000000801'
select tests.new_import('W1', 'processing', jsonb_build_object('version', 1, 'state', 'running', 'run_id', :'sw_run'::uuid,
  'claimed_at', now() - interval '16 minutes', 'claimed_by', tests.uid('seller1')), '20 minutes') as sw_run_old \gset
select tests.new_import('W1', 'processing', jsonb_build_object('version', 1, 'state', 'running', 'run_id', gen_random_uuid(),
  'claimed_at', now() - interval '12 minutes'), '1 hour') as sw_run_12 \gset
select tests.new_import('W1', 'processing', jsonb_build_object('version', 1, 'state', 'running', 'run_id', gen_random_uuid(),
  'claimed_at', now() - interval '5 minutes'), '1 hour') as sw_run_fresh \gset
select tests.new_import('W1', 'processing', '{"version": 1, "state": "running", "claimed_at": "not a time"}', '20 minutes') as sw_bad_time \gset
select tests.new_import('W2', 'processing', null, '16 minutes') as sw_new_old \gset
select tests.new_import('W2', 'processing', null, '5 minutes') as sw_new_fresh \gset
select tests.new_import('W2', 'review', '{"version": 1, "state": "done"}', '1 day') as sw_review \gset
select tests.new_import('W2', 'failed', '{"version": 1, "state": "failed", "error": "AI_REFUSED"}', '1 day') as sw_failed \gset
update public.price_list_imports set error_message = 'AI_REFUSED' where id = :'sw_failed';
insert into public.price_list_import_rows (import_id, row_no, name) values
  (:'sw_run_old', 1, '跑到一半的行 1'), (:'sw_run_old', 2, '跑到一半的行 2'), (:'sw_new_old', 1, '剩下的行'),
  (:'sw_run_fresh', 1, '正在跑的行'), (:'sw_review', 1, '等确认的行');
select tests.add_runs('W1', array['3 days', '50 hours', '1 day']::interval[]);
-- 客服把一天前的导入改回 processing（5 分钟前改的）：updated_at 是新的，created_at 是旧的
insert into public.price_list_imports (wholesaler_id, file_path, file_type, status, created_at, updated_at)
values (tests.uid('W2'), tests.uid('W2') || '/' || gen_random_uuid() || '.jpg', 'image', 'processing',
        now() - interval '1 day', now() - interval '5 minutes')
returning id as sw_reset \gset

select is(public.fail_stuck_price_list_imports(), 3, '标成失败 3 份：在跑超过 15 分钟的、读不懂占位时间的、从来没开始又过了 15 分钟的');
select is(
  (select status || '/' || error_message from public.price_list_imports where id = :'sw_run_old'), 'failed/AI_TIMEOUT',
  '在跑超过 15 分钟 → failed、AI_TIMEOUT'
);
select is(
  (select ai_raw from public.price_list_imports where id = :'sw_run_old'),
  jsonb_build_object('version', 1, 'state', 'failed', 'error', 'AI_TIMEOUT', 'run_id', :'sw_run'::uuid,
                     'claimed_at', now() - interval '16 minutes', 'claimed_by', tests.uid('seller1'),
                     'interrupted', 'sweep', 'finished_at', now()),
  'ai_raw 留着原来的（run_id、claimed_at、claimed_by），加上 state = failed、error、interrupted = sweep、finished_at'
);
select is(
  (select status || '/' || error_message || '/' || (ai_raw ->> 'interrupted') from public.price_list_imports where id = :'sw_bad_time'),
  'failed/AI_TIMEOUT/sweep', '占位时间读不懂：看最后改的时间（20 分钟前）→ AI_TIMEOUT'
);
select is(
  (select status || '/' || error_message from public.price_list_imports where id = :'sw_new_old'), 'failed/START_FAILED',
  '从来没开始、过了 15 分钟 → failed、START_FAILED'
);
select is(
  (select ai_raw from public.price_list_imports where id = :'sw_new_old'),
  jsonb_build_object('version', 1, 'state', 'failed', 'error', 'START_FAILED', 'interrupted', 'sweep', 'finished_at', now()),
  '没有 ai_raw 的：新建一份（version、state、error、interrupted、finished_at）'
);
select is(
  (select count(*)::int from public.price_list_import_rows where import_id in (:'sw_run_old', :'sw_new_old')), 0,
  '标成失败的导入，跑到一半的行删掉'
);
select is(
  (select count(*)::int from public.price_list_imports
   where id in (:'sw_run_12', :'sw_run_fresh', :'sw_new_fresh') and status = 'processing' and error_message is null),
  3, '还没到 15 分钟的不动（12 分钟前开始跑的：可以重新占位，但还不标失败）'
);
select is((select status || '/' || coalesce(error_message, '-') from public.price_list_imports where id = :'sw_reset'),
  'processing/-', '没人在跑的：看最后改的时间（updated_at），不是建的时间（客服刚改回 processing 的不会马上又被标失败）');
select is(
  (select string_agg(status || '/' || coalesce(error_message, '-') || '/' || (ai_raw ? 'interrupted'), ',' order by status)
   from public.price_list_imports where id in (:'sw_review', :'sw_failed')),
  'review/-/false,failed/AI_REFUSED/false', '不是 processing 的不动'
);
select is(
  (select count(*)::int from public.price_list_import_rows where import_id in (:'sw_run_fresh', :'sw_review')), 2,
  '没标失败的导入，行都留着'
);
select is(
  (select string_agg(extract(epoch from now() - created_at)::int::text, ',') from public.price_list_runs), '86400',
  '两天前的用量记录删掉（1 天前的留着）'
);
select is(public.fail_stuck_price_list_imports(), 0, '再跑一次：没有要改的');
select tests.login_as_service();
select is(public.fail_stuck_price_list_imports(), 0, 'service_role 也可以叫');
select tests.logout();
select is(public.reserve_price_list_run(:'sw_run_old', tests.uid('seller1'), gen_random_uuid()),
  '{"result": "not_processing", "status": "failed"}'::jsonb, '标成失败的不能再占位（批发商重新上传）');

-- =============================================================================
-- release_notification：领了但来不及发的通知放回队列
-- =============================================================================
\set nq '88888888-0000-4000-8000-000000000001'
\set nf '88888888-0000-4000-8000-000000000002'
\set ns '88888888-0000-4000-8000-000000000003'
update public.notifications set status = 'sent';   -- 其他的通知先当成发完了
insert into public.notifications (id, wholesaler_id, event_type) values (:'nq', tests.uid('W1'), 'test');
insert into public.notifications (id, wholesaler_id, event_type, status, attempts, next_attempt_at, last_error)
values (:'nf', tests.uid('W1'), 'test', 'failed', 2, now() - interval '1 minute', 'FCM_503');
insert into public.notifications (id, wholesaler_id, event_type, status, attempts, claimed_at, channel)
values (:'ns', tests.uid('W1'), 'test', 'sending', 1, now() - interval '11 minutes', 'push');

select public.claim_notifications() as c1 \gset
select is(
  (select array_agg((e ->> 'id')::uuid order by e ->> 'id') from jsonb_array_elements(:'c1'::jsonb) e),
  array[:'nq', :'nf', :'ns']::uuid[], '（领走：排队中的、到时间的 failed、卡住的）'
);
select is(
  (select string_agg(status || '/' || attempts, ',' order by id) from public.notifications where id in (:'nq', :'nf', :'ns')),
  'sending/0,sending/2,sending/2', '（领走时 queued / failed 不加 attempts；卡住重新领的加 1）'
);
select is(public.release_notification(:'nq'), true, '放回排队中领来的');
select is(public.release_notification(:'nf'), true, '放回失败重试领来的');
select is(public.release_notification(:'ns'), true, '放回卡住重新领来的');
select is(
  (select string_agg(status || '/' || attempts || '/' || coalesce(claimed_at::text, '-') || '/' || coalesce(next_attempt_at::text, '-'),
                     ',' order by id)
   from public.notifications where id in (:'nq', :'nf', :'ns')),
  'queued/0/-/-,queued/2/-/-,queued/2/-/-',
  '放回去：queued、claimed_at 和 next_attempt_at 清掉；attempts 跟领之前一样（卡住那一次照算）'
);
select is((select last_error from public.notifications where id = :'nf'), 'FCM_503', '上一次的错误留着');
select is(public.release_notification(:'nq'), false, '不是发送中：不改，回 false');

select public.claim_notifications() as c2 \gset
select is(
  (select array_agg((e ->> 'id')::uuid order by e ->> 'id') from jsonb_array_elements(:'c2'::jsonb) e),
  array[:'nq', :'nf', :'ns']::uuid[], '下一次领马上又领到（不用等重试时间）'
);
select is(
  (select string_agg(e ->> 'attempts', ',' order by e ->> 'id') from jsonb_array_elements(:'c2'::jsonb) e),
  '0,2,2', '再领也不加 attempts（放回去不算失败）'
);
select ok(public.complete_notification(:'nq', 'sent', 'push'), '（发出去了）');
select is(public.release_notification(:'nq'), false, '已经发完的不能放回');
select throws_ok(format('select public.release_notification(%L)', gen_random_uuid()), 'P0001', 'NOTIFICATION_NOT_FOUND',
  '没有这条通知 → NOTIFICATION_NOT_FOUND');
select tests.login_as_service();
select is(public.release_notification(:'ns'), true, 'service_role 可以叫');
select tests.logout();

-- ---------- claim id：放回去、记失败 / 跳过都要是领着的那个 dispatcher ----------
\set claim_a '66666666-0000-4000-8000-00000000000a'
\set claim_b '66666666-0000-4000-8000-00000000000b'
\set nt '88888888-0000-4000-8000-000000000004'
\set nt2 '88888888-0000-4000-8000-000000000005'
\set nt3 '88888888-0000-4000-8000-000000000006'
update public.notifications set status = 'sent' where status <> 'sent';   -- 上面的先当成发完了
insert into public.notifications (id, wholesaler_id, event_type) values (:'nt', tests.uid('W1'), 'test');
select is(
  (select string_agg(e ->> 'id', ',') from jsonb_array_elements(public.claim_notifications(50, :'claim_a')) e), :'nt',
  '（dispatcher A 带着 claim id 领走）'
);
select is((select claim_id from public.notifications where id = :'nt'), :'claim_a'::uuid, '领的时候记下 claim_id');
select is(public.release_notification(:'nt', :'claim_b'), false, '别人的 claim id：不能放回');
select is(public.release_notification(:'nt'), false, '没带 claim id 也不能放回（这条不是没带 id 领的）');
select is(public.complete_notification(:'nt', 'failed', 'push', 'X', null, true, :'claim_b'), false, '别人的 claim id：不能记失败');
select is(public.complete_notification(:'nt', 'skipped', null, 'X', null, true, :'claim_b'), false, '也不能记跳过');
select is((select status || '/' || attempts || '/' || claim_id from public.notifications where id = :'nt'),
  'sending/0/' || :'claim_a', '（上面那些都没改到）');
select is(public.release_notification(:'nt', :'claim_a'), true, '自己领的可以放回');
select is((select status || '/' || coalesce(claimed_at::text, '-') || '/' || coalesce(claim_id::text, '-') from public.notifications where id = :'nt'),
  'queued/-/-', '放回去：claimed_at、claim_id 清掉');
-- 修好的情况：A 放回去了（回应在路上断了），B 马上领走在发；A 以为没放回去，改用 complete 标失败 → 对不上，不改
select is(jsonb_array_length(public.claim_notifications(50, :'claim_b')), 1, '（dispatcher B 马上又领走）');
select is(public.complete_notification(:'nt', 'failed', 'push', 'DISPATCH_TIME_BUDGET', null, true, :'claim_a'), false,
  'A 晚到的「标失败」：已经是 B 的了，不改');
select is((select status || '/' || attempts || '/' || claim_id || '/' || coalesce(last_error, '-') from public.notifications where id = :'nt'),
  'sending/0/' || :'claim_b' || '/-', '还是 B 在发（没有变成 failed、没有算一次失败）');
select is(public.complete_notification(:'nt', 'sent', 'push', null, null, true, :'claim_b'), true, 'B 发完记得到');
select is((select status || '/' || (sent_at is not null) || '/' || attempts from public.notifications where id = :'nt'), 'sent/true/1',
  '记下「已发」（不会过几分钟又重发一次）');
-- 卡住重新领：claim_id 换成新的；「已发」不看 claim id（真的发出去了就记下来）
insert into public.notifications (id, wholesaler_id, event_type) values (:'nt2', tests.uid('W1'), 'test');
insert into public.notifications (id, wholesaler_id, event_type, status, attempts, claimed_at, claim_id, channel)
values (:'nt3', tests.uid('W1'), 'test', 'sending', 0, now() - interval '11 minutes', :'claim_a', 'push');
select is(
  (select string_agg(e ->> 'id', ',' order by e ->> 'id') from jsonb_array_elements(public.claim_notifications(50, :'claim_b')) e),
  :'nt2' || ',' || :'nt3', '（B 领走：新的一条、A 卡住超过 10 分钟的那条）'
);
select is((select string_agg(claim_id::text, ',' order by id) from public.notifications where id in (:'nt2', :'nt3')),
  :'claim_b' || ',' || :'claim_b', '卡住重新领的：claim_id 换成 B 的');
select is(public.complete_notification(:'nt3', 'failed', 'push', 'late', null, true, :'claim_a'), false,
  'A（卡住的那个）很晚才记失败：不改 B 的');
select is(public.complete_notification(:'nt2', 'sent', 'push', null, null, true, :'claim_a'), true,
  '「已发」不看 claim id：真的发出去了就记下来');
select is(public.complete_notification(:'nt2', 'failed', 'push', 'x', null, true, :'claim_b'), false,
  '（之后 B 的结果记不进去：已经不是发送中，也不会再重试）');
select is((select status::text from public.notifications where id = :'nt2'), 'sent', '（还是 sent）');

-- =============================================================================
-- 同时进来的请求：另外开连线（dblink）测锁
-- pgTAP 的测试只有一个连线、一个交易，测不到两个请求同时进来；这里另外开连线（c1、c2、c3），
-- 测试资料要先提交（conc 连线建；固定的 id，开始和最后都删掉）。这个交易自己改过的行别的连线碰不到，
-- 所以测试资料都是新的（批发商 CX、CY、CC1、CC2，用户 UA、UB、UC）。连线都设了 lock_timeout：
-- 真的卡住会报错，不会一直等。只在本机跑（scripts/test-db.sh：超级用户、有 dblink）；真的 Supabase 跳过。
-- =============================================================================
select exists (select 1 from pg_available_extensions where name = 'dblink')
       and coalesce((select r.rolsuper from pg_roles r where r.rolname = current_user), false) as can_conc \gset
\if :can_conc
create extension if not exists dblink with schema extensions;
select format('host=%s port=%s dbname=%s user=%s options=''-c lock_timeout=10s -c statement_timeout=30s''',
              coalesce(nullif(trim(split_part(current_setting('unix_socket_directories'), ',', 1)), ''), 'localhost'),
              current_setting('port'), current_database(), current_user) as conninfo \gset
select dblink_connect('conc', :'conninfo') as _ \gset
select dblink_connect('c1', :'conninfo') as _ \gset
select dblink_connect('c2', :'conninfo') as _ \gset
select dblink_connect('c3', :'conninfo') as _ \gset

-- 在另一个连线跑一句，回传第一行第一栏（文字）
create function tests.remote(p_conn text, p_sql text) returns text language sql as $$
  select t.v from dblink(p_conn, p_sql) as t(v text);
$$;
-- 送出去不等（之后用 remote_result 拿结果）
create function tests.remote_send(p_conn text, p_sql text) returns int language sql as $$
  select dblink_send_query(p_conn, p_sql);
$$;
create function tests.remote_result(p_conn text) returns text language plpgsql as $$
declare
  v text;
begin
  select t.v into v from dblink_get_result(p_conn) as t(v text);
  perform 1 from dblink_get_result(p_conn) as t(v text);   -- dblink 要再读一次（空的）才算做完
  return v;
end;
$$;
-- 等连线 p_conn（pid p_pid）：被 p_holder 挡住（在等锁）→ waiting；已经做完 → done；10 秒都不是 → timeout
create function tests.wait_remote(p_conn text, p_pid int, p_holder int) returns text language plpgsql as $$
begin
  for i in 1..200 loop
    if p_holder = any (pg_catalog.pg_blocking_pids(p_pid)) then
      return 'waiting';
    end if;
    if dblink_is_busy(p_conn) = 0 then
      return 'done';
    end if;
    perform pg_sleep(0.05);
  end loop;
  return 'timeout';
end;
$$;
create function tests.reserve_sql(p_import uuid, p_user uuid) returns text language sql as $$
  select format('select public.reserve_price_list_run(%L, %L, gen_random_uuid())::text', p_import, p_user);
$$;
-- 测试资料（都用 conc 连线、马上提交）
create function tests.conc_reset() returns text language sql as $$
  select dblink_exec('conc', $q$
    delete from public.wholesalers where id::text like 'cccccccc-0000-4000-8000-0000000000c%';
    delete from auth.users where id::text like 'aaaaaaaa-0000-4000-8000-0000000000c%';
    delete from public.regions where id = 'bbbbbbbb-0000-4000-8000-0000000000c1';
    delete from public.industries where id = 'bbbbbbbb-0000-4000-8000-0000000000c2';
  $q$);
$$;
create function tests.conc_clear() returns text language sql as $$
  select dblink_exec('conc', $q$
    delete from public.price_list_runs where wholesaler_id::text like 'cccccccc-0000-4000-8000-0000000000c%';
    delete from public.price_list_imports where wholesaler_id::text like 'cccccccc-0000-4000-8000-0000000000c%';
  $q$);
$$;
create function tests.conc_import(p_wholesaler uuid, p_age interval default '0 seconds') returns uuid language sql as $$
  select tests.remote('conc', format(
    'insert into public.price_list_imports (wholesaler_id, file_path, file_type, created_at, updated_at) '
    'values (%L, %L, %L, now() - %L::interval, now() - %L::interval) returning id::text',
    p_wholesaler, p_wholesaler || '/' || gen_random_uuid() || '.jpg', 'image', p_age, p_age))::uuid;
$$;
-- 1 分钟前跑过 p_n 次（p_user 叫的；空的 = 没记录）
create function tests.conc_runs(p_wholesaler uuid, p_user uuid, p_n int) returns text language sql as $$
  select dblink_exec('conc', format(
    'insert into public.price_list_runs (wholesaler_id, user_id, run_id, created_at) '
    'select %L, %L, gen_random_uuid(), now() - interval %L from generate_series(1, %s)',
    p_wholesaler, p_user, '1 minute', p_n));
$$;

\set cx 'cccccccc-0000-4000-8000-0000000000c1'
\set cy 'cccccccc-0000-4000-8000-0000000000c2'
\set cc1 'cccccccc-0000-4000-8000-0000000000c3'
\set cc2 'cccccccc-0000-4000-8000-0000000000c4'
\set ua 'aaaaaaaa-0000-4000-8000-0000000000c1'
\set ub 'aaaaaaaa-0000-4000-8000-0000000000c2'
\set uc 'aaaaaaaa-0000-4000-8000-0000000000c3'
\set cn '88888888-0000-4000-8000-0000000000c1'
select tests.conc_reset() as _ \gset
-- CX：UA 老板、UB 员工；CY：UA 老板；CC1、CC2：UC 建的（CC1 UA 员工，CC2 UB 员工）。都审核通过（3 / 10 / 30）
select dblink_exec('conc', format($q$
  insert into public.regions (id, code, name)
  values ('bbbbbbbb-0000-4000-8000-0000000000c1', 'conc_test', '{"zh": "并发测试", "en": "Conc", "ms": "Conc"}');
  insert into public.industries (id, code, name, default_commission_rate, founding_commission_rate)
  values ('bbbbbbbb-0000-4000-8000-0000000000c2', 'conc_test', '{"zh": "并发测试", "en": "Conc", "ms": "Conc"}', 0.03, 0.015);
  insert into auth.users (id, phone) values (%5$L, '60111000781'), (%6$L, '60111000782'), (%7$L, '60111000783');
  update public.profiles set role = 'seller' where id in (%5$L, %6$L, %7$L);
  insert into public.wholesalers (id, name, industry_id, region_id, status, created_by) values
    (%1$L, 'CX', 'bbbbbbbb-0000-4000-8000-0000000000c2', 'bbbbbbbb-0000-4000-8000-0000000000c1', 'active', null),
    (%2$L, 'CY', 'bbbbbbbb-0000-4000-8000-0000000000c2', 'bbbbbbbb-0000-4000-8000-0000000000c1', 'active', null),
    (%3$L, 'CC1', 'bbbbbbbb-0000-4000-8000-0000000000c2', 'bbbbbbbb-0000-4000-8000-0000000000c1', 'active', %7$L),
    (%4$L, 'CC2', 'bbbbbbbb-0000-4000-8000-0000000000c2', 'bbbbbbbb-0000-4000-8000-0000000000c1', 'active', %7$L);
  insert into public.wholesaler_members (wholesaler_id, user_id, member_role) values
    (%1$L, %5$L, 'owner'), (%1$L, %6$L, 'staff'), (%2$L, %5$L, 'owner'),
    (%3$L, %7$L, 'owner'), (%3$L, %5$L, 'staff'), (%4$L, %6$L, 'staff');
$q$, :'cx', :'cy', :'cc1', :'cc2', :'ua', :'ub', :'uc')) as _ \gset
select tests.remote('c1', 'select pg_backend_pid()::text') as c1_pid \gset
select tests.remote('c2', 'select pg_backend_pid()::text') as c2_pid \gset

-- ---------- 同一家批发商、两个人同时叫：在批发商那一行排队（for no key update） ----------
select tests.conc_clear() as _ \gset
select tests.conc_runs(:'cx', null, 2) as _ \gset
select tests.conc_import(:'cx') as q_i1 \gset
select tests.conc_import(:'cx') as q_i2 \gset
select dblink_exec('c1', 'begin') as _ \gset
select is(tests.remote('c1', tests.reserve_sql(:'q_i1', :'ua'))::jsonb ->> 'result', 'ok',
  '同时（同一家）：c1 占位，CX 10 分钟内第 3 次（还没提交）');
select is(
  dblink_exec('c3', format('set lock_timeout = %L; insert into public.price_list_imports (wholesaler_id, file_path, file_type) values (%L, %L, %L)',
                           '500ms', :'cx', :'cx' || '/' || gen_random_uuid() || '.jpg', 'image'), false),
  'INSERT 0 1', 'c1 锁着批发商的时候，这家照样可以新增导入（for no key update 不挡外键；for update 会挡）'
);
select tests.remote_send('c2', tests.reserve_sql(:'q_i2', :'ub')) as _ \gset
select is(tests.wait_remote('c2', :c2_pid, :c1_pid), 'waiting', 'c2（同一家、另一个人）在等 c1');
select dblink_exec('c1', 'commit') as _ \gset
select is(tests.remote_result('c2')::jsonb ->> 'result', 'quota', 'c1 提交之后 c2 才数：已经 3 次 → quota（不会多放一次）');
select is((select count(*)::int from public.price_list_runs where wholesaler_id = :'cx'), 3, 'CX 10 分钟内还是 3 次');

-- ---------- 同一个人、两家批发商同时叫：在「人」的 advisory lock 排队 ----------
select tests.conc_clear() as _ \gset
select tests.conc_runs(:'cy', :'ua', 2) as _ \gset
select tests.conc_import(:'cx') as u_i1 \gset
select tests.conc_import(:'cy') as u_i2 \gset
select dblink_exec('c1', 'begin') as _ \gset
select is(tests.remote('c1', tests.reserve_sql(:'u_i1', :'ua'))::jsonb ->> 'result', 'ok',
  '同时（同一个人）：c1 在 CX 占位，UA 加起来第 3 次（还没提交）');
select tests.remote_send('c2', tests.reserve_sql(:'u_i2', :'ua')) as _ \gset
select is(tests.wait_remote('c2', :c2_pid, :c1_pid), 'waiting', 'c2（同一个人、另一家 CY）在等 c1');
select dblink_exec('c1', 'commit') as _ \gset
select is(tests.remote_result('c2')::jsonb ->> 'result', 'quota', 'c2 → quota（UA 加起来已经 3 次）');
select is((select count(*)::int from public.price_list_runs where user_id = :'ua'), 3, 'UA 还是 3 次');

-- ---------- 同一个人建的两家、两个员工同时叫：在「建的人」的 advisory lock 排队 ----------
select tests.conc_clear() as _ \gset
select tests.conc_runs(:'cc1', null, 2) as _ \gset
select tests.conc_import(:'cc2') as c_i1 \gset
select tests.conc_import(:'cc1') as c_i2 \gset
select dblink_exec('c1', 'begin') as _ \gset
select is(tests.remote('c1', tests.reserve_sql(:'c_i1', :'ub'))::jsonb ->> 'result', 'ok',
  '同时（同一个人建的两家）：c1 UB 在 CC2 占位，UC 建的加起来第 3 次（还没提交）');
select tests.remote_send('c2', tests.reserve_sql(:'c_i2', :'ua')) as _ \gset
select is(tests.wait_remote('c2', :c2_pid, :c1_pid), 'waiting', 'c2（UA 在 CC1）在等 c1');
select dblink_exec('c1', 'commit') as _ \gset
select is(tests.remote_result('c2')::jsonb ->> 'result', 'quota', 'c2 → quota（UC 建的加起来已经 3 次）');
select is((select count(*)::int from public.price_list_runs where wholesaler_id in (:'cc1', :'cc2')), 3, 'CC1 + CC2 还是 3 次');

-- ---------- App 正在把导入标失败（markImportFailed）的时候占位：等那一行，不会用旧的资料占位 ----------
select tests.conc_clear() as _ \gset
select tests.conc_import(:'cx') as i_imp \gset
select dblink_exec('c1', 'begin') as _ \gset
select dblink_exec('c1', format('update public.price_list_imports set status = %L, error_message = %L where id = %L',
                                'failed', 'START_FAILED', :'i_imp')) as _ \gset
select tests.remote_send('c2', tests.reserve_sql(:'i_imp', :'ua')) as _ \gset
select is(tests.wait_remote('c2', :c2_pid, :c1_pid), 'waiting', 'c1 在改导入（还没提交）：c2 的占位等那一行（for update）');
select dblink_exec('c1', 'commit') as _ \gset
select is(tests.remote_result('c2')::jsonb, '{"result": "not_processing", "status": "failed"}'::jsonb,
  'c1 提交之后才看：已经 failed → not_processing');
select is(
  (select i.status || '/' || i.error_message || '/' || coalesce(i.ai_raw::text, '-') || '/'
          || (select count(*) from public.price_list_runs r where r.import_id = i.id)
   from public.price_list_imports i where i.id = :'i_imp'),
  'failed/START_FAILED/-/0', '导入还是 failed、START_FAILED：没有占位、没算次数（不会白叫 Claude）'
);

-- ---------- 定时任务同时在跑：正在占位的导入跳过（skip locked），不会用旧的资料标成 START_FAILED ----------
select tests.conc_clear() as _ \gset
select tests.conc_import(:'cx', '20 minutes') as s_imp \gset
select dblink_exec('c1', 'begin') as _ \gset
select is(tests.remote('c1', tests.reserve_sql(:'s_imp', :'ua'))::jsonb ->> 'result', 'ok',
  '20 分钟前建的导入现在才占位（c1 还没提交）');
select tests.remote_send('c2', 'select public.fail_stuck_price_list_imports()::text') as _ \gset
select is(tests.wait_remote('c2', :c2_pid, :c1_pid), 'done', '定时任务不等正在占位的那一份（c1 还没提交就做完了）');
select dblink_exec('c1', 'commit') as _ \gset
select is(tests.remote_result('c2'), '0', '也没有把它标成失败');
select is((select status || '/' || (ai_raw ->> 'state') from public.price_list_imports where id = :'s_imp'), 'processing/running',
  '占位成功的照样在跑');

-- ---------- 同时 complete 和 release：等 complete 做完再看，发完的不会放回队列 ----------
select dblink_exec('conc', format(
  'insert into public.notifications (id, wholesaler_id, event_type, status, claimed_at, claim_id, channel) '
  'values (%L, %L, %L, %L, now(), %L, %L)', :'cn', :'cx', 'test', 'sending', :'claim_a', 'push')) as _ \gset
select dblink_exec('c1', 'begin') as _ \gset
select is(tests.remote('c1', format('select public.complete_notification(%L, %L, %L, null, null, true, %L)::text',
                                    :'cn', 'sent', 'push', :'claim_a')),
  'true', 'c1 记「已发」（还没提交）');
select tests.remote_send('c2', format('select public.release_notification(%L, %L)::text', :'cn', :'claim_a')) as _ \gset
select is(tests.wait_remote('c2', :c2_pid, :c1_pid), 'waiting', '同时要把它放回队列：等 c1 做完');
select dblink_exec('c1', 'commit') as _ \gset
select is(tests.remote_result('c2'), 'false', 'c1 提交之后再看：已经发完了，不放回（回 false）');
select is((select status || '/' || (sent_at is not null) from public.notifications where id = :'cn'), 'sent/true',
  '还是「已发」（不会再被领、再发一次）');

select tests.conc_reset() as _ \gset
select dblink_disconnect('c1') as _ \gset
select dblink_disconnect('c2') as _ \gset
select dblink_disconnect('c3') as _ \gset
select dblink_disconnect('conc') as _ \gset
\else
select skip('没有 dblink 或不是超级用户（真的 Supabase）：两个连线同时进来的测试只在 scripts/test-db.sh 跑', 24);
\endif

-- =============================================================================
-- 定时任务（跟 06 一样：本机用假的 cron.schedule 测；真的 Supabase 检查迁移建好的）
-- =============================================================================
set local client_min_messages = error;
select to_regnamespace('cron') is null as fake_cron \gset
\if :fake_cron
select is(public._schedule_seller_hardening_jobs(), false, '没有 pg_cron：跳过');
create schema cron;
create table cron.test_jobs (jobname text primary key, schedule text, command text);
create function cron.schedule(job_name text, schedule text, command text) returns bigint language sql as $$
  insert into cron.test_jobs values (job_name, schedule, command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command;
  select 1::bigint;
$$;
select ok(public._schedule_seller_hardening_jobs(), '有 pg_cron：建定时任务');
select ok(public._schedule_seller_hardening_jobs(), '可以重复跑（同名的会更新）');
select is(
  (select string_agg(jobname || ' | ' || schedule || ' | ' || command, E'\n' order by jobname) from cron.test_jobs),
  'fail-stuck-price-list-imports | */5 * * * * | select public.fail_stuck_price_list_imports()',
  '每 5 分钟把卡住的导入标成失败（只有一个，重复跑不会多建）'
);
select skip('本机没有 pg_cron：迁移建好的定时任务只能在真的 Supabase 检查', 1);
\else
-- 真的 pg_cron（Supabase）：先检查迁移建好的（在测试自己再跑一次之前），再测重复跑是更新同名的。
-- 06 的三个也在这里检查（06 的测试也会自己再跑一次，交易 rollback 之后这里看到的是迁移建的）
select is(
  (select string_agg(jobname || ' | ' || schedule || ' | ' || command, E'\n' order by jobname) from cron.job
   where jobname in ('fail-stuck-price-list-imports', 'daily-delivery-summary', 'dispatch-notifications', 'unconfirmed-order-alerts')),
  'daily-delivery-summary | 30 21 * * * | select public.enqueue_daily_summaries()' || E'\n'
  || 'dispatch-notifications | * * * * * | select public._request_notification_dispatch(true)' || E'\n'
  || 'fail-stuck-price-list-imports | */5 * * * * | select public.fail_stuck_price_list_imports()' || E'\n'
  || 'unconfirmed-order-alerts | */5 * * * * | select public.enqueue_unconfirmed_alerts()',
  '迁移已经建好定时任务（06 的三个、这里的一个）'
);
select ok(public._schedule_seller_hardening_jobs(), '有 pg_cron：建定时任务（同名的会更新）');
select ok(public._schedule_seller_hardening_jobs(), '可以重复跑');
select is(
  (select string_agg(jobname || ' | ' || schedule || ' | ' || command, E'\n' order by jobname) from cron.job
   where jobname = 'fail-stuck-price-list-imports'),
  'fail-stuck-price-list-imports | */5 * * * * | select public.fail_stuck_price_list_imports()',
  '每 5 分钟把卡住的导入标成失败（只有一个，重复跑不会多建）'
);
select skip('真的 pg_cron：「没有 pg_cron 就跳过」在这里不测', 1);
\endif

select * from finish();
rollback;
