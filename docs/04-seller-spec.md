# 第四步规格：批发商端、推送、WhatsApp 接单、价目表 AI

> 这份是给实现用的「合同」：数据库函数、服务器函数（Edge Functions）、App 之间的接口都以这里为准。
> 第 5 节（外部服务细节）以查证结果为准，见 `docs/04-research.md`。

## 0. 第四步要求（docs/prompts.md）

1. 新订单推送通知，一键「确认」或「缺货」
2. 每天早上一份当天订单总结，可以打印给送货员
3. 上传价钱表照片或 Excel，由 AI 转成商品目录，确认后才上架
4. 修改价钱和库存
5. 没装 App 的批发商：订单用 WhatsApp Business API 模板消息发给他，消息里有「确认」和「缺货」按钮

## 1. 不变的原则（沿用第一到三步）

- 钱和状态只在数据库函数里改；每张表 RLS；新函数先 `revoke execute ... from public, anon, authenticated` 再只开放需要的。
- 只给服务器（service_role）用的函数，第一行检查 `public.is_service_call()`。
- 错误用英文代码 `raise exception 'CODE' using errcode = 'P0001'`（权限是 `42501`）。
- 金额用仙（int），日期按马来西亚时间（`public.today_myt()`）。
- 所有文字三语（zh / en / ms）；App 字最小 18、主要按钮 64 高、每页一个主要动作。

## 2. 数据库（新迁移 `supabase/migrations/20261127000100_seller.sql`）

### 2.1 结构变动

- `notification_status` 加一个值 `sending`（发送中，被 dispatcher 领走了）。
- `notifications` 加 `next_attempt_at timestamptz`（失败重试的时间）、`claimed_at timestamptz`。
- `orders` 加 `unconfirmed_alert_at timestamptz`（提醒过客服的时间）。
- 扩展 `pg_trgm`（商品名比对；装在 `extensions` schema，本机测试环境也要有）。

### 2.2 批发商读取（App 用，`authenticated`）

| 函数 | 回传 | 说明 |
|---|---|---|
| `get_seller_home(p_wholesaler_id uuid)` | jsonb | `wholesaler {id,name,status,is_founding,notify_channel}`、`pending_count`、`oldest_pending_at`、`today` (日期)、`today_order_count`（今天要送：confirmed/delivering 且 expected_delivery_date = today）、`today_total_sen`、`product_counts {active, draft, out_of_stock, low_stock}`、`latest_import {id,status,created_at}` 或 null |
| `list_seller_orders(p_wholesaler_id uuid, p_statuses order_status[] default null, p_delivery_date date default null, p_limit int default 50)` | jsonb array | 每张：`id, order_no, status, shop_name, zone_name (三语), item_count, out_of_stock_count, goods_subtotal_sen, shipping_fee_sen, total_sen, note, created_at, expected_delivery_date`；排序：pending 按 created_at 旧到新（先来先做），其他按 created_at 新到旧 |
| `get_delivery_summary(p_wholesaler_id uuid, p_date date default null)` | jsonb | 见 2.3 |

`get_order(p_order_id)`（第三步已有）批发商也能用：`actions.can_confirm / can_mark_delivering / can_mark_delivered`，`shop {name,address,phone,contact_name,zone_name}`。

全部检查：`is_wholesaler_member(p_wholesaler_id) or is_admin()`，否则 `NOT_ALLOWED`。

### 2.3 当天送货总结 `get_delivery_summary`

`p_date` 空就是 `today_myt()`。包括 `expected_delivery_date = p_date` 且状态是 confirmed / delivering 的订单；另外回传同一天还在 pending 的数量（提醒「还有 N 张没确认」）。

```json
{
  "date": "2026-11-26",
  "wholesaler": {"id": "...", "name": "...", "phone": "..."},
  "order_count": 3,
  "pending_count": 1,
  "goods_total_sen": 45600,
  "shipping_total_sen": 1600,
  "total_sen": 47200,
  "picking": [ {"name": "16安士 PP杯 95口径", "unit": "carton", "pack_qty": 1000, "qty": 5} ],
  "orders": [
    {
      "id": "...", "order_no": "JHB261126-00012", "status": "confirmed",
      "shop": {"name": "...", "contact_name": "...", "phone": "60...", "address": "...", "zone_name": {"zh":"..","en":"..","ms":".."}},
      "items": [ {"name": "...", "unit": "carton", "pack_qty": 1000, "qty": 2, "is_out_of_stock": false} ],
      "goods_subtotal_sen": 17000, "shipping_fee_sen": 800, "total_sen": 17800,
      "note": null, "payment_terms": ["cod","transfer"]
    }
  ]
}
```

