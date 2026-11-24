# 第一步：整体架构、数据库表设计、开发步骤

> 状态：设计稿，还没写代码。第二步会照这份设计写数据库迁移文件（SQL）和 RLS。
> 第 5 节有几个问题要你先确认，每个都附了建议答案。

**一句话：** 小店老板打开 App，比较几家批发商的价钱，一键下单；批发商确认后自己送货。平台不经手货款也不管物流，收入来自买家月费和批发商佣金。

---

## 1. 整体架构

### 1.1 组成部分

| 部分 | 用什么 | 负责什么 |
|---|---|---|
| 手机 App | Flutter（iOS + Android）。只做**一个** App，登录后按角色显示买家界面或批发商界面 | 浏览、比价、下单、接单、语音下单 |
| 客服后台 | Flutter Web（和 App 共用数据模型和多语言文字） | 代操作、看全部订单、订阅管理、佣金报表和账单 |
| 后端 | Supabase：Postgres 数据库 + RLS、Auth（手机号 + 验证码登录）、Storage（照片、录音、价目表、账单 PDF）、Edge Functions（TypeScript）、pg_cron（定时任务） | 数据、权限、所有跟钱有关的计算 |
| 推送 | Firebase Cloud Messaging | 新订单、订单状态、每日总结、提醒 |
| WhatsApp | WhatsApp Business Platform（Cloud API） | 只给没装 App 的人：收订单、发订单给批发商 |
| AI | Claude API（模型 `claude-opus-5-5`）+ 语音转文字服务 | 读价目表照片/Excel、把文字或语音转成订单草稿 |
| 收费 | 马来西亚付款网关（FPX、DuitNow、电子钱包），第七步再选哪家 | 买家月费、批发商上架费、佣金账单 |

### 1.2 一张订单怎么走

1. 老板在 App 选好货，按「下单」→ App 调用数据库函数 `place_order`。服务器**重新查**价钱、运费、起订量，不相信手机传来的数字。
2. 购物车里有 3 家批发商的货 → 拆成 3 张订单，每张有自己的运费和状态。
3. 每张订单放进「通知队列」→ 发送函数判断：批发商有装 App → 推送；没装 → WhatsApp 模板消息（带「确认」「缺货」按钮）。
4. 批发商按「确认」（App 里按，或在 WhatsApp 里按）→ 订单变成「已确认」→ 推送给老板。
5. 送达后 → 系统自动生成一条佣金记录 → 每月 1 号汇总成上个月的佣金账单。

### 1.3 定时任务（pg_cron，马来西亚时间）

| 什么时候 | 做什么 |
|---|---|
| 每天早上 6:00 | 给每家批发商发当天要送的订单总结（可以打印给送货员） |
| 每 5 分钟 | 新订单超过 30 分钟没人确认 → 后台提醒客服打电话跟进 |
| 每天 | 检查试用和订阅到期，发提醒；过了宽限期的订阅改成「已停」 |
| 每月 1 号 | 生成上个月每家批发商的佣金账单 |

### 1.4 设计原则（之后每一步都照这个做）

1. **钱只在服务器算。** 货价、运费、总额、佣金都由数据库函数计算，App 只负责显示。
2. **不该看到的价钱根本不发到手机。** 未付费用户看到的模糊价钱，服务器返回的是空值，App 只是画一个模糊方块。如果只在画面上加模糊效果，懂一点技术的人截一下网络数据就能看到真价钱。
3. **下单时拍快照。** 订单明细保存当时的商品名、单位、价钱；佣金记录保存当时的比例。批发商之后改价、我们之后改佣金比例，都不影响旧订单和旧账单。
4. **店铺、批发商跟登录账号分开。** 没装 App 的老板和批发商也有一条店铺/批发商记录（有 WhatsApp 号码），只是没有登录账号，客服可以替他们操作。以后他们装了 App，用同一个手机号登录就自动接上原来的记录。
5. **每个动作都记下是谁做的。** 订单有 `source`（App / 语音 / WhatsApp / 客服 / 重复下单）和 `created_by`；客服代操作写进 `audit_logs`，出纠纷时查得到。
6. **推送优先，WhatsApp 兜底。** 所有通知走同一个队列，按「有没有装 App」选渠道，WhatsApp 费用才不会失控。
7. **地区和行业是数据，不是代码。** 「新山」和「餐饮打包耗材」各是表里的一行。以后加槟城或者干货行业，不用改代码。
8. **金额用「仙」存整数。** RM12.50 存成 `1250`，避免小数误差。时间统一用 `Asia/Kuala_Lumpur`。
9. **三种语言。** 界面文字放在 Flutter 的 ARB 文件（zh / en / ms）；分类名这类系统数据存成 `{"zh": "...", "en": "...", "ms": "..."}`；批发商自己写的商品名照原文显示。

