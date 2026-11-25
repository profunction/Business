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
- `notifications` 加 `next_attempt_at timestamptz`（失败重试的时间）、`claimed_at timestamptz`、`wa_message_id text`（发出去的 WhatsApp 消息 id）。
- `orders` 加 `unconfirmed_alert_at timestamptz`（提醒过客服的时间）。
- `device_tokens` 加 `kind text not null default 'token' check (kind in ('token','fid'))`：Firebase 2026 年开始改用 Firebase Installation ID（FID），旧的 registration token 还能用；两种都要能存。`register_device_token(p_token, p_platform)` 加第三个参数 `p_kind text default 'token'`（旧的两个参数版本要删掉，免得重载混乱）。
- `wholesalers`、`shops` 加 `whatsapp_opt_in_at timestamptz`：Meta 规定要先取得对方同意才能发 WhatsApp。没有这个时间就**不发** WhatsApp（客服在第五步的后台登记；批发商自己在 App 设定里打开「用 WhatsApp 收订单」也会设）。
- `whatsapp_messages` 加 `from_user_id text`（2026 年起 Meta 的用户 ID「BSUID」，有些用户没有电话号码只有这个）、`context_wa_message_id text`（按钮是按在哪一条消息上）、`error_code int`。`phone` 改成可以是空的。加索引 `(context_wa_message_id)`。
- 扩展 `pg_trgm`（商品名比对；`create extension if not exists pg_trgm with schema extensions`，函数里用 `extensions.similarity(...)`）。

### 2.2 批发商读取（App 用，`authenticated`）

| 函数 | 回传 | 说明 |
|---|---|---|
| `get_seller_home(p_wholesaler_id uuid)` | jsonb | `wholesaler {id,name,status,is_founding,notify_channel}`、`pending_count`、`oldest_pending_at`、`today` (日期)、`today_order_count`（今天要送：confirmed/delivering 且 expected_delivery_date = today）、`today_total_sen`、`product_counts {active, draft, out_of_stock, low_stock}`、`latest_import {id,status,created_at}` 或 null |
| `list_seller_orders(p_wholesaler_id uuid, p_statuses order_status[] default null, p_delivery_date date default null, p_limit int default 50)` | jsonb array | 每张：`id, order_no, status, shop_name, zone_name (三语), item_count, out_of_stock_count, goods_subtotal_sen, shipping_fee_sen, total_sen, note, created_at, expected_delivery_date`；排序：pending 按 created_at 旧到新（先来先做），其他按 created_at 新到旧 |
| `get_delivery_summary(p_wholesaler_id uuid, p_date date default null)` | jsonb | 见 2.3 |

`get_order(p_order_id)`（第三步已有）批发商也能用：`actions.can_confirm / can_mark_delivering / can_mark_delivered`，`shop {name,address,phone,contact_name,zone_name}`。

全部检查：`is_wholesaler_member(p_wholesaler_id) or is_admin()`，否则 `NOT_ALLOWED`。

> **实现说明**：`product_counts.out_of_stock / low_stock` 只算上架中（active）的商品。`list_seller_orders` 混在一起时 pending 排最前面；`p_limit` 限制在 1–200；`p_statuses` 是空数组等于不筛选。批发商不存在（客服调用时）→ `WHOLESALER_NOT_FOUND`。

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

> **实现说明**：`items` 另外多给 `unit_price_sen`、`line_total_sen`（送货单可以印价钱），缺货的那几样也列出来（`is_out_of_stock = true`，排在后面）。`shop.phone`、`wholesaler.phone` 没有就用 `whatsapp_phone`。

### 2.4 商品（批发商直接读写 `products` 表）

RLS 已经允许批发商改自己的商品（`wholesaler_id` 受保护不能改）。App 直接 `select/insert/update`。不需要新函数。上架 = `status = 'active'`，下架 = `archived`。

### 2.5 价目表导入

流程：App 上传文件到 Storage `price-lists/<wholesaler_id>/<uuid>.<ext>` → 插入 `price_list_imports`（status `processing`，RLS 允许）→ 调用 Edge Function `parse-price-list` `{import_id}` → 函数写入 `price_list_import_rows`，再叫 `suggest_import_matches`，状态改成 `review`（失败就 `failed` + `error_message`）→ App 显示每一行让批发商改 → 调用 `apply_price_list_import` 上架。

