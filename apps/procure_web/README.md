# 公司采购网页（Flutter Web）

给公司账号（公司、工厂、酒店、连锁餐厅、GLC）的员工用电脑操作。第八步第 1 期（`docs/08-procurement-spec.md` 第 12 节）有：
手机号 + 验证码登录、注册公司（送 30 天试用）、换公司（一个人可以是几家公司的成员）、首页、商品比价（选分店，`get_offers`）、
分店 / 工地（加、改、封存）、成员和邀请（角色、能管哪几个分店）、方案和付款（换方案下一期生效、账单 → HitPay 新分页）、收件箱、公司资料。
申请单、审批、采购单、收货、对账、询价是之后几期。

- 角色：`admin`（全部）、`finance`（方案、付款、全部分店）、`approver`、`requester`（只看自己的分店，看不到成员和方案）。
  服务器的函数（`supabase/migrations/20261202000200_company_accounts.sql`）会再检查角色，测试 `supabase/tests/database/12_company_accounts.test.sql`。
- 数据模型和服务器调用在 `packages/core`（`ProcureApi`、`lib/src/models/company.dart`）。
- **公司方案只在这里付**（手机 App 不卖、不放付款按钮或连结，只显示「方案由贵公司管理」）。

## 不用服务器，先看画面（示范模式）

```bash
flutter run -d chrome -t lib/main_demo.dart
```

资料是本机数据库导出的真实样本，按了会跟着变（只在记忆体里）。网址参数：`?lang=zh|en|ms`、`?login=1`（从登录开始，验证码 `123456`）、
`?new=1`（还没有公司：注册公司）、`?role=requester|finance`（用这个角色看）、`?seller=1`（批发商账号：不能用）。

## 连本机的 Supabase

```bash
cp config/local.example.json config/local.json   # 填 Publishable key
flutter run -d chrome --dart-define-from-file=config/local.json
```

用任何一个测试号码登录（例如 `60120000003`，先不要设成客服），会去「注册公司」。付款要 Edge Function `create-payment`
有 `HITPAY_*` 设定（见 `docs/07-billing.md`）；没设定时画面说「网上付款还没开通」，客服可以在客服后台「公司」标记银行转账已付。

## 测试、打包

```bash
flutter analyze
flutter test                 # 示范模式把每一页点一遍（1280 和 400 宽度、三种语言、几种角色），加上 ARB 键检查
flutter build web            # 正式版（要 --dart-define-from-file）；示范版加 -t lib/main_demo.dart
```

## 更新示范数据

改了公司的函数之后：`./tool/export_fixtures.sh`（临时起一个 Postgres，端口 54381，跑迁移和 seed，再跑 `tool/procure_fixtures.sql`，
把回传存成 `packages/core/test/fixtures/procure_*.json` 和客服后台的 `admin_compan*.json`，最后产生两边的 `lib/demo/demo_data.dart`）。