### 1.5 「比 WhatsApp 还简单」的界面规则

- 字最小 18sp；主要按钮全宽、高度至少 56dp
- 每页只有一个主要动作（一个大按钮）
- 数量用 ＋ / － 按钮，不用打字
- 图标旁边一定有文字
- 第一次打开先选语言：「华文 / English / Bahasa Melayu」三个大按钮
- 登录只要手机号 + 验证码，没有密码
- 订单状态用颜色**加**文字（例：绿色「已送达」），不能只靠颜色

### 1.6 代码仓库结构（建议）

```
apps/mobile/            Flutter 手机 App（买家 + 批发商）
apps/admin_web/         Flutter Web 客服后台
packages/core/          共用：数据模型、Supabase 调用、多语言文字、金额格式
supabase/migrations/    数据库表、RLS、数据库函数（SQL）
supabase/functions/     Edge Functions：推送、WhatsApp、AI、付款回调、账单
supabase/seed.sql       测试数据（新山送货区、打包耗材分类、几家假批发商）
docs/                   设计文档和提示词
```

主要 Flutter 套件：`supabase_flutter`、`firebase_messaging`、`go_router`（页面跳转）、`flutter_riverpod`（状态管理）、`flutter_localizations` + `intl`（多语言）、`record`（录音）、`image_picker`（拍价目表）、`printing`（打印每日总结）。

---

## 2. 数据库表设计

下面只列主要字段，完整的字段类型、约束和索引在第二步的 SQL 里。

### 2.1 基础设定

| 表 | 用途 | 主要字段 |
|---|---|---|
| `regions` | 地区 | `code`（`JHB`）、`name`（三语）、`is_active` |
| `delivery_zones` | 地区里的送货区，例如 Skudai、Tebrau、Mount Austin、Johor Jaya | `region_id`、`name`、`postcodes`（邮区列表） |
| `industries` | 行业和它的佣金比例 | `code`（`food_packaging`）、`name`、`default_commission_rate`、`founding_commission_rate` |
| `categories` | 商品分类：杯、盖、饭盒、塑料袋、吸管、纸巾…… | `industry_id`、`parent_id`、`name`（三语）、`sort_order` |
| `app_settings` | 全局设定 | 试用天数（14）、创始批发商名额（100）、创始上架费（RM100）、续费宽限天数 |

### 2.2 用户、店铺、批发商

| 表 | 用途 | 主要字段 |
|---|---|---|
| `profiles` | 每个登录账号一行，对应 Supabase 的 `auth.users` | `id`、`full_name`、`phone`、`role`（buyer / seller / admin）、`locale`（zh / en / ms） |
| `shops` | 买家的店 | `name`、`shop_type`（餐馆 / 饮料店 / 杂货店 / 其他）、`zone_id`、`address`、`phone`、`whatsapp_phone`、`notify_channel`、`created_by` |
| `shop_members` | 哪些账号可以操作这家店 | `shop_id`、`user_id`、`member_role`（owner / staff） |
| `wholesalers` | 批发商 | `name`、`industry_id`、`region_id`、`phone`、`whatsapp_phone`、`notify_channel`、`status`（pending 待审核 / active / suspended）、`is_founding`、`founding_no`（1–100）、`commission_rate_override`、`rating_avg`、`rating_count`、`order_cutoff_time`、`payment_terms` |
| `wholesaler_members` | 哪些账号可以操作这家批发商 | `wholesaler_id`、`user_id`、`member_role` |
| `wholesaler_delivery_zones` | 每家批发商送哪些区、运费多少 | `wholesaler_id`、`zone_id`、`shipping_fee_sen`、`free_shipping_min_sen`（满多少免运费，可空）、`min_order_sen`（最低消费，可空）、`lead_time_days`（几天送到）、`delivery_weekdays` |
| `device_tokens` | 推送用的手机 token | `user_id`、`fcm_token`、`platform`、`last_seen_at` |