| 函数 | 谁用 | 说明 |
|---|---|---|
| `suggest_import_matches(p_import_id uuid)` | service | 每一行：在**同一家批发商**的商品里找名字最像的（`similarity(lower(name))`，> 0.45）→ `matched_product_id` 并把 `action` 设为 `update`；没有就 `create`。再在标准商品里找最像的（zh/en/ms 三个名字取最高，> 0.3）→ `suggested_catalog_item_id`。资料不完整（没价钱或没名字）的行 `action = 'skip'`。回传 `{rows, matched, suggested}` |
| `apply_price_list_import(p_import_id uuid)` | 批发商 / 客服 | 只接受 status = `review`。`create` 行：需要 name、unit、pack_qty、price_sen，否则 `IMPORT_ROW_INCOMPLETE`（detail = row_no）；新增商品 `status = 'active'`，`catalog_item_id = suggested_catalog_item_id`，`category_id` 跟着标准商品，`min_order_qty` 默认 1。`update` 行：改 matched 商品的 `price_sen`（以及有填的 `min_order_qty`、`unit`、`pack_qty`），`status` 设 active。`skip` 不动。最后 import `status = 'applied'`、`applied_at = now()`。回传 `{created, updated, skipped}` |
| `reserve_price_list_run(p_import_id uuid, p_user_id uuid, p_run_id uuid)` | service（parse-price-list） | 迁移 `20261127000200_seller_hardening.sql`。一个交易里：锁批发商那一行（同一家排队）→ 锁导入 → 按顺序检查，第一个不符合就回传、什么都不改：`{"result":"not_found"}`、`not_member`（p_user_id 不是成员 owner / staff，也不是客服）、`suspended`（只有 active / pending 能跑；叫的人或建这家批发商的人是一家停权批发商的老板、或建了那一家，也是 suspended）、`{"result":"not_processing","status":...}`、`already_running`（`ai_raw.state = running` 且 `claimed_at` 10 分钟内）、`{"result":"quota","window":"burst\|hour\|day","retry_after_sec":N}`。都通过 → `ai_raw = {version:1, state:running, run_id, claimed_at, claimed_by}`、`error_message = null`、记一笔 `price_list_runs`，回传 `{result:"ok", run_id, claimed_at, wholesaler_id, wholesaler_status, import_id, file_path, file_type}`。用量（`price_list_runs` 算，数字只在 `_price_list_run_limits()`）：active 10 分钟 3 次 / 1 小时 10 次 / 1 天 30 次，pending 2 / 4 / 8，照这家批发商的状态；三份各算各的、哪一份满了都挡：这家批发商、叫的人（在每一家跑的加起来）、建这家批发商的人（`created_by`，他建的每一家加起来）；客服不算「人」。所以一直注册新的批发商不会多出用量（`register_wholesaler` 也改成一个人同时只能有一家待审核的，否则 `WHOLESALER_ALREADY_PENDING`，detail = 那一家；客服不限制）。同一个人同时进来的在 advisory lock 排队，再锁批发商那一行（`for no key update`）、导入（`for update`）。N = 要等几秒才有位置（≥ 1，进位；几份、几段都满回传要等最久的）。`p_run_id` 空 → `INVALID_RUN_ID`，用过 → `RUN_ID_USED` |
| `fail_stuck_price_list_imports()` | service / 定时任务 | 还是 processing 的：在跑（`ai_raw.state = running`）且 `claimed_at` 超过 15 分钟 → `failed` + `AI_TIMEOUT`；没人在跑且 15 分钟没人动过（`updated_at`，没改过就是建的时间）→ `failed` + `START_FAILED`。`ai_raw` 原来的资料留着，加 `state = failed`、`error`、`interrupted = 'sweep'`、`finished_at`；删掉那份导入的行；另外删两天前的 `price_list_runs`。回传标了几份 |

批发商在 App 里改行：直接 update `price_list_import_rows`（RLS 已允许）。

**导入本身的保护**（trigger `price_list_imports_guard`，`20261127000200`）：批发商（authenticated）新增时只能 `status = processing`，`ai_raw` / `error_message` / `applied_at` 要是空的，`created_by` 空的或自己（设成自己，`created_at` 设成现在）；修改时 `wholesaler_id`、`file_path`、`file_type`、`ai_raw`、`applied_at`、`created_by`、`created_at`（和 `id`）不能改，状态只能 `processing → failed`，而且 `error_message` 是 App 自己的代码（`START_FAILED`、`NETWORK`、`AUTH`）；其他 → `COLUMN_PROTECTED`（42501，detail = 哪一栏）。服务器、security definer 函数（`apply_price_list_import`、`reserve_price_list_run`……）、客服不检查（跟 `protect_columns` 一样）。所以用量、占位都不能被批发商自己改掉。

