# Edge Functions（第四步）

规格：[`docs/04-seller-spec.md`](../../docs/04-seller-spec.md) 第 3
节；外部服务的查证结果：[`docs/04-research.md`](../../docs/04-research.md)； WhatsApp
模板送审：[`docs/04-whatsapp-templates.md`](../../docs/04-whatsapp-templates.md)。

> **先打包，再开本机、再部署。** `config.toml` 的 `entrypoint` 指到打包好的 `_dist/<函数>/index.js`，`_dist/` 不进
> git，所以刚 clone 下来的没有这些档案。`supabase start`、`supabase functions serve`、部署之前，一定要先在
> `supabase/functions` 里跑 `deno task bundle`（或用 `deno task serve` = 打包 + serve、`deno task deploy` = 打包 +
> 部署）。改了代码也要重新打包。

| 函数                     | 谁叫                                                    | 怎么验身份                                                                               |
| ------------------------ | ------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `dispatch-notifications` | pg_cron（每分钟）、`notifications` 的 trigger（pg_net） | `apikey` 头 = secret key（固定时间比较）                                                 |
| `whatsapp-webhook`       | Meta                                                    | GET：`hub.verify_token`；POST：`X-Hub-Signature-256`（App Secret，原始 body）            |
| `parse-price-list`       | App（`functions.invoke`）                               | `auth.getUser(jwt)`，再用用户身份（RLS）读 import；占位 / 用量：`reserve_price_list_run` |

三个都是 `verify_jwt = false`（`supabase/config.toml`），身份全部在代码里检查。

```
_shared/      env.ts、supabase.ts、http.ts、fcm.ts、whatsapp.ts、messages.ts（所有三语文字）、
              claude.ts、spreadsheet.ts、filetype.ts、zipguard.ts、pdf.ts
<函数>/       index.ts（export default { fetch }）+ deno.json（import map；版本跟根目录一样）
tests/        deno test（外部 API 全部用假的 fetch，不连网）
deno.json     本机测试 / 打包用（frozen deno.lock）
bundle.ts     deno task bundle：照 deno.lock 打包成 _dist/<函数>/index.js（部署的是这个，不进 git）
```

## 秘密（`supabase secrets set NAME=value`，名字不能以 `SUPABASE_` 开头）

| 名字                                         | 用在                                  | 没设会怎样                                                             |
| -------------------------------------------- | ------------------------------------- | ---------------------------------------------------------------------- |
| `FCM_SERVICE_ACCOUNT_JSON`                   | 推送（Firebase 服务账号 JSON 整份）   | 推送通知标 failed `FCM_NOT_CONFIGURED`，不重试                         |
| `WHATSAPP_TOKEN`、`WHATSAPP_PHONE_NUMBER_ID` | 发 WhatsApp（system user 永久 token） | WhatsApp 通知标 failed `WHATSAPP_NOT_CONFIGURED`，不重试；按钮回复不发 |
| `WHATSAPP_GRAPH_VERSION`                     | Graph API 版本                        | 默认 `v27.0`                                                           |
| `WHATSAPP_APP_SECRET`                        | 验 webhook 签名                       | webhook POST 回 500（Meta 会重送）                                     |
| `WHATSAPP_VERIFY_TOKEN`                      | webhook 验证握手（自己想一串字）      | 握手回 403                                                             |
| `ANTHROPIC_API_KEY`                          | 价目表 AI                             | 导入标 failed `AI_NOT_CONFIGURED`                                      |
| `PRICE_LIST_TIME_BUDGET_MS`（可选）          | 价目表背景工作的时间预算              | 默认 380000（付费方案 400 秒）；**免费方案设 140000**；最多 540000     |
| `DISPATCH_TIME_BUDGET_MS`（可选）            | dispatcher 一次最多跑多久             | 默认 100000                                                            |
| `WORKER_WALL_CLOCK_MS`（可选）               | 平台的 worker 总时间（dispatcher 用） | 默认 150000（免费方案）；**付费方案设 400000**                         |

