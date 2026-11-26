# 新山 B2B 批发下单 App

帮小店老板一次比较多家批发商的价钱，一键进货。第一阶段：新山、餐饮打包耗材。

- 技术：Flutter（iOS / Android / 客服后台网页）+ Supabase + Firebase Cloud Messaging
- 语言：华文、English、Bahasa Melayu；货币 RM

## 文件

- [`docs/prompts.md`](docs/prompts.md)：七步开发提示词（最新版）
- [`docs/01-architecture.md`](docs/01-architecture.md)：第一步，整体架构、数据库表设计、开发步骤
- [`docs/02-database.md`](docs/02-database.md)：第二步，数据库怎么用、App 要调用的函数、错误代码、怎么测试
- [`docs/03-buyer-app.md`](docs/03-buyer-app.md)：第三步，买家端（截图在 `docs/screenshots/03-buyer/`）
- `supabase/`：数据库迁移、种子数据、测试
- `packages/core/`：手机 App 和客服后台共用的 Dart 代码
- `apps/mobile/`：Flutter 手机 App（怎么跑见 [`apps/mobile/README.md`](apps/mobile/README.md)）
- `apps/admin_web/`：Flutter Web 客服后台（怎么跑见 [`apps/admin_web/README.md`](apps/admin_web/README.md)）
- 语音下单、WhatsApp 下单（第六步）：[`docs/06-voice-whatsapp.md`](docs/06-voice-whatsapp.md)
- 收费（第七步：月费、佣金账单、付款网关、App Store / Google Play 规定）：[`docs/07-billing.md`](docs/07-billing.md)
- 公司采购（第八步，分 5 期；第 1 期公司账号和方案已做）：[`docs/08-procurement-spec.md`](docs/08-procurement-spec.md)；
  `apps/procure_web/`：Flutter Web 公司采购网页（怎么跑见 [`apps/procure_web/README.md`](apps/procure_web/README.md)）
- `scripts/test-db.sh`：不用 Docker 的数据库测试（`./scripts/test-db.sh`）