> **实现说明**
> - **相似度**：数据库 locale 是 C 时（本机测试、部分主机）pg_trgm 不把中文字当成字，「95 平盖」和「95 拱形盖」会被当成一模一样。所以全英文 / 数字的名字用 `extensions.similarity(lower(...))`；有中文等其他文字的用同样的三字组规则自己切（`_name_trgms` / `_trgm_sim` / `_name_similarity`，中文字也算字，全形字母数字当半形）。两种算法对英文名字结果完全一样（有测试）。
> - **尺寸数字**：包装材料不同尺寸的名字通常只差一个数字（12oz / 16oz 杯、90mm / 95mm 盖），相似度会超过 0.45（只看 0.45 的话，价目表多了一个新尺寸，确认上架时会把新尺寸的价钱写到旧尺寸的商品上）。所以两边名字里的数字（`_name_numbers`：全形当半形，016 = 16，6.50 = 6.5）要**一边包含另一边**才算同一样：「95 平盖」和「95 平盖 1000个」可以，12oz 和 16oz、90 和 95 不行（那一行变 `create`）。标准商品的建议也照这个规则。
> - **一对一**：一样商品只对给最像的那一行（其他行变 `create`），一样像时单位和包装数量也相同的优先；下架（archived）的商品也会对，但排在后面（`update` 时会重新上架）。没价钱的行也会算出对到哪样，方便批发商补上价钱后改成 `update`。
> - **错误代码**：`IMPORT_NOT_FOUND`；`suggest_import_matches` 遇到已上架的 → `IMPORT_ALREADY_APPLIED`；`apply` 不是 review → `IMPORT_NOT_IN_REVIEW`（detail = 现在的状态）；`update` 行也要有 `matched_product_id` 和 `price_sen`，否则 `IMPORT_ROW_INCOMPLETE`；对到的商品不是这家批发商的（行是批发商自己可以改的）→ `IMPORT_ROW_INVALID_PRODUCT`；两行 `update` 同一样商品 → `IMPORT_DUPLICATE_PRODUCT`。detail 都是 row_no。

### 2.6 通知发送（只给 service）

| 函数 | 说明 |
|---|---|
| `claim_notifications(p_limit int default 50, p_claim_id uuid default null)` | `p_claim_id`（`20261127000200`）：dispatcher 每次一个新的 uuid，领到的记在 `notifications.claim_id`，release / complete 要带同一个。领走 `status = 'queued'` 或（`failed` 且 `attempts < 5` 且 `next_attempt_at <= now()`）的通知，`for update skip locked`，设为 `sending`、`claimed_at = now()`。另外把 `sending` 超过 10 分钟的当成卡住，重新领。**同一个 WhatsApp 号码一次只领一条**（Meta 对同一个收件人大约每 6 秒只能发 1 条），其他的留在 queued 下一轮再发。回传 jsonb array，每个：`{id, event_type, payload, locale, channel, push_targets: [{target, kind}], whatsapp_phone, details}`。`channel` 规则见下。`details`：订单类事件附上订单资料（见下） |
| `complete_notification(p_id uuid, p_status notification_status, p_channel notification_channel, p_error text default null, p_wa_message_id text default null, p_retry boolean default true, p_claim_id uuid default null)` | `sent / failed / skipped`。failed / skipped 要 `claim_id` 对得上（领着的那个 dispatcher；都是 null 也算），对不上回 false 不改（别人已经重新领走了）；sent 不看 claim id（真的发出去了）。`attempts + 1`；failed 且 `p_retry` 时 `next_attempt_at = now() + (2^attempts) 分钟`，`p_retry = false`（永久失败，例如号码不在 WhatsApp、模板没批准）就不再重试（attempts 设为 5）；sent 时 `sent_at = now()`、记下 `wa_message_id`；WhatsApp 发出的写一行 `whatsapp_messages`（outbound、template、关联 order_id、`wa_message_id`、收件 shop / wholesaler） |
| `remove_device_tokens(p_tokens text[])` | 删除 FCM 说已失效的 token / FID |
| `release_notification(p_id uuid, p_claim_id uuid default null)` | `20261127000200`。dispatcher 领了、但时间不够没开始发的那条放回队列：`sending` 而且 `claim_id` 对得上 → `queued`，`claimed_at`、`next_attempt_at`、`claim_id` 清掉，下一次 claim 马上又领到，不算失败、`attempts` 不变（claim 只在「卡住重新领」时加 1，那是算之前卡住的那一次，不扣回去）。回传 boolean：不是 `sending`、或是别人领的 → false 不改；没有这条 → `NOTIFICATION_NOT_FOUND`。为什么要 claim id：放回去其实成功了、回应在路上断了，dispatcher 退回去用 complete 标失败，那条可能已经被别的 dispatcher 领走在发 |