- `picking` = 所有订单里**没缺货**的明细按 (name, unit, pack_qty) 加总，给仓库拣货。
- `orders` 按送货区（zone sort_order）再按店名排，方便送货员排路线。

### 2.4 商品（批发商直接读写 `products` 表）

RLS 已经允许批发商改自己的商品（`wholesaler_id` 受保护不能改）。App 直接 `select/insert/update`。不需要新函数。上架 = `status = 'active'`，下架 = `archived`。

### 2.5 价目表导入

流程：App 上传文件到 Storage `price-lists/<wholesaler_id>/<uuid>.<ext>` → 插入 `price_list_imports`（status `processing`，RLS 允许）→ 调用 Edge Function `parse-price-list` `{import_id}` → 函数写入 `price_list_import_rows`，再叫 `suggest_import_matches`，状态改成 `review`（失败就 `failed` + `error_message`）→ App 显示每一行让批发商改 → 调用 `apply_price_list_import` 上架。

| 函数 | 谁用 | 说明 |
|---|---|---|
| `suggest_import_matches(p_import_id uuid)` | service | 每一行：在**同一家批发商**的商品里找名字最像的（`similarity(lower(name))`，> 0.45）→ `matched_product_id` 并把 `action` 设为 `update`；没有就 `create`。再在标准商品里找最像的（zh/en/ms 三个名字取最高，> 0.3）→ `suggested_catalog_item_id`。资料不完整（没价钱或没名字）的行 `action = 'skip'`。回传 `{rows, matched, suggested}` |
| `apply_price_list_import(p_import_id uuid)` | 批发商 / 客服 | 只接受 status = `review`。`create` 行：需要 name、unit、pack_qty、price_sen，否则 `IMPORT_ROW_INCOMPLETE`（detail = row_no）；新增商品 `status = 'active'`，`catalog_item_id = suggested_catalog_item_id`，`category_id` 跟着标准商品，`min_order_qty` 默认 1。`update` 行：改 matched 商品的 `price_sen`（以及有填的 `min_order_qty`、`unit`、`pack_qty`），`status` 设 active。`skip` 不动。最后 import `status = 'applied'`、`applied_at = now()`。回传 `{created, updated, skipped}` |

批发商在 App 里改行：直接 update `price_list_import_rows`（RLS 已允许）。

### 2.6 通知发送（只给 service）

| 函数 | 说明 |
|---|---|
| `claim_notifications(p_limit int default 50)` | 领走 `status = 'queued'` 或（`failed` 且 `attempts < 5` 且 `next_attempt_at <= now()`）的通知，`for update skip locked`，设为 `sending`、`claimed_at = now()`。另外把 `sending` 超过 10 分钟的当成卡住，重新领。回传 jsonb array，每个：`{id, event_type, payload, locale, channel, push_tokens[], whatsapp_phone, details}`。`channel` 规则见下。`details`：订单类事件附上订单资料（见下） |
| `complete_notification(p_id uuid, p_status notification_status, p_channel notification_channel, p_error text default null, p_wa_message_id text default null)` | `sent / failed / skipped`。`attempts + 1`；failed 时 `next_attempt_at = now() + (2^attempts) 分钟`；sent 时 `sent_at = now()`；WhatsApp 发出的写一行 `whatsapp_messages`（outbound、template、关联 order_id） |
| `remove_device_tokens(p_tokens text[])` | 删除 FCM 说已失效的 token |

**选渠道（channel）**：收件人是批发商 / 店铺 / 用户：

1. `notify_channel = 'whatsapp'` → WhatsApp（有号码才行）。
2. `notify_channel = 'push'` → 推送（没 token 就 skipped）。
3. `auto`（默认）→ 有任何成员的 `device_tokens`（`last_seen_at` 60 天内）→ 推送；否则有 WhatsApp 号码 → WhatsApp；都没有 → `channel = null`，dispatcher 标 `skipped`。
4. 用户（`user_id`，例如客服提醒）→ 只有推送。
5. `daily_summary` 和 `order_unconfirmed` 不走 WhatsApp（避免按条收费；没装 App 的批发商每张单都已经收到 WhatsApp）。

**`details`（订单类事件 `order_new / order_status_changed / order_cancelled`）**：
`{order_id, order_no, status, shop_name, shop_address, shop_phone, wholesaler_name, items_text, item_count, total_sen, expected_delivery_date, out_of_stock_count}`，`items_text` 例如 `16安士 PP杯 95口径 x2 箱; 95 平盖 x1 箱`（单位按收件人语言，最多 900 字）。

