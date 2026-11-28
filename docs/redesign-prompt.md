# 顾客 App 改成专业采购风（给 ChatGPT / Codex 的提示词）

```
你在 GitHub 项目 profunction/Business 的分支 ccr-0caaf059-047i1b 工作。这是马来西亚新山的 B2B 批发下单平台：Flutter App 在 apps/mobile（买家和批发商共用一个 App），共用包在 packages/core，三种语言 zh（默认）/ en / ms 用 gen-l10n（ARB 在 apps/mobile/lib/l10n），Riverpod 管状态，go_router 管页面，格式 page_width 120。

【要做的事】
老板觉得「顾客（买家）下单」那边的画面太像小孩子：首页一块一块的大彩色方块（橙、绿、蓝、紫）、字和按钮太大。改成「专业采购平台」的感觉：干净、可信，像现代的 B2B 采购 App。只改外观，所有功能、页面路径、provider 和 API 调用都不能变。

【目标样子】
- 白色或很浅的灰色底，只用一个主色（深青色或深蓝色）加灰色；彩色只用在状态标签（待确认、已确认、缺货等）。
- 一般 Material 3 大小：内文 14–16sp、标题 18–22sp、按钮高 40–48dp、圆角 8–12dp、卡片用细边框或很轻的阴影。可按的地方至少 44dp，颜色对比要够（WCAG AA）。
- 买家下面有导航：首页 / 分类 / 购物车（有数字）/ 订单 / 我的（设定、订阅）。用现有的路径，切换时要保留状态，不能弄坏深层连结、推送打开的页面和批发商那边。
- 首页：上面是店名和搜索栏；一排小的快捷按钮（「跟上次一样」、「按住说话下单」，按住录音的功能照旧）；还没确认的语音订单和试用提醒用细长的横条；「常买的商品」（可以直接加减数量）和「最近的订单」（有状态标签）。只用 App 已经拿到的资料，不要加新的后端调用。
- 商品列表、批发商页、商品页、购物车、结账、订单列表和详情、设定、订阅、免费选 3 家批发商、语音订单确认页：全部统一风格。价钱靠右对齐，购物车按批发商分组，合计清楚，主要按钮放在下面。
- 外观集中在主题文件（apps/mobile/lib/app/theme.dart）：颜色、字体、卡片、按钮、输入框、标签、导航，画面里不要再写死颜色和大小。批发商那边也用同一个主题，要确认它看起来正常、没有跑版，但不要重新设计批发商的排版。
- 三种语言在手机宽度 360–400 都不能跑版，马来文的字特别长。

【现在的进度】
上一个 AI 做到一半就停了（commit 0127ee1 和 2157d8f，还没测试过）。已经改过：
apps/mobile/lib/app/theme.dart、buyer_shell.dart（新的下方导航）、router.dart、providers.dart、
features/home/home_page.dart、features/browse/（browse_page、cart_button、catalog_items_page、compare_page、offer_card、wholesaler_products_page）、
features/orders/orders_page.dart、features/voice/mic_button.dart、widgets/common.dart、三个 ARB。
还没改：商品页、购物车、结账、订单详情、评价、设定、订阅、免费批发商、语音订单确认页，还有测试。
先检查已经改过的部分：能用的就接着做，有问题的就改掉。如果觉得太乱，也可以从 commit a65e5e1 重新开始。

【检查方法】
- 打开示范版：cd apps/mobile && flutter run -d chrome -t lib/main_demo.dart
  - 买家首页是默认画面；?lang=en 是英文、?lang=ms 是马来文；?seller=1 是批发商
  - 每一页都看过，留意有没有跑版、没翻译
- 测试要全部通过：
  cd apps/mobile && flutter analyze && flutter test && flutter build web -t lib/main_demo.dart
  cd packages/core && dart test
  cd apps/admin_web && flutter analyze && flutter test
- 测试要跟着新画面改，但不能为了通过就删掉测试。

【完成后】
commit 后 push 到同一个分支 ccr-0caaf059-047i1b，不要 push 到别的分支。
用简单中文告诉我：改了什么、截图（买家首页、分类、购物车、结账、订单、设定；中文和马来文各一份）、每个测试最后一行的结果。
```