**选渠道（channel）**：收件人是批发商 / 店铺 / 用户：

「可以发 WhatsApp」= 有 `whatsapp_phone`（没有就用 `phone`）**而且** `whatsapp_opt_in_at` 不是空的。

1. `notify_channel = 'whatsapp'` → WhatsApp（可以发才发，否则 skipped）。
2. `notify_channel = 'push'` → 推送（没 token 就 skipped）。
3. `auto`（默认）→ 有任何成员的 `device_tokens`（`last_seen_at` 60 天内）→ 推送；否则可以发 WhatsApp → WhatsApp；都没有 → `channel = null`，dispatcher 标 `skipped`。
4. 用户（`user_id`，例如客服提醒）→ 只有推送。
5. `daily_summary` 和 `order_unconfirmed` 不走 WhatsApp（避免按条收费；没装 App 的批发商每张单都已经收到 WhatsApp）。

**`details`（订单类事件 `order_new / order_status_changed / order_cancelled`）**：
`{order_id, order_no, status, shop_name, shop_address, shop_phone, wholesaler_name, items_text, item_count, total_sen, expected_delivery_date, out_of_stock_count}`，`items_text` 例如 `16安士 PP杯 95口径 x2 箱; 95 平盖 x1 箱`（单位按收件人语言，最多 900 字）。

`locale`：收件人是批发商 / 店铺就用它的 `locale`；用户就用 profile 的。

> **实现说明**
> - `claim_notifications` 每条多回传 `attempts`；`push_targets` 只在 `channel = push` 时有内容（否则 `[]`），`whatsapp_phone` 只在 `channel = whatsapp` 时有值。领走时就把选好的 `channel` 存进 `notifications.channel`（complete 会再覆盖）。
> - 同号码只领一条：同一轮、同时在跑的另一个 dispatcher（advisory lock）、这个号码还有 WhatsApp 在「发送中」（10 分钟内）都算，留着下一轮。每一轮只锁要领的行数，不会把整个队列锁住。
> - 卡住（`sending` 超过 10 分钟）重新领时算失败一次；到 5 次就直接标 `failed`、`last_error = 'STUCK_IN_SENDING'`。
> - `notify_channel = 'whatsapp'` 但事件是 `daily_summary` / `order_unconfirmed` → `channel = null`（不改用推送）。
> - `details`：payload 里有 `order_id` 的通知都附上（也包括 `order_unconfirmed`）。`items_text` 缺货的那样加「（缺货）/ (out of stock) / (habis stok)」，名字里的换行和连续空白变成一个空格（WhatsApp 模板参数不能有），超过 900 字就截到某一样为止，后面加「; …」。
> - `complete_notification` 回传 boolean：只改「发送中」的那条（true）；不是发送中就不改（false），但 WhatsApp 发出去的那一行照样写进 `whatsapp_messages`（按钮 context 要对得到）。重试时间用加 1 之后的 attempts：2、4、8、16 分钟，第 5 次失败就不再试。错误代码：`INVALID_STATUS`、`NOTIFICATION_NOT_FOUND`。`remove_device_tokens` 回传删了几个。
> - `register_device_token`：错误代码 `INVALID_TOKEN`、`INVALID_TOKEN_KIND`、`INVALID_PLATFORM`。

### 2.7 WhatsApp 回传（只给 service）

| 函数 | 说明 |
|---|---|
| `handle_whatsapp_button(p_from text, p_from_user_id text, p_context_id text, p_payload text, p_wa_message_id text, p_raw jsonb default null)` | 先用 `wa_message_id` 写 `whatsapp_messages`（inbound，`button`）；重复的（同一个 id 已经有）直接回 `{"result":"duplicate"}`（Meta 会重送 webhook 长达 7 天）。`p_payload` 格式 `CONFIRM:<order_uuid>` 或 `OOS:<order_uuid>`，其他回 `invalid_payload`。找订单；**授权**：`p_from`（normalize 后）是这家批发商的 phone / whatsapp_phone 或其成员的 profile phone；或者 `p_from` 是空的（用户只有 BSUID），但 `p_context_id` 是我们发给**这家批发商、这张订单**的那条 outbound 消息。都不符合就回 `not_authorized`（不改任何东西）。订单是 pending：CONFIRM → `confirm_order(order, '{}', 'whatsapp')`；OOS → `set_order_status(order, 'out_of_stock', null, 'whatsapp')`。不是 pending → `already_<status>`。回传 `{result: confirmed|out_of_stock|already_confirmed|..., order_no, status, locale}`，Edge Function 用它回一句确认文字 |
| `record_whatsapp_message(p_from text, p_type wa_message_type, p_body text, p_media_id text, p_wa_message_id text, p_raw jsonb)` | 其他进来的消息（文字、语音……）只记录，按号码对上 shop / wholesaler；重复 id 忽略。第六步再处理成订单草稿 |
| `update_whatsapp_status(p_wa_message_id text, p_status text, p_error_code int default null, p_error text default null)` | 更新 outbound 消息的 `delivery_status`（sent / delivered / read / failed / played）。状态可能乱序到达：不要把 read 改回 delivered（顺序 sent < delivered < read；failed 永远覆盖） |

