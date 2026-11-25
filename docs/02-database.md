# 第二步：数据库

> 状态：完成，122 项自动测试全部通过（`./scripts/test-db.sh`）。
> 表的设计说明在 [`01-architecture.md`](01-architecture.md) 第 2 节，这里讲做出来的东西怎么用。

## 1. 文件

| 文件 | 内容 |
|---|---|
| `supabase/config.toml` | Supabase 项目设定：开了手机号 + 验证码登录，本机有 4 个测试号码 |
| `supabase/migrations/…100_base.sql` | 地区、送货区、行业、分类、全局设定、用户、店铺、批发商 |
| `supabase/migrations/…200_catalog.sql` | 标准商品、批发商的商品、改价记录、价目表导入 |
| `supabase/migrations/…300_orders.sql` | 购物车、结账、订单、订单明细、状态记录、评价 |
| `supabase/migrations/…400_billing.sql` | 月费价目、订阅、试用、免费可看的批发商、付款、佣金、佣金账单 |
| `supabase/migrations/…500_messaging.sql` | WhatsApp 消息、AI 订单草稿、通知队列、操作记录 |
| `supabase/migrations/…600_access_control.sql` | 权限：辅助函数、受保护字段、每张表的 RLS 规则 |
| `supabase/migrations/…700_business_logic.sql` | 业务函数：注册、看价钱、报价、下单、改状态、佣金、评价、账单、订阅维护 |
| `supabase/migrations/…800_schedules_realtime.sql` | 定时任务、实时更新 |
| `supabase/seed.sql` | 新山 8 个送货区、打包耗材 9 个分类、12 样标准商品、月费 RM50，加上示范数据 |
| `supabase/tests/database/*.test.sql` | 4 个测试文件，共 122 项 |
| `scripts/test-db.sh` | 不用 Docker 的一键测试 |

## 2. 权限是怎么保证的

- **每张表都开了 RLS**（有一项测试专门检查，以后漏开会直接失败）。
- 买家只看到自己店的订单，批发商只看到发给自己的订单，客服看到全部。
- **商品表买家不能直接查**：价钱一定要经过 `get_offers()`，由它决定这家店看不看得到价钱。看不到的，服务器返回空值。
- **订单不能直接写**：连客服也只能通过下面的函数下单、改状态，金额、状态、佣金才不会对不上。
- **受保护字段**：用户可以改自己的资料，但有些字段只有客服能改，例如自己的角色、批发商的审核状态、佣金比例、评分。
- **客服做的每个改动**都自动写进 `audit_logs`，包括「代哪家店 / 哪家批发商」。

## 3. App 要调用的函数

Flutter 里用 `supabase.rpc('函数名', params: {...})` 调用。每个函数里面都会再检查是谁在调用。

### 买家

| 函数 | 做什么 |
|---|---|
| `register_shop(p_name, p_zone_id, …)` | 注册店铺，自动开 14 天试用（一个手机号只送一次），月费按当天价钱锁定 |
| `get_subscription_status(p_shop_id)` | 有没有全部功能、试用到哪天、锁定的月费、免费可看的批发商、什么时候可以再换 |
| `set_unlocked_wholesalers(p_shop_id, p_wholesaler_ids)` | 未付费用户选免费可看的 3 家 |
| `get_offers(p_shop_id, p_catalog_item_id, p_wholesaler_id, p_category_id, p_search)` | 看商品和比价：每个多少钱、评分、运费、起订量、几天送到 |
| `quote_cart(p_shop_id)` | 「确认下单」页：按批发商分组的货价 + 运费 = 总额，每一行有没有问题 |
| `place_order(p_shop_id, p_expected_total_sen, p_note, p_source)` | 下单。`p_expected_total_sen` 传老板看到的总额，对不上就拒绝（不会多收钱） |
| `reorder_last(p_shop_id)` | 「跟上次一样」：把上次的货放回购物车，返回新报价、改了价的、买不到的 |
| `set_order_status(p_order_id, 'cancelled', p_note)` | 取消（待确认或已确认时） |
| `set_order_status(p_order_id, 'delivered')` | 「收到了」 |
| `submit_review(p_order_id, p_rating, p_tags, p_comment)` | 评价已送达的订单（可以改） |

购物车直接读写 `cart_items` 表（RLS 只让买家碰自己店的）。

### 批发商

| 函数 | 做什么 |
|---|---|
| `register_wholesaler(p_name, p_region_id, p_industry_id, …)` | 自己注册，状态「待审核」 |
| `confirm_order(p_order_id, p_out_of_stock_item_ids)` | 一键「确认」，可以顺便标出哪几样缺货；全部缺货就变成「缺货」 |
| `set_order_status(p_order_id, 'out_of_stock' / 'delivering' / 'delivered')` | 整单缺货、送货中、已送达 |

商品、运费、送货区直接读写 `products`、`wholesaler_delivery_zones` 表（只能改自己的）。

### 大家都用

| 函数 | 做什么 |
|---|---|
| `register_device_token(p_token, p_platform)` | 登记推送 token |

### 客服和定时任务

