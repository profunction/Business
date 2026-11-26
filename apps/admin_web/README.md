# 客服后台（Flutter Web）

客服用电脑（平板也可以）操作：代买家下单、代批发商管商品（上架 / 下架、改价钱、改库存）、看全部订单（按日期、批发商、店铺、状态、来源筛选）
和代改状态、新订单超过 30 分钟没确认的跟进名单、订阅（延长试用、手动标记已付、取消、创始价）、批发商审核 / 停权 / 佣金比例 / 创始会员、
每月佣金报表（CSV 全部、每家一份 PDF 账单；草稿 → 发出 → 已付）、操作记录。

- 只有 `profiles.role = 'admin'` 的账号进得来（登录跟手机 App 一样用手机号 + 验证码）；服务器的 `admin_*` 函数也会再检查 `is_admin()`，
  每个动作写一行 `audit_logs`。函数在 `supabase/migrations/20261128000100_admin.sql`，测试 `supabase/tests/database/08_admin.test.sql`。
- 数据模型和服务器调用在 `packages/core`（`AdminApi`、`lib/src/models/admin.dart`、佣金 CSV `commission_csv.dart`）。

## 不用服务器，先看画面（示范模式）

```bash
flutter run -d chrome -t lib/main_demo.dart
```

资料是本机数据库导出的真实样本，按了会跟着变（只在记忆体里）。网址参数：`?lang=zh|en|ms`、`?login=1`（从登录开始，验证码 `123456`）、
`?buyer=1`（登录的不是客服，看「不是客服」那一页）。

## 连本机的 Supabase

```bash
cp config/local.example.json config/local.json   # 填 Publishable key
flutter run -d chrome --dart-define-from-file=config/local.json
```

客服账号：用 `60120000003` 登录一次，再在 SQL editor 执行 `update public.profiles set role = 'admin' where phone = '60120000003';`。

**账单上的公司资料**（`INVOICE_COMPANY_NAME`、`_SSM`、`_ADDRESS`、`_EMAIL`、`INVOICE_BANK_DETAILS`）：公司注册（SSM）和银行户口办好之后再填；
没填时 PDF 印「公司资料未设定」，其他照样能用。LHDN e-Invoice（MyInvois）还没接，上线前问会计。

## 测试、打包

```bash
flutter analyze
flutter test                 # 示范模式把每一页点一遍（电脑和平板宽度、三种语言），加上 PDF、ARB 键检查
flutter build web            # 正式版（要 --dart-define-from-file）；示范版加 -t lib/main_demo.dart
```

## 更新示范数据

改了 `admin_*` 函数之后：`./tool/export_fixtures.sh`（临时起一个 Postgres，跑迁移和 seed，再跑 `tool/admin_fixtures.sql`，
把回传存成 `packages/core/test/fixtures/admin_*.json`，最后产生 `lib/demo/demo_data.dart`）。