> **实现说明**
> - `handle_whatsapp_button` 多一个结果：找不到订单 → `order_not_found`；`invalid_payload` / `order_not_found` / `not_authorized` 只回 `{result, locale}`（locale 是按号码认出的发信人的，认不出是 null；不透露订单资料）。号码有给但对不上时不看 context（照规格）。
> - `record_whatsapp_message` 回传 `{result: recorded|duplicate, id, shop_id, wholesaler_id}`；BSUID 和 context 从 `p_raw.from_user_id`、`p_raw.context.id` 取；媒体 id 记在 `raw.media_id`（第六步下载后再填 `media_path`）。
> - `update_whatsapp_status` 回传 `{result: updated|stale|ignored, delivery_status}`；`played` 排在 `read` 后面；不认识的状态 → `ignored`。还没记录的 id（状态比 `complete_notification` 先到）先建一行 outbound，之后 complete 会补上订单和收件人。`failed` 时错误文字记在 `raw.status_error`，也写进对应通知的 `last_error`。

### 2.8 定时任务（`pg_cron`，有才建）

| 名称 | 时间（UTC） | 做什么 |
|---|---|---|
| `daily-delivery-summary` | `30 21 * * *`（马来西亚 05:30） | `enqueue_daily_summaries()`：每家 active 批发商，今天有要送的单（或还有 pending 的今天单）→ 插一条 `daily_summary` 通知，payload `{date, order_count, pending_count, total_sen}` |
| `unconfirmed-order-alerts` | `*/5 * * * *` | `enqueue_unconfirmed_alerts()`：pending 超过 `app_settings.order_confirm_alert_minutes` 且 `unconfirmed_alert_at is null` 的订单 → 给每个客服（role admin）插 `order_unconfirmed` 通知，设 `unconfirmed_alert_at` |
| `dispatch-notifications` | `* * * * *` | 用 `pg_net` 叫 Edge Function `dispatch-notifications`（重试和补漏）。另外 `notifications` 新增时用 trigger 立刻叫一次（`pg_net` 是异步的，不会拖慢下单） |
| `fail-stuck-price-list-imports` | `*/5 * * * *` | `fail_stuck_price_list_imports()`：卡在 processing 的导入标成失败（见 2.5）。由 `_schedule_seller_hardening_jobs()` 建（`20261127000200`，同名会更新，可以重复跑） |

Edge Function 的网址和钥匙放在 Supabase Vault（照官方「Scheduling Edge Functions」的名字：`project_url`、`secret_key`），迁移里**不写死**，部署时在 SQL editor 用 `vault.create_secret(...)` 建。调用：`net.http_post(url := <project_url> || '/functions/v1/dispatch-notifications', headers := jsonb_build_object('Content-Type','application/json','apikey', <secret_key>), body := '{}'::jsonb, timeout_milliseconds := 10000)`（**一定用具名参数**；新的 secret key 不是 JWT，要放 `apikey` 头，不是 Authorization）。没有 Vault / pg_net / 秘密还没建 → 跳过不报错（本机测试环境也是这样）。`create extension if not exists pg_net with schema extensions` 要放在检查可用之后。

> **实现说明**：`enqueue_daily_summaries()`、`enqueue_unconfirmed_alerts()` 只给 service，回传插了几条（几张单）；同一天 / 同一张单重复跑不会重复发；还没有客服账号时订单先不标记。叫 dispatcher 的是 `_request_notification_dispatch(p_only_if_due boolean default false)`（Vault / pg_net / 秘密缺任何一样就回 null，出错也只记 warning）；trigger 是每个 insert 语句叫一次；每分钟的定时任务用 `p_only_if_due = true`，没有要发的通知就不叫。定时任务由 `_schedule_seller_jobs()` 建（同名会更新）。

### 2.9 Storage（有 `storage` schema 才建）

| bucket | 公开 | 规则 |
|---|---|---|
| `price-lists` | 否 | 第一层文件夹 = wholesaler_id；该批发商成员可上传 / 读取；客服全部；10 MB；image/jpeg, image/png, image/webp, application/pdf, xlsx, xls, csv |
| `product-photos` | 是（读） | 第一层文件夹 = wholesaler_id；成员可上传 / 删除；5 MB；图片 |