- `notify_channel`：`auto`（默认，有装 App 就推送，没有就 WhatsApp）/ `push` / `whatsapp`。有些批发商装了 App 但还是习惯看 WhatsApp，客服可以手动改。
- `payment_terms` 只做显示（货到付款 / 转账 / 月结）。**货款平台不经手**，老板和批发商自己结算。
- 一家店可以有几个人用（老板 + 员工），表先支持，第一阶段界面只做老板一个人。

### 2.3 商品

比价的关键：不同批发商卖的「同一样东西」要能对在一起。所以分成「标准商品」和「批发商的商品」两层。

| 表 | 用途 | 主要字段 |
|---|---|---|
| `catalog_items` | 标准商品，例：「16oz PP 透明杯（95mm 口径）」 | `category_id`、`name`（三语）、`spec`（容量、材质、尺寸、颜色）、`base_unit`（个 / 条 / 卷）、`image_path` |
| `products` | 批发商实际在卖的商品 | `wholesaler_id`、`catalog_item_id`（对应哪个标准商品，可空）、`name`（批发商自己的叫法）、`photo_paths`、`unit`（箱 / 包 / 条）、`pack_qty`（一个单位有几个）、`price_sen`、`min_order_qty`（起订量）、`stock_status`（有货 / 少量 / 缺货）、`lead_time_days_override`（可空）、`status`（draft 草稿 / active 上架 / archived 下架） |
| `product_price_history` | 改价记录 | `product_id`、`old_price_sen`、`new_price_sen`、`changed_by`、`changed_at` |
| `price_list_imports` | 上传的价目表（照片 / PDF / Excel） | `wholesaler_id`、`file_path`、`file_type`、`status`（处理中 / 待确认 / 已上架 / 失败）、`created_by` |
| `price_list_import_rows` | AI 识别出来的每一行，等人确认 | `import_id`、`raw_text`、识别出的名称 / 单位 / 包装数量 / 价钱、`matched_product_id` 或 `catalog_item_id`、`action`（新增 / 改价 / 跳过）、`confidence` |

- **比价看「每个多少钱」**：A 家 1000 个一箱 RM85（每个 8.5 仙），B 家 50 个一包 RM4.80（每个 9.6 仙）。只比箱价或包价会误导老板，所以要有 `pack_qty`。
- **送货地区和送货时间放在批发商层级**（`wholesaler_delivery_zones`），商品上只有一个可选的覆盖值。同一家批发商的货一般一起送，要批发商逐个商品填，他们会嫌麻烦。
- `catalog_items` 由客服维护。AI 导入价目表时会建议对应哪个标准商品，由人确认。

### 2.4 购物车和订单

| 表 | 用途 | 主要字段 |
|---|---|---|
| `cart_items` | 购物车（放在服务器，客服也能帮老板加货） | `shop_id`、`product_id`、`qty`、`added_by` |
| `checkouts` | 一次结账，可能包含几家批发商。「跟上次一样」就是复制最近一次结账 | `shop_id`、`created_by`、`source`、`goods_total_sen`、`shipping_total_sen` |
| `orders` | 每家批发商一张订单 | `order_no`、`checkout_id`、`shop_id`、`wholesaler_id`、`zone_id`、`status`、`goods_subtotal_sen`、`shipping_fee_sen`、`total_sen`、`expected_delivery_date`、`note`、`source`（app / voice / whatsapp / admin / reorder）、`created_by`、`confirmed_at`、`delivered_at`、`cancel_reason` |
| `order_items` | 订单明细（下单时的快照） | `order_id`、`product_id`、`name_snapshot`、`unit_snapshot`、`pack_qty_snapshot`、`unit_price_sen`、`qty`、`line_total_sen`、`is_out_of_stock` |
| `order_status_events` | 状态变化记录，App 里的进度条靠它显示 | `order_id`、`from_status`、`to_status`、`actor_id`、`channel`（app / whatsapp / admin / system）、`created_at` |