时间预算：Supabase 的总时间是按 **worker** 算的（一个 worker 会接很多个请求），所以 parse-price-list 的期限是 「worker
开始的时间 + `PRICE_LIST_TIME_BUDGET_MS`」（晚进来的请求分到的时间比较少，剩下不够叫 Claude 就直接
`AI_TIMEOUT`）。worker 要被关掉时（`beforeunload`）会中止正在跑的工作、马上把 import 标成 failed（总时间到 →
`AI_TIMEOUT`，CPU / 记忆体超过 → `INTERNAL_ERROR`）。dispatcher 每条开始之前都看预算：剩下不到 15 秒就不再开始发，
领到但没发的用 `release_notification` 放回队列（不算失败、`attempts` 不变，下一次叫马上再领；放不回去才标 failed + 重试
`DISPATCH_TIME_BUDGET`，2 分钟后再发），每个对外请求也最多等到预算用完。 dispatcher 的期限也不超过「worker 开始 +
`WORKER_WALL_CLOCK_MS` - 15 秒」（晚进来的请求少发一点，不会发到一半被 平台杀掉、10 分钟后重发一次）；`beforeunload`
之后不再领、不再开始发，领到还没开始发的马上放回队列（不等正在发的那几条；回应要等放回去的都做完）。每次 dispatch 带一个
新的 claim id（`claim_notifications` / `release_notification` / `complete_notification` 的 `p_claim_id`）：数据库只让
领着的那个 dispatcher 放回、记 failed / skipped（`sent` 不看），所以「放回去其实成功了、回应在路上断了、那条马上又被别的
dispatcher 领走」时，退回的标失败对不上、不会改到别人的（不会变成 failed、之后又重发一次）。

价目表的时间：Excel / CSV 每段 50 行、PDF 超过 4 页就每段 4 页（同一个 document block + `cache_control`，第一段
开始回应、快取写好之后别段才送），最多同时 8 段；max_tokens → 那一段切两半**同时**再读一次。开始叫 Claude
之前先估计（一段 90 秒）：整个预算都读不完 → `TOO_MANY_ROWS`（付费方案大约 32 段 = 1600 行 / 128 页；免费方案 8 段 = 400
行 / 32 页），这个 worker 剩下的时间不够 → `AI_TIMEOUT`，都不叫 Claude、不花钱。失败时写数据库 （改成
failed、删行）暂时失败 → 隔 0.5 / 2 / 5 秒再试。

价目表的占位和用量：只用一个数据库函数 `reserve_price_list_run(import_id, user.id, 新的 run_id)`（服务器身份，迁移
`20261127000200_seller_hardening.sql`），一个交易里照顺序检查成员 → 停权 → 状态 → 在跑 → 用量，都通过才占位
（`ai_raw.state = running`）、记一笔
`price_list_runs`（只有服务器碰得到，批发商删不掉；删掉导入用量也留着）。挡下来的什么都没改、不算次数（HTTP
见下面的表）。 用量：10 分钟 3 次、1 小时 10 次、1 天 30 次（还没审核的 `pending`：2 / 4 / 8；数字只在数据库的
`_price_list_run_limits()`）。每家批发商各算各的，**每个人也一样**：叫的人在每一家跑的加起来、建这家批发商的人建的每一家
加起来，哪一份满了都挡（客服不算）；停权批发商的老板（或建的人）在别家也不能跑。`register_wholesaler`
一个人同时只能有一家 待审核的。所以一直注册新的批发商不会多出用量。之后写回 import 都要 `status = processing` 而且
`ai_raw->>run_id` 是这一次的。卡在 processing 的由定时任务 `fail_stuck_price_list_imports`（每 5 分钟）收拾：在跑超过 15
分钟 → `AI_TIMEOUT`，App 建好导入后没叫到 AI 15 分钟 → `START_FAILED`。「在跑」超过 10 分钟别人可以重新占位，所以
`PRICE_LIST_TIME_BUDGET_MS` 最多 540000（9 分钟，再大就用默认值）。