> **实现说明**：由 `_setup_seller_storage()` 建（可以重复跑；没有 storage schema 回 false）。两个 bucket 共用一组 `storage.objects` 规则：第一层文件夹（`(storage.foldername(name))[1]`）等于自己批发商 id 的文字才可以读 / 上传 / 改 / 删；客服全部。`product-photos` 允许 image/jpeg、image/png、image/webp；公开读靠 bucket 的 public。

### 2.10 测试（`supabase/tests/database/06_seller.test.sql`）

至少覆盖：批发商首页数字；只看到自己的订单；送货总结（拣货加总不含缺货、排序）；导入比对和上架（create / update / skip / 不完整报错 / 别家不能上架）；claim 选渠道（有 token → push；没 token 有 WhatsApp → whatsapp；notify_channel 强制；daily_summary 不走 WhatsApp）、重复领不到、complete 重试时间；WhatsApp 按钮（确认、缺货、重复、号码不对不改、已经处理过）；客服提醒；daily summary 排程函数；service 函数普通用户不能调用。

加固（`07_seller_hardening.test.sql`）：`price_list_runs` 只给服务器；`reserve_price_list_run` 每一种结果（含占位超过 10 分钟重新占位、active / pending 三段用量、`retry_after_sec` 的秒数、几段都满取最久）；保护 trigger（App 的 createImport / markImportFailed 照样可以，每一种不能改的都 `COLUMN_PROTECTED`，service_role 和 `apply_price_list_import` 不受影响）；`fail_stuck_price_list_imports` 两种情况、删行、删旧用量、不动新的和不是 processing 的（看 `updated_at` 不是 `created_at`；新增时 `updated_at` 也设成现在）；用量按「人」算、`register_wholesaler` 一家待审核、停权老板的新批发商；删掉导入用量留着；检查顺序和 `retry_after_sec` 进位；`release_notification` 和 claim id；定时任务（真的 Supabase 先检查迁移建好的）。两个连线同时进来的（dblink，只在本机跑）：同一家 / 同一个人 / 同一个人建的两家同时占位会排队、不多放；锁批发商不挡新增导入；App 标失败时占位等那一行；定时任务跳过正在占位的；complete 和 release 同时。

## 3. Edge Functions（`supabase/functions/`，Deno + TypeScript）

```
supabase/functions/
  _shared/            env.ts、supabase.ts、fcm.ts、whatsapp.ts、claude.ts、spreadsheet.ts、messages.ts（三语通知文字）、http.ts
  dispatch-notifications/index.ts
  whatsapp-webhook/index.ts
  parse-price-list/index.ts
  tests/              deno test：纯逻辑都要有测试（签名验证、payload 解析、通知文字、价目表结果整理、Excel 转文字），外部 API 用假的 fetch
```