**订单状态：**

```
待确认 ──「确认」──▶ 已确认 ──▶ 送货中 ──▶ 已送达
  │
  ├──「缺货」──▶ 缺货（整张单都没货）
  └──「取消」──▶ 已取消（送货前，老板或客服可以取消）
```

- **部分缺货**：批发商把其中几样标「缺货」，其他照送 → 订单还是「已确认」，金额自动重算，老板收到通知。
- 状态只能通过数据库函数 `set_order_status()` 改，函数会检查谁可以从哪个状态改到哪个状态。
- **运费**：按老板店铺所在的送货区查 `wholesaler_delivery_zones`；达到免运费金额就是 0；没达到最低消费不能下单，界面显示「还差 RM xx」。

### 2.5 评价

| 表 | 用途 | 主要字段 |
|---|---|---|
| `reviews` | 一张已送达的订单可以评一次 | `order_id`（唯一）、`shop_id`、`wholesaler_id`、`rating`（1–5）、`tags`（准时、货好、包装好……一键点选）、`comment` |

只有「已送达」的订单可以评价，防止刷分。写入后由触发器自动更新 `wholesalers.rating_avg` 和 `rating_count`。

### 2.6 订阅和收费

| 表 | 用途 | 主要字段 |
|---|---|---|
| `pricing_plans` | 买家月费的价目历史 | `amount_sen`（5000 = RM50）、`effective_from`、`effective_to` |
| `subscriptions` | 每家店的订阅 | `shop_id`、`status`（trialing 试用 / active 有效 / past_due 逾期 / lapsed 已停）、`started_at`（开始日期）、`trial_ends_at`、`locked_price_sen`（锁定的月费）、`is_founding_price`（是不是创始价）、`current_period_end`、`grace_until`、`lapsed_at` |
| `trial_claims` | 防止同一个手机号重复拿试用 | `phone`（唯一）、`shop_id`、`claimed_at` |
| `unlocked_wholesalers` | 未付费用户可以完整看到的 3 家批发商 | `shop_id`、`wholesaler_id`、`unlocked_at` |
| `payments` | 收到的每一笔钱 | `payer_type`（shop / wholesaler）、`payer_id`、`purpose`（subscription / listing_fee / commission_invoice）、`reference_id`、`amount_sen`、`gateway`、`method`（fpx / duitnow / ewallet）、`gateway_ref`、`status`、`paid_at` |
| `commission_records` | 每张已送达订单一条佣金记录 | `order_id`（唯一）、`wholesaler_id`、`period_month`、`base_amount_sen`（货价，不含运费）、`rate`、`rate_source`（单独调整 / 创始 / 行业默认）、`commission_sen`、`invoice_id` |
| `commission_invoices` | 每家批发商每月一张佣金账单 | `invoice_no`、`wholesaler_id`、`period_month`、`order_count`、`gmv_sen`、`commission_sen`、`status`（草稿 / 已发出 / 已付 / 逾期）、`due_date`、`pdf_path` |

**「价钱跟着账号锁定」怎么落到表里：**

1. 注册 → 建一条订阅，状态「试用」，`locked_price_sen` = 当天 `pricing_plans` 的价钱。
2. 一直按时续费 → 一直用同一条记录，`locked_price_sen` 不变。
3. 到期没付 → 「逾期」。宽限期内（建议 7 天）补付，原价保留。
4. 过了宽限期 → 「已停」。之后回来 → **新建**一条订阅，按当时的价钱锁定。
5. 数据库保证每家店同时只有一条没停的订阅。

