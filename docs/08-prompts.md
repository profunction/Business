# 第八步提示词（给别的 AI 用）

一次给一段。等这一段做完、测试全部通过、提交了，才给下一段。

---

## 共用说明（每一段前面都贴上）

```
你在一个 GitHub 项目里工作：马来西亚新山的 B2B 批发下单平台（Supabase Postgres + Deno Edge Functions + Flutter，三种语言 zh/en/ms）。
第 1 到 7 步已经做好、测试过（commit 2033887）。第 8 步是加「公司账户」和像 Lapasar 那样的采购功能，设计在 docs/08-procurement-spec.md，请完整读一遍，这是你的需求。

先读：docs/prompts.md、docs/01-architecture.md、docs/02-database.md、docs/08-procurement-spec.md、supabase/migrations 里的全部 migration。

规则（一定要照做）：
- 不要改旧的 migration，新的 SQL 放在新的 migration 文件。重新定义旧函数时，先在全部 migration 里找它最新的版本，从那个版本改。
- 函数用 SECURITY DEFINER + set search_path = ''，用 is_admin() / is_service_call() 检查，先 revoke from public, anon, authenticated 再 grant。
- 错误用 raise exception 'CODE'（P0001；权限错误用 42501）。钱用 sen（整数）。时间用马来西亚时间的 helper。注释用简单中文。
- pgTAP 测试放 supabase/tests/database/，照现有文件用 \if 平台判断和 _helpers.psql。
- Edge Functions：共用代码放 _shared，deno.json 固定版本，deno.lock 冻结，测试用假的 fetch，bundle.ts 和 config.toml 要加入口。
- 每个阶段都要改到的 App 都要做：顾客 App（apps/mobile 的买家端）、批发商 App（apps/mobile 的批发商端）、公司采购网页（apps/procure_web）、客服后台（apps/admin_web）。新画面在手机宽度 400 不能跑版。
- Flutter：Riverpod、go_router、gen-l10n（zh 默认、en、ms 三个 ARB 都要有），page_width 120，共用 packages/core。每个 App 都有示范模式，示范资料从真的本地 Postgres 导出（参考 apps/admin_web/tool/export_fixtures.sh）。
- 没有真的外部账号：所有外部服务都要放在设定后面，测试用假的，没设定时要安全地显示「未设定」。
- 小店现有的功能不能变。
- 不要抄 Lapasar 的名字、标志、文字和外观，只做一样的功能。

做完要全部通过：
./scripts/test-db.sh
cd supabase/functions && deno task check && deno task lint && deno task fmt && deno task test
cd packages/core && dart analyze && dart test
apps/mobile、apps/admin_web（有 apps/procure_web 的话也要）：flutter analyze && flutter test && flutter build web -t lib/main_demo.dart

最后告诉我：做了什么、新的数据库函数、改了设计的哪里、每个测试的结果。
```

---

## 第 1 阶段：公司账户和收费

```
做 docs/08-procurement-spec.md 的第 1 阶段（只做这一阶段）：
- migration 20261202000100_procure_enums.sql 和 20261202000200_company_accounts.sql，测试 12_company_accounts.test.sql
- 公司、员工角色（admin / approver / finance / requester）、每个人管哪些分店、用电话邀请员工、公司月费方案、订阅和发票、网页里的收件箱
- 公司分店不能走小店的下单流程（USE_REQUISITION）
- create-payment 和 payment-webhook 加公司方案
- 新的 Flutter 网页 apps/procure_web（照 apps/admin_web 的结构）：电话验证码登录、切换公司、分店、员工和邀请、方案和付款、收件箱，要有示范模式
- 客服后台 apps/admin_web 加「公司」管理页
- 顾客 App（apps/mobile）：公司员工登录后认得是哪家公司，设定页和开店页显示「我的公司」（角色、「方案由贵公司管理」）；这一阶段没有新功能，App 里不能有任何付款按钮或去网页付款的字。小店的画面完全不变

注意：commit b082fb7 里有上一个 AI 做了一半、没测试过的第 1 阶段程序。先检查它，能用的就接着做完，有问题的就改掉。
```

## 第 2 阶段：申请、批准、采购单