- **全部函数 `verify_jwt = false`**（`supabase/config.toml` 的 `[functions.<name>]`），在代码里自己检查身份：新的 secret / publishable key 不是 JWT，平台的 JWT 检查对它们不可靠。
- 每个函数有自己的 `deno.json`（imports），入口 `index.ts` 用 `export default { fetch: handler }`（测试可以直接 import，不会开端口）。
- **dispatch-notifications**：只接受 `apikey` 头等于 secret key（`JSON.parse(SUPABASE_SECRET_KEYS).default`，没有就退回旧的 `SUPABASE_SERVICE_ROLE_KEY`）的请求，比较要用固定时间比较。`claim_notifications(50)` → 每条按 channel 发 → `complete_notification`。推送失效的 token 收集起来 `remove_device_tokens`。一次跑不完就循环到没得领或快超时。领到了但时间不够、还没开始发的那几条用 `release_notification(id)` 放回队列（不要标 failed：不算一次失败，下一次马上再领；回 false = 已经不是发送中，不用管）。放不回去（数据库出错）才退回旧的做法 `complete_notification(failed, 'DISPATCH_TIME_BUDGET', retry = true)`。每次 dispatch 一个新的 claim id，claim / release / complete 都带（`p_claim_id`）：出错时其实可能已经放回去、又被别的 dispatcher 领走了，退回的标失败对不上就不改。`beforeunload` 时领到还没开始发的马上放回去（不等正在发的）。放回去的这一次不再领（留给下一次 trigger / 每分钟的定时任务）。
- **whatsapp-webhook**：GET 做验证握手（`WHATSAPP_VERIFY_TOKEN`）；POST 先验 `X-Hub-Signature-256`（`WHATSAPP_APP_SECRET`，用原始 body），不对就 401。按钮 → `handle_whatsapp_button` → 成功就回一句文字（客户刚发消息，24 小时内免费回复）；其他消息 → `record_whatsapp_message`；状态 → `update_whatsapp_status`。永远尽快回 200（Meta 会重送）。
- **parse-price-list**：App 用 `supabase.functions.invoke('parse-price-list', body: {import_id})` 叫（自动带用户 JWT）。函数先验用户（`auth.getUser(jwt)`；JWT 不对 → 401 `UNAUTHORIZED`，Auth 服务自己出问题（断线、5xx、429、回的不是 JSON）→ 503 `AUTH_UNAVAILABLE`，暂时的、不是登录过期），再**用用户身份**读 import（RLS 保证是自己的），读不到 → 404（不叫数据库函数）。状态、占位和用量只用一个数据库函数 `reserve_price_list_run(import_id, user.id, 新的 run_id)`（见 2.5；不再用 Storage 记次数、不再自己 PATCH 占位）：`not_found` / `not_member` → 404 `IMPORT_NOT_FOUND`，`suspended` → 403 `WHOLESALER_SUSPENDED`，`not_processing` → 409 `IMPORT_NOT_PROCESSING`，`already_running` → 409 `IMPORT_ALREADY_RUNNING`，`quota` → 429 `TOO_MANY_IMPORTS`（`retry_after`、`window`、`Retry-After` 头 = `retry_after_sec`），叫不到（数据库出错、断线、回传认不得）→ 503 `QUOTA_UNAVAILABLE`（暂时的，import 没动）；不跑的都没占位、不算次数。`ok` 才跑，之后写回 import 都要 `status = processing` 而且用回传的 `run_id` 过滤（定时任务已经标失败的不会被盖掉）、`claimed_at` 照回传的写。设定（时间预算、Claude 钥匙）在叫 reserve 之前读好；`PRICE_LIST_TIME_BUDGET_MS` 最多 540000（比「在跑超过 10 分钟可以重新占位」短）。卡住的由定时任务 `fail_stuck_price_list_imports` 收拾（15 分钟）。全部 HTTP 回应见 `supabase/functions/README.md`。然后**立刻回 202**，用 `EdgeRuntime.waitUntil` 在背景做（Opus 读价目表可能超过 150 秒）：用 service 身份下载文件（大小上限 10 MB），用**魔术字节**判断真正格式（不信档名 / MIME）；图片（jpeg / png / webp / gif）、PDF → Claude；xlsx / xls / csv → SheetJS 0.20.3 转成带行号的文字（`Sheet!R12: ...`，表头标 `[context]`，太长就分段、每段重复表头）再给 Claude（xlsx 先检查 zip：解压后太大 / 压缩比太夸张 → `FILE_TOO_LARGE`，zip 坏掉 → `SPREADSHEET_UNREADABLE`，不交给 SheetJS；表长过 4800 行或商品超过 1200 样 → `TOO_MANY_ROWS`，不会悄悄少掉后面的商品）；HEIC 等不支持的格式 → `failed`，`error_message = 'UNSUPPORTED_FILE'`。Claude：`npm:@anthropic-ai/sdk@1.13.0`，`claude-opus-5-5`，`client.beta.messages.stream(...).finalMessage()`，`output_config: {format: {type:'json_schema', schema}, effort: 'medium'}`，`max_tokens: 32000`，伺服器端 fallback（`betas: ['server-side-fallback-2026-07-01']`、`fallbacks: 'default'`），不送 temperature；先看 `stop_reason`（refusal → failed `AI_REFUSED`；max_tokens → 分段重试一次，再不行 failed `AI_TRUNCATED`），把全部 text block 照顺序接起来 `JSON.parse`（streaming 中途被拒绝时 fallback 模型从断掉的地方接着写，JSON 会分在 fallback block 前后；接起来 parse 不了才试 fallback block 之后的文字）再验证（unit 转小写、不在列表的当 piece 并降低 confidence、confidence 夹在 0..1、price_sen / pack_qty 必须是正整数否则 null）。提示词和 schema 用 `docs/research/step4/claude.json` 的版本（已核对），价目表内容包在 `<pasted_content>` 里。写入 `price_list_import_rows`（row_no 从 1 开始；`unreadable` 的也写成行：只有 raw_text，`action = 'skip'`），`ai_raw` 存整份回传，再叫 `suggest_import_matches`，status → `review`。任何错误 → `failed` + 简短 `error_message`（英文代码），不要把内部错误细节给用户。
- 环境变量：平台自动给 `SUPABASE_URL`、`SUPABASE_SECRET_KEYS`、`SUPABASE_PUBLISHABLE_KEYS`（JSON，取 `default`；旧项目退回 `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_ANON_KEY`）。自己设：`FCM_SERVICE_ACCOUNT_JSON`、`WHATSAPP_TOKEN`（system user 永久 token）、`WHATSAPP_PHONE_NUMBER_ID`、`WHATSAPP_APP_SECRET`、`WHATSAPP_VERIFY_TOKEN`、`WHATSAPP_GRAPH_VERSION`（默认 `v27.0`）、`ANTHROPIC_API_KEY`。名字不能以 `SUPABASE_` 开头。没设定的服务就跳过并在日志说明（例如没 WhatsApp 设定 → 那些通知标 failed + 原因，`p_retry = false`）。

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

