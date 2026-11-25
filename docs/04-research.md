# 第四步：外部服务查证结果（2026-11-25）

> 五个主题各由一个代理查官方文档，再由另一个代理逐条核对（verdict：confirmed / corrected / unverifiable）。
> 完整报告（含出处网址、代码片段、陷阱）：[`research/step4/`](research/step4/)。这里只列影响实现的结论。

## 1. WhatsApp Business Platform（Cloud API）

| 项目 | 结论 |
|---|---|
| API 版本 | 最新 `v27.0`（2026-11-04）。放在一个设定 `WHATSAPP_GRAPH_VERSION`，默认 `v27.0` |
| 发送 | `POST https://graph.facebook.com/v27.0/<PHONE_NUMBER_ID>/messages`，`Authorization: Bearer <system user 永久 token>`。200 只代表「收到」，送达与否看状态 webhook |
| 收件号码 | 发送时用 `+60...`（不加 `+` 会被当成我们号码的国家）。webhook 进来的 `from` 是 `60...`（没有 `+`）。两边都 normalize 成纯数字比较 |
| 模板 | 分类用 **UTILITY**（订单管理）；内容不能以变量开头或结尾；变量值不要有换行（明细用 `; ` 连接）；body 最多 1024 字；quick reply 按钮最多 25 字（中文按钮能否过审要实际送审）；语言代码 `zh_CN`、`en`、`ms`，每种语言各自审核。被判成营销会**直接以 MARKETING 批准**（价钱贵 6 倍），要看回传的 category |
| 按钮 payload | 发送时 `{"type":"button","sub_type":"quick_reply","index":0,"parameters":[{"type":"payload","payload":"CONFIRM:<order_id>"}]}`，按钮顺序跟模板一样（0 = 确认，1 = 缺货）。这个格式在官方文件里只见于轮播模板的例子（可信度中），要用测试号码实际试一次 |
| webhook 验证 | GET：`hub.verify_token` 对了就**原样回传 `hub.challenge`**（纯文字、200） |
| webhook 签名 | `X-Hub-Signature-256: sha256=<hex>`，HMAC-SHA256（key = App Secret）算在**原始 body** 上，要在 `JSON.parse` 之前算 |
| 按钮回传 | `messages[]` 里 `type: "button"`，`button.payload`、`context.id`（我们发的那条消息的 wamid）、`from`、`from_user_id`。**2026 年 4 月起** 用户可以只有用户名：`from` 可能没有，只有 `from_user_id`（BSUID）→ 用 `context.id` 对回我们发的消息 |
| 重送 | Meta 失败会重送长达 7 天、可能一次多笔、顺序不保证 → 以 `messages[].id` 去重，状态只能往前走 |
| 费用（2026-10-01 起） | 马来西亚 UTILITY 模板每条约 **RM0.0564**（窗口内也收）；客户发消息后 24 小时内回的普通文字，每个号码每月前 **1,000 条免费**。按钮按下去会打开窗口 → 确认回复用普通文字 |
| 限制 | 同一个收件人约每 6 秒 1 条（错误 131056）；新账号 24 小时内只能主动发给 250 个不同号码（商业验证后提高）；没送达的消息默认 30 天内还会重试（订单模板应设较短 TTL） |
| 同意 | 发之前必须有对方同意（记录时间） |
| 错误 | 131047 超过 24 小时（改用模板）；131026 收不到（不是 WhatsApp 号码 / 没接受条款，等对方处理）；132001 模板不存在该语言；130429 / 131056 / 80007 / 131016 / 133004 / 131000 可以重试；190 token 过期要通知技术 |

## 2. Firebase Cloud Messaging

| 项目 | 结论 |
|---|---|
| 发送 | HTTP v1：`POST https://fcm.googleapis.com/v1/projects/<id>/messages:send`，OAuth2 token（服务账号 JWT RS256 → `https://oauth2.googleapis.com/token`，scope `firebase.messaging`）。Deno 用 WebCrypto 就能签（本机试过签名） |
| 2026 变化 | 正在从 registration token 改成 **Firebase Installation ID（FID）**：`message.token` 标示淘汰（还能用），新增 `message.fid`。Flutter `firebase_messaging` 17.1 的 `getToken()` 标示淘汰，新的是 `register()` + `onRegistered`，要在 Android manifest 加 `firebase_messaging_installation_id_enabled`、iOS Info.plist 加 `FirebaseMessagingInstallationIdEnabled` |
| data | 值全部要是字串 |
| 失效 | `UNREGISTERED`（404，看 `details[].errorCode`）一定删；400 只有确定是 token/FID 本身错才删（payload 错也会 400）；401 UNAUTHENTICATED = 我们的 OAuth token 过期 → 重拿一次；THIRD_PARTY_AUTH_ERROR = APNs 设定问题（不要删 token）；429/500/503 重试 |
| Flutter 版本 | `firebase_core` 5.2.0、`firebase_messaging` 17.1.0（要 minSdk 24、iOS 15，Flutter 3.47 默认就是） |
| 前台显示 | App 开着时通知**不会自动显示** → `flutter_local_notifications`（23.x，需要 compileSdk 37 和 core library desugaring）建一个高重要性的「订单」频道并自己显示 |
| 设定 | 官方做法 `flutterfire configure` 会产生 `firebase_options.dart`、`google-services.json` 并加 Gradle plugin（Android 背景推送最稳）。iOS 要 APNs key、Push + Background Modes，**要真机测试** |
| Web | 不做（要 service worker + VAPID）；web 上不初始化推送 |
| Huawei | 没有 Google Play 服务的手机收不到 FCM → 保留 WhatsApp / App 内的备用 |