第二步提示词里的「是否锁定创始价」和第七步的「价钱跟着账号锁定」合并成同一套规则：每个账号都锁定注册时的价钱，`is_founding_price` 只是标记他是不是早期 RM50 那一批，方便后台筛选。

**佣金比例怎么取**（从上到下，用第一个有值的）：批发商单独调整的比例 → 创始会员比例（`is_founding` 的批发商）→ 行业默认比例。比例在生成佣金记录时就存下来。

### 2.7 WhatsApp、语音、AI

| 表 | 用途 | 主要字段 |
|---|---|---|
| `whatsapp_messages` | 所有进出的 WhatsApp 消息 | `direction`（in / out）、`wa_message_id`、`phone`、`shop_id` 或 `wholesaler_id`、`type`（text / audio / button / template）、`body`、`media_path`、`template_name`、`order_id`、`delivery_status` |
| `order_drafts` | AI 转出来的订单草稿 | `shop_id`、`source`（app_voice / whatsapp_text / whatsapp_voice）、`audio_path`、`transcript`、`parsed_lines`（JSON：哪样商品、多少、AI 有多确定）、`status`（待确认 / 已确认 / 作废）、`reviewed_by`、`checkout_id` |

App 里语音下单，草稿由老板自己确认；WhatsApp 下单，草稿由客服在后台确认。

### 2.8 通知和操作记录

| 表 | 用途 | 主要字段 |
|---|---|---|
| `notifications` | 通知队列 | 收件人（user / shop / wholesaler）、`event_type`（新订单、状态变化、每日总结、试用快到期、新账单……）、`payload`、`channel`（push / whatsapp）、`status`（排队 / 已发 / 失败）、`attempts` |
| `audit_logs` | 谁改了什么 | `actor_id`、`acting_for`（代哪家店或批发商）、`action`、`table_name`、`record_id`、`before`、`after`、`created_at` |

### 2.9 权限（RLS）概要

三个辅助函数：`is_admin()`、`my_shop_ids()`、`my_wholesaler_ids()`。

| 数据 | 买家 | 批发商 | 客服 |
|---|---|---|---|
| 订单、订单明细、状态记录 | 自己店的 | 发给自己的 | 全部 |
| 商品 | 已上架的（价钱走专用函数，见下面） | 自己的，可以改 | 全部 |
| 店铺资料 | 自己的 | 给自己下过单的店（名字、地址、电话，送货要用） | 全部 |
| 订阅、付款 | 自己的 | 自己的上架费和佣金付款 | 全部 |
| 佣金记录、佣金账单 | 看不到 | 自己的 | 全部 |
| 评价 | 大家都能看；只能评自己已送达的订单 | 能看 | 全部 |
| 订单草稿 | 自己的 | 看不到 | 全部 |
| WhatsApp 消息、操作记录 | 看不到 | 看不到 | 全部 |

- **重要动作不让 App 直接改表。** 下单、改状态、算佣金、订阅变化，只能调用数据库函数或 Edge Function，函数里先检查权限再写。
- **价钱模糊：** 买家不能直接查 `products.price_sen`，要通过 `get_offers()` 这类函数拿价钱。函数判断：试用中或已付费 → 返回全部价钱；未付费 → 只返回 `unlocked_wholesalers` 里那 3 家的价钱，其他返回空值。
- **客服代操作：** 客服调用的是同一批函数，多传一个「代谁操作」的参数，函数检查 `is_admin()`，并写入 `audit_logs`。

---

## 3. 外部服务和要注意的地方

### 3.1 推送和 WhatsApp

- 新订单、状态变化、每日总结：有装 App 的人用 FCM 推送（不收钱）。
- 没装 App 的批发商：发 WhatsApp 模板消息（模板要先通过 Meta 审核），附「确认」「缺货」快捷按钮。批发商按了以后，WhatsApp 回传给我们的服务器，直接改订单状态。
- 老板主动发 WhatsApp 来下单：我们在之后的客服对话时段内回复他，通常比主动发模板消息便宜。Meta 的收费规则常常改，上线前再核对一次。
- 新订单 30 分钟没人确认：提醒客服打电话，不自动连发 WhatsApp。

