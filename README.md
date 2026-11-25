# 新山 B2B 批发下单 App

帮小店老板一次比较多家批发商的价钱，一键进货。第一阶段：新山、餐饮打包耗材。

- 技术：Flutter（iOS / Android / 客服后台网页）+ Supabase + Firebase Cloud Messaging
- 语言：华文、English、Bahasa Melayu；货币 RM

## 文件

- [`docs/prompts.md`](docs/prompts.md)：七步开发提示词（最新版）
- [`docs/01-architecture.md`](docs/01-architecture.md)：第一步，整体架构、数据库表设计、开发步骤
- [`docs/02-database.md`](docs/02-database.md)：第二步，数据库怎么用、App 要调用的函数、错误代码、怎么测试
- `supabase/`：数据库迁移、种子数据、测试
- `scripts/test-db.sh`：不用 Docker 的数据库测试（`./scripts/test-db.sh`）