`locale`：收件人是批发商 / 店铺就用它的 `locale`；用户就用 profile 的。

### 2.7 WhatsApp 回传（只给 service）

| 函数 | 说明 |
|---|---|
| `handle_whatsapp_button(p_from text, p_payload text, p_wa_message_id text, p_raw jsonb default null)` | 先用 `wa_message_id` 写 `whatsapp_messages`（inbound，`button`）；重复的（同一个 id 已经有）直接回 `{"result":"duplicate"}`。`p_payload` 格式 `CONFIRM:<order_uuid>` 或 `OOS:<order_uuid>`，其他回 `invalid_payload`。找订单；**发信人号码（normalize 后）必须是这家批发商的 phone / whatsapp_phone 或其成员的 profile phone**，否则回 `not_authorized`（不改任何东西）。订单是 pending：CONFIRM → `confirm_order(order, '{}', 'whatsapp')`；OOS → `set_order_status(order, 'out_of_stock', null, 'whatsapp')`。不是 pending → `already_<status>`。回传 `{result: confirmed|out_of_stock|already_confirmed|..., order_no, status, locale}`，Edge Function 用它回一句确认文字 |
| `record_whatsapp_message(p_from text, p_type wa_message_type, p_body text, p_media_id text, p_wa_message_id text, p_raw jsonb)` | 其他进来的消息（文字、语音……）只记录，按号码对上 shop / wholesaler；重复 id 忽略。第六步再处理成订单草稿 |
| `update_whatsapp_status(p_wa_message_id text, p_status text, p_error text default null)` | 更新 outbound 消息的 `delivery_status`（sent / delivered / read / failed） |

### 2.8 定时任务（`pg_cron`，有才建）

| 名称 | 时间（UTC） | 做什么 |
|---|---|---|
| `daily-delivery-summary` | `30 21 * * *`（马来西亚 05:30） | `enqueue_daily_summaries()`：每家 active 批发商，今天有要送的单（或还有 pending 的今天单）→ 插一条 `daily_summary` 通知，payload `{date, order_count, pending_count, total_sen}` |
| `unconfirmed-order-alerts` | `*/5 * * * *` | `enqueue_unconfirmed_alerts()`：pending 超过 `app_settings.order_confirm_alert_minutes` 且 `unconfirmed_alert_at is null` 的订单 → 给每个客服（role admin）插 `order_unconfirmed` 通知，设 `unconfirmed_alert_at` |
| `dispatch-notifications` | `* * * * *` | 用 `pg_net` 叫 Edge Function `dispatch-notifications`（重试和补漏）。另外 `notifications` 新增时用 trigger 立刻叫一次（`pg_net` 是异步的，不会拖慢下单） |

Edge Function 的网址和钥匙放在 Supabase Vault（名字 `project_url`、`dispatch_secret`），迁移里**不写死**；没有 Vault / pg_net 就跳过（本机测试环境）。

### 2.9 Storage（有 `storage` schema 才建）

| bucket | 公开 | 规则 |
|---|---|---|
| `price-lists` | 否 | 第一层文件夹 = wholesaler_id；该批发商成员可上传 / 读取；客服全部；10 MB；image/jpeg, image/png, image/webp, application/pdf, xlsx, xls, csv |
| `product-photos` | 是（读） | 第一层文件夹 = wholesaler_id；成员可上传 / 删除；5 MB；图片 |

### 2.10 测试（`supabase/tests/database/06_seller.test.sql`）

至少覆盖：批发商首页数字；只看到自己的订单；送货总结（拣货加总不含缺货、排序）；导入比对和上架（create / update / skip / 不完整报错 / 别家不能上架）；claim 选渠道（有 token → push；没 token 有 WhatsApp → whatsapp；notify_channel 强制；daily_summary 不走 WhatsApp）、重复领不到、complete 重试时间；WhatsApp 按钮（确认、缺货、重复、号码不对不改、已经处理过）；客服提醒；daily summary 排程函数；service 函数普通用户不能调用。

## 3. Edge Functions（`supabase/functions/`，Deno + TypeScript）

```
supabase/functions/
  _shared/            env.ts、supabase.ts、fcm.ts、whatsapp.ts、claude.ts、spreadsheet.ts、messages.ts（三语通知文字）、http.ts
  dispatch-notifications/index.ts
  whatsapp-webhook/index.ts
  parse-price-list/index.ts
  tests/              deno test：纯逻辑都要有测试（签名验证、payload 解析、通知文字、价目表结果整理、Excel 转文字），外部 API 用假的 fetch
```