| 函数 | 做什么 |
|---|---|
| `start_trial(p_shop_id)` | 帮没装 App 的店开试用 |
| `generate_commission_invoices(p_period_month)` | 生成佣金草稿账单（默认上个月；每月 1 号自动跑） |
| `run_subscription_maintenance()` | 试用 / 订阅到期处理（每天自动跑） |

客服也可以用上面买家和批发商的函数「代操作」，例如替任何一家店调用 `place_order`。

## 4. 错误代码

函数出错时返回英文代码，App 按代码显示三语提示（第三步会做）。

| 代码 | 意思 |
|---|---|
| `NOT_LOGGED_IN` | 没登录 |
| `NOT_ALLOWED` | 没有权限（例如用别家店的身份） |
| `ROLE_MISMATCH` | 买家账号不能注册批发商，反过来也一样 |
| `COLUMN_PROTECTED` | 这个字段只有客服能改 |
| `INVALID_ZONE` | 送货区不存在 |
| `TOO_MANY_WHOLESALERS` | 免费只能选 3 家 |
| `UNLOCK_COOLDOWN` | 30 天内不能再换（`detail` 是可以再换的时间） |
| `WHOLESALER_NOT_AVAILABLE` | 这家批发商还没审核，或者不送你那区 |
| `CART_EMPTY` | 购物车是空的 |
| `CART_HAS_PROBLEMS` | 购物车有问题（`detail` 是完整报价，标了每一行的问题） |
| `PRICE_CHANGED` | 价钱刚好改了，请重新确认（`detail` 是新报价） |
| `INVALID_SOURCE` | 老板不能把订单来源设成「客服」 |
| `ORDER_NOT_FOUND` | 找不到订单 |
| `INVALID_TRANSITION` | 订单现在的状态不能这样改 |
| `ITEM_NOT_IN_ORDER` | 标缺货的那一行不在这张订单里 |
| `ORDER_NOT_DELIVERED` | 还没送到不能评价 |
| `NO_PREVIOUS_ORDER` | 还没下过单，没有「上次」 |
| `FOUNDING_QUOTA_FULL` | 创始会员名额满了 |
| `NO_PRICING_PLAN` | 系统还没设定月费（设定问题，找技术） |

报价里每一行、每一组的问题：

| 代码 | 意思 |
|---|---|
| `PRODUCT_UNAVAILABLE` | 商品下架了 |
| `NOT_DELIVERING` | 这家批发商不送你那区 |
| `WHOLESALER_LOCKED` | 未付费用户：这家不在免费名单 |
| `OUT_OF_STOCK` | 缺货 |
| `BELOW_MIN_QTY` | 未到起订量 |
| `BELOW_MIN_ORDER` | 未到最低消费（`short_by_sen` 是还差多少） |

## 5. 怎么测试

**不用 Docker（我在开发环境跑的就是这个）：**

```bash
./scripts/test-db.sh
```

会临时起一个 Postgres，跑全部迁移、种子数据和 122 项测试，跑完自动删掉。需要 Postgres 15 以上、pgTAP、pg_prove。

**有 Docker 的话，用 Supabase 官方做法**（会起完整的本机 Supabase，包括登录和网页后台 Studio）：

```bash
npx supabase start
npx supabase db reset     # 跑迁移 + 种子数据
npx supabase test db      # 跑测试
```

这个做法我在开发环境没办法跑（没有 Docker），第一次用的时候如果有问题告诉我。

**本机测试号码**（验证码都是 `123456`）：

| 号码 | 登录后是 |
|---|---|
| 60120000001 | 示范店「阿明茶餐室」的老板（试用中） |
| 60120000002 | 示范批发商 A 的老板 |
| 60120000003 | 普通账号；执行下面那句 SQL 后变成客服 |
| 60120000004 | 示范店「Kedai Runcit Siti」的老板（试用已用完，免费只开放 A，C 的价钱是模糊的） |

**设定客服账号**（客服只能这样设，App 里不能自己改）：

```sql
update public.profiles set role = 'admin' where phone = '60120000003';
```

## 6. 还没做的（留到后面的步骤）

| 什么 | 哪一步 |
|---|---|
| 照片、价目表、录音的存储空间（Storage bucket）和权限 | 第三、四步，做上传的时候 |
| 通知真的发出去（推送 / WhatsApp）；现在只是排进 `notifications` 队列 | 第四步 |
| 每天早上的批发商订单总结、新订单 30 分钟没确认提醒客服 | 第四、五步 |
| 价目表 AI 识别后「确认上架」的函数 | 第四步 |
| 客服发出账单、标记已付；账单 PDF | 第五步 |
| 语音 / WhatsApp 草稿转成订单 | 第六步 |
| 付款网关、续费、重新订阅、创始上架费付款 | 第七步 |

## 7. 上线前要改的设定

- **送货区的邮区**只是示例，要核对。
- **佣金比例**先填了「行业默认 2%、创始会员 1%」，在 `industries` 表里改。
- **示范数据**（示范批发商、示范店、示范订单）不要导入正式环境，`seed.sql` 里只用第 1 部分「设定」。
- 以后新增函数的迁移，要照 `…700_business_logic.sql` 最后一节的做法收回默认权限，只开放 App 要用的。