- **推送**：`firebase_core` 5.2.0 + `firebase_messaging` 17.1.0 + `flutter_local_notifications` 23.x。Firebase 设定用 `--dart-define`（`FIREBASE_API_KEY`、`FIREBASE_APP_ID_ANDROID`、`FIREBASE_APP_ID_IOS`、`FIREBASE_MESSAGING_SENDER_ID`、`FIREBASE_PROJECT_ID`、`FIREBASE_IOS_BUNDLE_ID`）组成 `FirebaseOptions`；没传就不启用推送（App 照样能用；web 永远不启用）。正式上线前建议跑 `flutterfire configure` 产生 `google-services.json`（Android 背景推送最稳），文件里写清楚。用 **FID**：先订阅 `onRegistered` 再 `register()`，拿到的值 → `register_device_token(p_token, p_platform, 'fid')`；Android manifest / iOS Info.plist 加 FID 开关。前台：自己用 `flutter_local_notifications` 显示（Android 频道 `orders`，高重要性）；iOS `setForegroundNotificationPresentationOptions`。点通知（`getInitialMessage`、`onMessageOpenedApp`、本地通知的 payload）→ 按 `data.type` / `data.order_id` 打开订单或送货总结。买家也一样登记。Android：`compileSdk` 37、core library desugaring；iOS 加 Push / Background Modes 要在 Xcode 做（写进文件）。
- **价目表上传**：照片用 `image_picker`（`maxWidth: 2576, imageQuality: 85` → JPEG，解决 HEIC）；文件用 `file_picker` 13 的静态 API；用魔术字节判断格式；路径 `<wholesaler_id>/<uuid>.<ext>`（ASCII）；上传后插 `price_list_imports`，再叫 `parse-price-list`；收到 202 后每 3 秒查一次 import 的 status（最多 5 分钟），`review` → 进确认页，`failed` → 按 `error_message` 显示三语原因（看不懂的档案 / AI 读不到 / 网络）。
- **打印**：`pdf` 3.13.1 + `printing` 5.15.1，字体打包 `assets/google_fonts/NotoSansSC-Regular.ttf`、`-Bold.ttf`（TTF，Google Fonts 下载）；`share_plus` 13 分享文字；`url_launcher` 打电话 / WhatsApp（try/catch）。iOS Info.plist 加相机 / 相簿说明。
- **示范模式**：`main_demo.dart?seller=1` 进批发商端，数据来自 `packages/core/test/fixtures/seller_*.json`（从本机数据库导出的真实回传）。
- **测试**：`flutter test` 加批发商流程（首页、确认含部分缺货、缺货、送货总结、改价、导入确认上架），手机宽度 400 不能 overflow。
- **三语文字**：新 key 都以 `seller` 开头，三个 `.arb` 都要有，键名一致。

## 5. 外部服务细节

见 [`docs/04-research.md`](04-research.md)（已查证，含出处）。实现时以它为准；跟它冲突的地方先回来改这份规格。

### 5.1 WhatsApp 模板（要在 WhatsApp Manager 送审，三种语言 `zh_CN` / `en` / `ms`）

| 模板名 | 分类 | 变量（named） | 按钮 |
|---|---|---|---|
| `order_new_v1` | UTILITY | `order_no`、`shop_name`、`items`、`total`、`delivery_date`、`address` | quick reply：0 = 确认，1 = 缺货（payload 由我们每条消息给） |
| `order_status_v1` | UTILITY | `order_no`、`wholesaler_name`、`status_text`、`total` | 无 |
| `order_cancelled_v1` | UTILITY | `order_no`、`shop_name`、`reason` | 无 |

内文范例和送审注意事项写在 `docs/04-seller.md`（交付文件）。dispatch 函数里模板名、变量名放在 `_shared/messages.ts` 一个地方。按钮按下后的回复用**普通文字**（窗口内、前 1,000 条免费），三语，例如「✅ 已确认订单 JHB261126-00012」。