```
做 docs/08-procurement-spec.md 的第 2 阶段（只做这一阶段）：
- migration 20261203000100_requisitions.sql，测试 13_requisitions.test.sql
- 把 _quote_cart 和 place_order 里面的 _quote_items、_insert_orders 抽出来，行为不能变（旧测试要照样通过）
- 采购申请；批准规则按金额、类别、分店、预算；可以分几层；申请人不能批自己的；同一个人只能批一层
- 用固定规则算的提醒：拆单、价钱比市价或上次高、有更便宜的、数量不寻常、超预算、新的批发商。AI 只写解释和建议，不能自己批准
- 批准后按批发商出采购单（就是普通订单加采购单号）
- 新的 Edge Function procurement-insights
- 顾客 App（apps/mobile）：首页多一个「公司采购」；「审批」：列表 → 一张单 + AI 提醒 → 大按钮「批准」「退回」「不批」；浏览商品时可以「加入申请单」再送出
- procure_web 加申请、批准、采购单的页面
```

## 第 3 阶段：收货、发票、核对、月结

```
做 docs/08-procurement-spec.md 的第 3 阶段（只做这一阶段）：
- migration 20261204000100_receiving_matching.sql，测试 14_receiving_matching.test.sql
- 收货（可以分几次收、可以拒收），超过 N 天自动当作收到
- 采购单、收货、发票三样逐行核对，有容许差额
- 每家批发商的记账天数和额度；每月对账单；财务记录付款，批发商确认
- 公司订单的佣金改成按真正收到的货算，在收货完成时才产生（不能少算也不能算两次）
- 新的 Edge Function parse-procurement-doc：AI 读发票和送货单的照片
- 顾客 App（apps/mobile）：「收货」：我分店的采购单 → 每行 ＋／－ 数量、拒收原因、拍送货单（AI 先填好）→「确认收货」
- 批发商 App：「要开发票（N）」、按收货数量一键开发票或拍照上传、月结单、确认收到付款、记账申请「同意」「不同意」；订单详情显示采购单号和记账天数
- procure_web 和客服后台加对应的页面
```

## 第 4 阶段：询价、报价、竞价

```
做 docs/08-procurement-spec.md 的第 4 阶段（只做这一阶段）：
- migration 20261205000100_rfq.sql，测试 15_rfq.test.sql
- 三种询价：报价随时看得到、截止才一起打开、限时竞价
- 竞价：每次最少要降多少、最后几分钟有人出价就自动延长、即时显示排名和倒数
- 批发商可以在 App 报价，也可以用 WhatsApp 或上传文件，AI 变成报价草稿；加两个新的 WhatsApp 模板
- 报价排在一起比较，可以还价；选好了变成采购单，还是要走公司的批准（从已批准的申请来、又在容许范围内的就自动批准）
- 批发商 App：首页加「询价（N）」；一行一行填价钱或「上传报价单」（AI 先填好）→「送出报价」；还价「接受」「不接受」；竞价页有倒数、我的名次、「出更低的价」
- 顾客 App（apps/mobile）：公司员工可以看询价进度和结果（建立询价在 procure_web 做）
- procure_web 和客服后台加对应的页面
```

## 第 5 阶段：比价、花费分析、公开网站

```
做 docs/08-procurement-spec.md 的第 5 阶段（只做这一阶段）：
- migration 20261206000100_benchmark_spend_site.sql，测试 16_benchmark_spend_site.test.sql
- 每晚算市价；「这个价钱合不合理」，小店也能用
- AI 建议每个批发商的商品对应哪一个标准商品，客服审核
- 花费分析：按分店、类别、批发商看花了多少钱，同一样东西买贵了的标出来，省钱建议，每月 AI 总结（AI 不能自己写钱的数字）
- 公开网站 apps/site：静态网页，三种语言，首页介绍、怎么用、不用登录就能看商品分类（不显示价钱和批发商名字）、常见问题、公司或店家注册、「成为批发商」申请
- 网站的表格送到新的 Edge Function site-forms
- 顾客 App（apps/mobile）：商品页加「价钱合理吗？」，小店和公司员工都能用
- procure_web 加花费分析页（图表、AI 说明、导出 CSV）
- 客服后台加「批发商申请」审核页
```