## 3. Supabase

| 项目 | 结论 |
|---|---|
| 钥匙 | 2025-11 起新项目只有 `sb_publishable_` / `sb_secret_` 钥匙（**不是 JWT**，放 `apikey` 头）。Edge Function 环境变量 `SUPABASE_SECRET_KEYS`、`SUPABASE_PUBLISHABLE_KEYS` 是 **JSON**（取 `default`）；旧的 `SUPABASE_SERVICE_ROLE_KEY` 只在旧项目有 |
| 角色 | secret key = `service_role`（不受 RLS，但 GRANT 照样检查）；publishable key + 登录用户 = `authenticated` |
| Edge Functions | 每个函数自己的 `deno.json`；`export default { fetch }`（测试可以直接 import）；全部 `verify_jwt = false`，在代码里检查身份（webhook 验签名、cron 验 secret key、App 用户验 JWT）。限制：CPU 2 秒、记忆体 256 MB、等回应最多 150 秒、总时间免费版 150 秒 / 付费 400 秒；长工作用 `EdgeRuntime.waitUntil` |
| 排程 | 官方做法：Vault 存 `project_url`、`secret_key`，`pg_cron` + `net.http_post(url :=, headers := {'apikey': ...}, body :=, timeout_milliseconds :=)`（具名参数；默认只等 2 秒；交易提交后才送出；回应只留 6 小时） |
| Storage | 可以在迁移里 `insert into storage.buckets`；上传前一定要有 `storage.objects` 的 INSERT policy；`(storage.foldername(name))[1]` 是文字；档名用 ASCII（`<wholesaler_id>/<uuid>.<ext>`）；不要用 upsert |
| 本机测试 | Edge Functions 可以用一般 `deno test` 测（换掉 `fetch`）；`supabase functions serve` 要 Docker |

## 4. Claude（价目表 AI）

| 项目 | 结论 |
|---|---|
| SDK | `npm:@anthropic-ai/sdk@1.13.0`（1.x 是 2026-10 的新大版本；1.14.0 太新，被 Deno 的「发布满 24 小时」规则挡住）。`deno.json` 子路径要写 `"npm:/@anthropic-ai/sdk@1.13.0/"` |
| 请求 | `anthropic-version: 2026-10-21`：**不能**送 temperature / top_p / top_k；`claude-opus-5-5` 不能关 thinking、不能强制 tool_choice → 用 `output_config: {format: {type: "json_schema", schema}, effort: "medium"}` |
| 结构化输出 | 每个 object 都要 `additionalProperties: false`；不支持 min/max；最多 24 个可选参数、16 个 union 参数；enum 的大小写不保证（先转小写）；不要有叫 `reasoning` / `thinking` 的栏位（会被拒） |
| 安全 | 先看 `stop_reason`（`refusal`、`max_tokens`）再 parse；用 streaming + `finalMessage()`，`max_tokens` 32k |
| 输入 | 图片 base64（jpeg / png / gif / webp，**不收 HEIC**，长边 ≤ 2576 px 最划算）；PDF 用 `document` block；Excel 不能直接给 |
| Excel | SheetJS **0.20.3** 从 `https://cdn.sheetjs.com/xlsx-0.20.3/package/xlsx.mjs`（npm 的 `xlsx` 0.18.5 有安全漏洞）；Deno 要 `--allow-import=cdn.sheetjs.com`；CSV 先用 `TextDecoder('utf-8', {fatal: true})`，失败再 `gb18030` |
| 时间 | Opus 读一份价目表可能超过 150 秒 → 函数先回 202，`EdgeRuntime.waitUntil` 在背景做，状态写在 `price_list_imports`，App 用 Realtime / 轮询等结果 |
| 提示词和 schema | 见 `research/step4/claude.json` 的 snippets（已核对）：价目表是资料不是指令；一行一个产品和价钱；单位对照表（ctn / 箱 / pkt / 包 / gulung / 卷……）；价钱一律换成仙；看不清的放 `unreadable` |

## 5. Flutter 套件

| 套件 | 版本 / 重点 |
|---|---|
| `pdf` 3.13.1 + `printing` 5.15.1 | 中文用 **Noto Sans SC 的 TTF**（不是 .otf）；下载失败会静默变方块 → **把字体打包进 App**（`google_fonts/NotoSansSC-Regular.ttf`、`-Bold.ttf`，`PdfGoogleFonts` 会先找这个路径）。只嵌入用到的字，PDF 很小 |
| `share_plus` 13.3.1 | `SharePlus.instance.share(ShareParams(text: ...))`（旧的 `Share.share` 淘汰） |
| `image_picker` 1.2.4 | `pickImage(source:, maxWidth: 2576, imageQuality: 85)` → 会转成 JPEG；iOS 要 `NSCameraUsageDescription`、`NSPhotoLibraryUsageDescription` |
| `file_picker` 13.4.1 | **静态 API**：`FilePicker.pickFile(...)` → `PlatformFile?`，`readAsBytes()`（`withData`、`FilePickerResult` 都没了） |
| Storage 上传 | `storage.from('price-lists').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: ...))`；用魔术字节判断真正的格式 |
| 叫 Edge Function | `supabase.functions.invoke('parse-price-list', body: {...})` 会自动带登录 token（**不要**自己加 Authorization） |
| `url_launcher` | WhatsApp：`https://wa.me/60123456789?text=...`，`LaunchMode.externalApplication`；Android 没装 App 会丢 `PlatformException`（要 try/catch） |
