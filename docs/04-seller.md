# 第四步：推送（FCM）和 WhatsApp 怎么设定、怎么测

规格见 `docs/04-seller-spec.md`；Edge Function 的部署和全部秘密见 `supabase/functions/README.md`。

## 1. Firebase 推送（FCM）

1. Firebase 主控台建项目，加 Android / iOS App（iOS 要上传 APNs 钥匙）。
2. **服务器**：项目设定 → 服务账号 → 产生新的私钥，下载 JSON。
   `supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(cat key.json)"`
   - 读的地方：`supabase/functions/_shared/env.ts` 的 `fcmServiceAccount()`；发送在 `_shared/fcm.ts`。
   - 没设：推送通知标 failed `FCM_NOT_CONFIGURED`，不重试。
3. **App**：`apps/mobile/config/firebase.example.json` 抄成 `firebase.json`，填 `FIREBASE_API_KEY`、
   `FIREBASE_APP_ID_ANDROID`、`FIREBASE_APP_ID_IOS`、`FIREBASE_MESSAGING_SENDER_ID`、`FIREBASE_PROJECT_ID`、
   `FIREBASE_IOS_BUNDLE_ID`，用 `--dart-define-from-file=config/firebase.json` 跑；
   或者跑 `flutterfire configure`，再加 `--dart-define=FIREBASE_NATIVE_CONFIG=true`。读的地方：`lib/push/push_config.dart`。
4. 批发商的通知（新订单、取消、每日总结、账单……）推送的 data 都带 `wholesaler_id`；
   每日总结的 tag 是 `daily-summary-<批发商 id>`，两家的通知不会互相盖掉。
   一个人是两家的成员，按通知会先换到那一家（`lib/push/push_navigator.dart`）。

## 2. WhatsApp Cloud API

1. Meta Business → WhatsApp → 加电话号码，建 system user，产生永久 token（权限 `whatsapp_business_messaging`）。
2. 秘密（读的地方都在 `_shared/env.ts`）：

| 名字 | 用途 |
|---|---|
| `WHATSAPP_TOKEN`、`WHATSAPP_PHONE_NUMBER_ID` | 发模板消息（`whatsappConfig()`） |
| `WHATSAPP_GRAPH_VERSION` | 可以不设，默认 `v27.0` |
| `WHATSAPP_APP_SECRET` | 验 webhook 签名（App Dashboard → 基本设定 → App 密钥） |
| `WHATSAPP_VERIFY_TOKEN` | webhook 握手，自己想一串字 |

3. 三个模板（`order_new_v1`、`order_status_v1`、`order_cancelled_v1`）的送审内容和步骤：
   [`docs/04-whatsapp-templates.md`](04-whatsapp-templates.md)。文字要跟 `_shared/messages.ts` 一字不差。
4. Webhook：Callback URL = `https://<project>.supabase.co/functions/v1/whatsapp-webhook`，
   Verify token = `WHATSAPP_VERIFY_TOKEN`，订阅 `messages`。
5. 批发商 / 店铺要先同意（`whatsapp_opt_in_at`），没有就不发。

## 3. 定时发送

SQL editor 建 Vault 秘密（迁移里不写死）：

```sql
select vault.create_secret('https://<project>.supabase.co', 'project_url');
select vault.create_secret('<secret key>', 'secret_key');
```

之后新通知会马上叫 `dispatch-notifications`，每分钟再补一次。

## 4. 怎么测

- 不用真的账号：`./scripts/test-db.sh`（数据库）、`cd supabase/functions && deno task test`（假的 fetch：
  FCM、Graph API 都是假的）、`flutter test`（App，示范模式）。
- 真的推送：App 登录批发商账号、允许通知 → 另一个账号下单 → 手机收到「新订单」，按一下打开那张单。
- 真的 WhatsApp：批发商设定里选「WhatsApp」并同意 → 下单 → 收到模板，按「确认」→ 订单变成已确认。
- 出问题：看 `notifications` 的 `status`、`last_error`；WhatsApp 送达状态看 `whatsapp_messages.delivery_status`。