大小限制：价目表档案 10 MB；xlsx 解压后合计 32 MB（工作表 / XML 16 MB，单一 entry 压缩比超过 100:1 也不收）→
`FILE_TOO_LARGE`；zip 的 entry 资料重叠 / 指同一个 header、deflate block 比正常的编码器多太多 →
`SPREADSHEET_UNREADABLE`，检查本身超过 0.5 秒 → `FILE_TOO_LARGE`。CSV 不交给 SheetJS（自己照它的规则切格：每行 最多 256
栏、看得到的 1000 个字）；CSV / xls 有内容的格子最多 6 万格，xls 的 BIFF 记录最多 15 万笔、空白格 100 万格 →
`FILE_TOO_LARGE`。第 4800 行以下还有**值** → `TOO_MANY_ROWS`（只看有值的格子：表写的范围 `<dimension>`
连只有框线的格子也算，不能用）；商品最多 1200 样 → `TOO_MANY_ROWS`。whatsapp-webhook 的 body 最多 4 MB （Meta 最多 3
MB），超过 → 413；没有签名 / 格式不对 → 401，都不读 body。

平台自动给 `SUPABASE_URL`、`SUPABASE_SECRET_KEYS`、`SUPABASE_PUBLISHABLE_KEYS`（旧项目退回 `SUPABASE_SERVICE_ROLE_KEY` /
`SUPABASE_ANON_KEY`）。 pg_cron 用的 Vault 秘密 `secret_key` 要放 **default** 那把 secret key。

## 本机

```sh
cd supabase/functions
deno task check && deno task lint && deno task fmt && deno task test   # 测试不用打包

deno task bundle     # 第一次（和每次改了代码）：supabase start / functions serve 载入的是 _dist/<函数>/index.js
supabase start       # 本机整套（要 Docker）
deno task serve      # = deno task bundle，再 supabase functions serve（秘密放 supabase/functions/.env，照 .env.example）
```

不用 Docker、不连外网（Deno 会下载 npm / jsr / cdn.sheetjs.com 的套件；npm 版本要发布满 24 小时才装得到）。
`deno.lock`（frozen）锁住全部套件，包括间接用到的和 SheetJS 档案的 hash：对不上就不跑。要更新套件时改 `deno.json`
和各函数的 `deno.json`，再跑
`deno install --frozen=false --allow-import=cdn.sheetjs.com,jsr.io,registry.npmjs.org --entrypoint _shared/*.ts */index.ts tests/*.ts`
重写 lock 档。

部署的不是原始码：`deno task bundle` 照这份 lock（`--frozen-lockfile`，integrity 对不上就失败）把每个函数打包成
`_dist/<函数>/index.js`（只剩 `node:` 内建模组；打包完会检查、载入一次），`config.toml` 的 `entrypoint` 指到这里，
所以部署工具（Docker 或 `--use-api`）不会再解析间接用到的套件（以前部署时会拿到 `^` 范围里最新、可能刚发布的版本， 没有
integrity 检查）。`supabase functions serve` 要 Docker，之前先 `deno task bundle`（改了代码要重新打包、重开
serve；`deno task serve` 两件一起做）；`config.toml` 的 `[edge_runtime] policy = "per_worker"`
是为了让背景工作在本机跑完。

## 部署

```sh
cd supabase/functions
deno task deploy   # = deno task bundle，再 supabase functions deploy dispatch-notifications whatsapp-webhook parse-price-list --yes
```

不要直接 `supabase functions deploy`：`_dist/` 没有或是旧的就会部署到旧的代码（没有的话部署会失败）。

部署后：Meta App Dashboard → WhatsApp → Configuration：Callback URL =
`https://<project>.supabase.co/functions/v1/whatsapp-webhook`， Verify token = `WHATSAPP_VERIFY_TOKEN`，订阅
`messages`。

## parse-price-list 的 HTTP 回应

