# Edge Functions（第四步）

规格：[`docs/04-seller-spec.md`](../../docs/04-seller-spec.md) 第 3
节；外部服务的查证结果：[`docs/04-research.md`](../../docs/04-research.md)； WhatsApp
模板送审：[`docs/04-whatsapp-templates.md`](../../docs/04-whatsapp-templates.md)。

| 函数                     | 谁叫                                                    | 怎么验身份                                                                    |
| ------------------------ | ------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `dispatch-notifications` | pg_cron（每分钟）、`notifications` 的 trigger（pg_net） | `apikey` 头 = secret key（固定时间比较）                                      |
| `whatsapp-webhook`       | Meta                                                    | GET：`hub.verify_token`；POST：`X-Hub-Signature-256`（App Secret，原始 body） |
| `parse-price-list`       | App（`functions.invoke`）                               | `auth.getUser(jwt)`，再用用户身份（RLS）读 import                             |

三个都是 `verify_jwt = false`（`supabase/config.toml`），身份全部在代码里检查。

```
_shared/      env.ts、supabase.ts、http.ts、fcm.ts、whatsapp.ts、messages.ts（所有三语文字）、
              claude.ts、spreadsheet.ts、filetype.ts
<函数>/       index.ts（export default { fetch }）+ deno.json（部署用的 import map）
tests/        deno test（外部 API 全部用假的 fetch，不连网）
deno.json     只给本机测试用；版本要跟各函数的 deno.json 一样（tests/deno_json_test.ts 会检查）
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
| `PRICE_LIST_TIME_BUDGET_MS`（可选）          | 价目表背景工作的时间预算              | 默认 380000（付费方案 400 秒）；**免费方案设 140000**                  |
| `DISPATCH_TIME_BUDGET_MS`（可选）            | dispatcher 一次最多跑多久             | 默认 100000                                                            |

平台自动给 `SUPABASE_URL`、`SUPABASE_SECRET_KEYS`、`SUPABASE_PUBLISHABLE_KEYS`（旧项目退回 `SUPABASE_SERVICE_ROLE_KEY` /
`SUPABASE_ANON_KEY`）。 pg_cron 用的 Vault 秘密 `secret_key` 要放 **default** 那把 secret key。

## 本机

```sh
cd supabase/functions
deno task check && deno task lint && deno task fmt && deno task test
```

不用 Docker、不连外网（Deno 会下载 npm / jsr / cdn.sheetjs.com 的套件；npm 版本要发布满 24 小时才装得到）。
`supabase functions serve` 要 Docker；`config.toml` 的 `[edge_runtime] policy = "per_worker"`
是为了让背景工作在本机跑完。

## 部署

```sh
supabase functions deploy dispatch-notifications whatsapp-webhook parse-price-list --yes
```

部署后：Meta App Dashboard → WhatsApp → Configuration：Callback URL =
`https://<project>.supabase.co/functions/v1/whatsapp-webhook`， Verify token = `WHATSAPP_VERIFY_TOKEN`，订阅
`messages`。

## parse-price-list 的 `error_message`（App 按这个显示三语原因）

| 类别         | 代码                                                                                                                                                                  |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 看不懂的档案 | `UNSUPPORTED_FILE`、`FILE_TOO_LARGE`、`EMPTY_FILE`、`FILE_NOT_FOUND`、`INVALID_FILE_PATH`、`SPREADSHEET_UNREADABLE`、`EMPTY_SPREADSHEET`、`TOO_MANY_ROWS`             |
| AI 读不到    | `AI_REFUSED`、`AI_TRUNCATED`、`AI_INVALID_OUTPUT`、`NO_PRODUCTS_FOUND`                                                                                                |
| 网络 / 服务  | `AI_TIMEOUT`、`AI_BUSY`、`AI_UNAVAILABLE`、`AI_FAILED`、`AI_AUTH_FAILED`、`AI_REQUEST_REJECTED`、`AI_NOT_CONFIGURED`、`DOWNLOAD_FAILED`、`DB_ERROR`、`INTERNAL_ERROR` |

`ai_raw` 存整份 AI 回传（`outputs`），另外 `rows[]` 按 `row_no` 放每行的 `source_ref`、`unit_raw`、`notes`（看不清的行是
`unreadable_reason`）， `document` 放 `supplier_name`、`order_min_sen`、`document_notes`，`calls[]` 是每次叫 Claude
的模型 / stop_reason / 用量。