- **dispatch-notifications**：只接受带正确 `x-dispatch-secret`（等于环境变量 `DISPATCH_SECRET`）的请求。`claim_notifications(50)` → 每条按 channel 发 → `complete_notification`。推送失效的 token 收集起来 `remove_device_tokens`。一次跑不完就循环到没得领或快超时。
- **whatsapp-webhook**：GET 做验证握手（`WHATSAPP_VERIFY_TOKEN`）；POST 先验 `X-Hub-Signature-256`（`WHATSAPP_APP_SECRET`，用原始 body），不对就 401。按钮 → `handle_whatsapp_button` → 成功就回一句文字（客户刚发消息，24 小时内免费回复）；其他消息 → `record_whatsapp_message`；状态 → `update_whatsapp_status`。永远尽快回 200（Meta 会重送）。
- **parse-price-list**：用户的 JWT 叫（`supabase.functions.invoke`）。用用户身份读 import（RLS 保证是自己的），用 service 身份下载文件、写行。图片 / PDF → Claude（`claude-opus-5-5`，结构化输出）；Excel / CSV → 先转成文字表格再给 Claude 整理。写完叫 `suggest_import_matches`，status → `review`；出错 → `failed`。
- 环境变量：`SUPABASE_URL`、`SUPABASE_SERVICE_ROLE_KEY`（或新的 secret key）、`DISPATCH_SECRET`、`FCM_SERVICE_ACCOUNT_JSON`、`WHATSAPP_TOKEN`、`WHATSAPP_PHONE_NUMBER_ID`、`WHATSAPP_APP_SECRET`、`WHATSAPP_VERIFY_TOKEN`、`ANTHROPIC_API_KEY`。没设定的服务就跳过并在日志说明（例如没 WhatsApp 设定 → 那些通知标 failed + 原因）。

## 4. App（`apps/mobile`，批发商登录后）

| 路由 | 页面 | 一件事 |
|---|---|---|
| `/seller` | 首页：大按钮「新订单（N）」「今天要送（N）」「商品和价钱」「上传价目表」；待审核时上面显示提示 | 选要做的事 |
| `/seller/orders?tab=pending\|today\|all` | 订单列表（pending 先来先做） | 选一张单 |
| `/seller/orders/:id` | 订单详情：店名、地址、电话（可以打电话 / WhatsApp）、明细；底部两个大按钮「确认」「缺货」；按「确认」前可以勾选哪几样缺货；已确认 → 「出发送货」/「已送达」 | 确认或缺货 |
| `/seller/summary?date=` | 今天要送：拣货单 + 每张单（按区、按店）；「打印」（PDF，有中文字体）、「分享给送货员」（文字，发 WhatsApp） | 打印 / 分享 |
| `/seller/products` | 商品列表：名字、价钱、库存（颜色 + 文字）；搜索 | 选一样商品 |
| `/seller/products/:id`、`/seller/products/new` | 改价钱（数字键盘）、库存三个大按钮（有货 / 快卖完 / 缺货）、起订量、上架 / 下架 | 保存 |
| `/seller/import` | 选「拍照」「选照片」「选文件（Excel / PDF）」→ 上传 → 等 AI | 上传 |
| `/seller/import/:id` | 一行一行：AI 读到的名字、单位、包装数量、价钱，可以改；每行「新增 / 更新（对到哪样商品）/ 跳过」；底部「确认上架（N 样）」 | 确认上架 |
| `/seller/settings` | 语言、通知方式（App 推送 / WhatsApp）、登出 | 设定 |

- **推送**：`firebase_messaging`。用 `--dart-define` 传 Firebase 设定（`FIREBASE_API_KEY`、`FIREBASE_APP_ID`、`FIREBASE_MESSAGING_SENDER_ID`、`FIREBASE_PROJECT_ID`、iOS 另有 `FIREBASE_IOS_BUNDLE_ID`），没传就不启用推送（App 照样能用）。登录后拿 token → `register_device_token`；token 更新也要登记。点通知 → 按 `data.type` / `data.order_id` 打开订单或送货总结。买家也一样登记（第三步的状态通知）。
- **示范模式**：`main_demo.dart?seller=1` 进批发商端，数据来自 `packages/core/test/fixtures/seller_*.json`（从本机数据库导出的真实回传）。
- **测试**：`flutter test` 加批发商流程（首页、确认含部分缺货、缺货、送货总结、改价、导入确认上架），手机宽度 400 不能 overflow。
- **三语文字**：新 key 都以 `seller` 开头，三个 `.arb` 都要有，键名一致。

## 5. 外部服务细节

见 `docs/04-research.md`（查证后填写）。