| HTTP | `error`                                                                                      | 什么时候                                                                      | import                                       |
| ---- | -------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | -------------------------------------------- |
| 202  | （回 `{import_id, status: "processing"}`）                                                   | 占位成功，背景在读                                                            | `ai_raw.state = running`；App 每 3 秒查状态  |
| 400  | `INVALID_IMPORT_ID`                                                                          | `import_id` 不是 uuid                                                         | 没动                                         |
| 401  | `UNAUTHORIZED`                                                                               | 没有 / 错的 JWT（Auth 说 JWT 不对、用户 / session 不在了）                    | 没动                                         |
| 403  | `WHOLESALER_SUSPENDED`                                                                       | `suspended`：批发商停权；或叫的人、建这家的人是一家停权批发商的老板（或建的） | 没动                                         |
| 404  | `IMPORT_NOT_FOUND`                                                                           | 用户身份（RLS）读不到；`not_found`（刚被删掉）；`not_member`（不是成员）      | 没动                                         |
| 405  | `METHOD_NOT_ALLOWED`                                                                         | 不是 POST / OPTIONS                                                           | 没动                                         |
| 409  | `IMPORT_NOT_PROCESSING`（加 `status`：现在的状态）                                           | `not_processing`：已经读完 / 失败 / 上架                                      | 没动                                         |
| 409  | `IMPORT_ALREADY_RUNNING`                                                                     | `already_running`：有人在读（10 分钟内占的位）                                | 没动（不算失败，继续等）                     |
| 429  | `TOO_MANY_IMPORTS`（`retry_after` 秒、`window`：`burst` / `hour` / `day`；`Retry-After` 头） | `quota`：用量满了；等 `retry_after` 秒再叫就不会被别段挡住                    | 没动、不算次数                               |
| 500  | `CONFIG_MISSING`、`DB_ERROR`、`INTERNAL_ERROR`                                               | 函数没设定好；用户身份读 import 出错；程式错误                                | 没动（`CONFIG_MISSING` 时什么都还没碰）      |
| 503  | `QUOTA_UNAVAILABLE`                                                                          | 叫不到 `reserve_price_list_run`（数据库暂时出错、断线、迁移还没跑）           | 没动：暂时的，等一下再叫一样可以             |
| 503  | `QUOTA_UNAVAILABLE`（多带 `cause: "AUTH"`）                                                  | Auth 服务暂时出错（断线、逾时、5xx、429、回的不是 JSON），验不了 JWT          | 没动：暂时的（**不是**登录过期），等一下再叫 |

极少数：数据库已经占好位、回应在路上断了 → 503，但 import 是「在跑」又没人在读：10 分钟后再叫可以重新占位，15
分钟后定时任务标 `AI_TIMEOUT`。

## parse-price-list 的 `error_message`（App 按这个显示三语原因）

| 类别                       | 代码                                                                                                                                                                  |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| HTTP（不是 error_message） | 见上面的表：没占位的回应（4xx、503）import 都没动                                                                                                                     |
| 定时任务写的               | `AI_TIMEOUT`（在跑超过 15 分钟）、`START_FAILED`（没叫到 AI 15 分钟）；`ai_raw.interrupted = "sweep"`                                                                 |
| 看不懂的档案               | `UNSUPPORTED_FILE`、`FILE_TOO_LARGE`、`EMPTY_FILE`、`FILE_NOT_FOUND`、`INVALID_FILE_PATH`、`SPREADSHEET_UNREADABLE`、`EMPTY_SPREADSHEET`、`TOO_MANY_ROWS`             |
| AI 读不到                  | `AI_REFUSED`、`AI_TRUNCATED`、`AI_INVALID_OUTPUT`、`NO_PRODUCTS_FOUND`                                                                                                |
| 网络 / 服务                | `AI_TIMEOUT`、`AI_BUSY`、`AI_UNAVAILABLE`、`AI_FAILED`、`AI_AUTH_FAILED`、`AI_REQUEST_REJECTED`、`AI_NOT_CONFIGURED`、`DOWNLOAD_FAILED`、`DB_ERROR`、`INTERNAL_ERROR` |

`ai_raw` 存整份 AI 回传（`outputs`），另外 `rows[]` 按 `row_no` 放每行的 `source_ref`、`unit_raw`、`notes`（看不清的行是
`unreadable_reason`）， `document` 放 `supplier_name`、`order_min_sen`、`document_notes`，`calls[]` 是每次叫 Claude
的模型 / stop_reason / 用量。
