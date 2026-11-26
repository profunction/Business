# 第七步：收费

## 买家的月费一定要用应用内购买吗？（2026-11 查的）

1. **在 iPhone / Android 的 App 里面卖月费，就一定要用应用内购买。** 月费解锁的是 App 里的功能（看全部批发商的价钱），Apple 3.1.1 说订阅、解锁功能「必须用 in-app purchase」；Google Play 也把「订阅、商业软件、云端服务」列为必须用 Play Billing。([Apple 3.1.1](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)、[Google Play 付款政策](https://support.google.com/googleplay/android-developer/answer/9858738))
2. **「B2B」帮不了。** Apple 3.1.3(c) 只给「卖给公司、让员工 / 学生用」的 App；一家店一个老板是「single user」，要用应用内购买。Google 没有 B2B 例外；「实体货物」的例外只包括买货，不包括月费。([Apple 3.1.3](https://developer.apple.com/app-store/review/guidelines/#other-purchase-methods))
3. **2025 年美国的判决、欧盟的规定、Google 2026 年和 Epic 的和解，都不包括马来西亚**：美国的 App Store 可以放外面付款的按钮 / 链接，欧盟、英国另外有方案，马来西亚照旧不可以。([Apple 3.1.1(a)](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)、[MacRumors：Google 2026 改费用](https://macrumors.com/2026/06/24/google-play-store-fee-change/))
4. **可以在网页付。** 条件是 App 里面不卖、不放付款按钮、不放「去网页付款」的链接或文字；App 外面（WhatsApp、短信、电邮）告诉老板怎么付是可以的（Apple 3.1.3 开头那段）。老板在网页付了，App 照样认得（订阅状态在服务器）。
5. **风险：** Apple 3.1.3(b) 字面上要求「网页买的也要在 App 里有应用内购买可以买」。审核员如果坚持，就要加 Apple / Google 的应用内购买（小企业抽 15%，Google 订阅现在 10%）。
6. **批发商的佣金账单、创始上架费不用应用内购买：** 那是实体货物交易的平台费（Apple 3.1.3(e)、Google「实体货物 / 服务」的例外），App 里可以直接接付款网关。上架费比较像「上架的数字服务」，审核有疑问时可以用下面的开关先关掉。

**App 现在这样做：** 商店版本（iOS / Android）的买家「我的订阅」只显示状态、还剩几天、锁定的价钱，没有付款按钮、没有提网页付款；客服在后台按「付款链接」复制给老板（WhatsApp）。网页版有付款按钮。开关（`apps/mobile/lib/app/billing_config.dart`）：`--dart-define=BUYER_IN_APP_PAY=web`（默认）/ `all` / `none`，`--dart-define=SELLER_IN_APP_PAY=true`（默认）/ `false`。

## 付款网关：用 HitPay

| 网关 | FPX | DuitNow | 电子钱包 | 自动扣款 | 费用（大约，未含 8% SST） |
|---|---|---|---|---|---|
| **HitPay**（选这个） | 有 | DuitNow QR | TNG、GrabPay、ShopeePay、Boost | 卡、电子钱包可以；FPX / DuitNow 不行 | FPX 1.8% + RM0.40，DuitNow QR 1.2%，钱包 1.9–2.2%，没有月费 |
| Curlec（Razorpay） | 有 | DuitNow Pay / AutoDebit | 有 | 银行 e-Mandate（最强） | FPX 1.5% 或 RM1 |
| Billplz | 有 | 不清楚 | Boost | 没找到 | 预付额度，没公开 |
| Stripe Malaysia | 有 | 没有 | 只有 GrabPay | 卡 | FPX 3% + RM1 |
| Fiuu（Razer）/ iPay88（Adaptis） | 有 | 有 | 有 | 要谈 | 要报价 |

选 HitPay：一个账号就有全部要的方法（FPX、DuitNow、四个钱包），不用月费、开户快，API 简单（开单回一个付款网址；webhook 用 HMAC-SHA256 签名）。月费 RM50 很少，老板多数用 FPX / DuitNow，这两种本来就不能自动扣，所以用「快到期推送 + 付款链接」比较实际。以后要银行自动扣款再加 Curlec（网关的代码只在 `supabase/functions/_shared/payments.ts`）。
来源：[HitPay API](https://docs.hitpayapp.com/apis/guide/online-payments)、[HitPay 费用](https://hitpayapp.com/blog/payment-processing-fees-malaysia-2026)、[Curlec 订阅](https://curlec.com/subscriptions)、[Airwallex：Curlec 费用](https://www.airwallex.com/my/blog/curlec-review)、[Billplz API](https://billplz.github.io/api_slate)、[Airwallex：Stripe 马来西亚](https://www.airwallex.com/my/blog/fiuu-vs-stripe)、[Fiuu](https://hitpayapp.com/blog/fiuu-review-malaysia)。费用多数来自竞争对手的比较文章，签约前要跟网关确认。

## 程序在哪里

- 数据库：`supabase/migrations/20261130000100_billing.sql`（测试 `10_billing.test.sql`）。续费规则只有一份 `_extend_subscription`：试用中从试用结束算、一直续费从上期结束接着算（锁定价不变）、宽限期内补付原价、停了再回来按当时的新价钱新建订阅。
- 每天 00:20（马来西亚时间）`run_billing_daily`：月初生成并自动发出上个月的佣金账单（推送）、快到期 / 逾期推送、买家快到期推送。
- Edge Functions：`create-payment`（开付款页）、`payment-webhook`（验签名、同一笔只算一次）。
- 要设定的（Edge Function secrets）：`HITPAY_API_KEY`、`HITPAY_SALT`、`HITPAY_ENV=production`（默认 sandbox）、`PAYMENT_RETURN_URL`（可以不设）。HitPay 后台的 webhook 指到 `https://<project>.supabase.co/functions/v1/payment-webhook`，事件选 `payment_request.completed`。没设定时 App 显示「网上付款还没开通」，客服照旧可以手动标记已付。