### 3.2 AI

- **价目表：** 照片和 PDF 直接交给 Claude 读；Excel 先在服务器解析成表格，再交给 Claude 整理。结果用固定的 JSON 格式输出，全部存成草稿，人确认后才上架。
- **语音：** Claude 不直接听录音。先用语音转文字服务转成文字，再交给 Claude，配合这家店以前买过什么、批发商有什么货，转成订单草稿。
- **最大的技术风险是福建话（还有广东话）的语音识别。** 华语、英文、马来文问题不大，但大部分语音服务对福建话（特别是新马口音）识别得不准。建议做第六步之前，先录 20–30 段新山老板真实的下单语音，拿去测几家服务再决定用哪家。识别不准时，退回「显示文字，让老板自己改」。

### 3.3 收费（第七步细做）

- 付款网关要支持 FPX、DuitNow、电子钱包，月费最好还能自动扣款。第七步比较几家再定。
- 买家月费能不能用网页付款：Apple 和 Google 对「在 App 里解锁的数字服务」一般要求用应用内购买，这会影响第三步「模糊价钱 + 升级」的做法。第七步我先查最新规定再详细回答。在那之前，第三步的模糊画面**先不放付款按钮**，免得之后要拆掉。

### 3.4 要提前办的事（要几个星期，建议现在就开始）

- 公司注册（SSM）：付款网关和 WhatsApp Business 认证都要用
- Apple Developer 账号（每年 USD 99）、Google Play 开发者账号（一次 USD 25）
- Meta Business 认证、WhatsApp Business 号码、消息模板审核
- 付款网关商户申请
- 短信验证码服务（Supabase 的手机号登录要接 Twilio 这类短信服务商）
- 税务：佣金账单和订阅收据可能要符合 LHDN e-Invoice（MyInvois）和 SST 规定，按营业额有门槛，上线前问会计
- 隐私：按 PDPA 写隐私政策，特别要说明语音录音保存多久

---

## 4. 开发步骤

照 `docs/prompts.md` 的七步走，每步做完测试通过再做下一步。

| 步骤 | 做什么 | 做完怎么验收 |
|---|---|---|
| 1 | 架构和表设计（本文件） | 你确认第 5 节的问题 |
| 2 | 数据库：建表、RLS、核心函数（下单、改状态、算运费、算佣金）、新山测试数据 | 自动测试通过，例如「买家 A 看不到买家 B 的订单」「未付费用户拿不到第 4 家的价钱」 |
| 3 | 先搭 Flutter 骨架（手机号登录、三语、大字主题、按角色进首页），再做买家端 | 用测试数据从比价走到下单、看状态、评价 |
| 4 | 批发商端、推送、WhatsApp 接单模板 | 下单后批发商手机收到推送，按「确认」后老板收到通知 |
| 5 | 客服后台 | 客服代一家店下单、代批发商改价，操作记录查得到 |
| 6 | 语音下单、WhatsApp 下单 | 用真实录音测识别率；用 WhatsApp 测试号码走完整个流程 |
| 7 | 收费 | 在付款网关测试环境走完：试用 → 付费 → 续费 → 停 → 回来按新价 |
| 8 | 试点上线 | 新山 5–10 家批发商、20–30 家店，客服在旁边陪着用 |

---

## 5. 做第二步之前请你确认

每题都有建议答案，同意的话直接回「照建议」就可以。

1. **未付费用户的「三家批发商」怎么选？**
   建议：老板自己选 3 家（第一次会自动填他买过的那几家），每个月可以换一次。
2. **未付费用户能不能下单？**
   建议：可以，但只能向这 3 家下单。
3. **佣金按什么金额算？**
   建议：只算已送达的货价，不含运费；缺货和取消的不算。
4. **续费宽限期多久？**
   建议：7 天。宽限期内补付，保留原来锁定的价钱。
5. **批发商能不能自己注册上架？**
   建议：可以自己注册，但要客服审核通过后才出现在买家面前。
