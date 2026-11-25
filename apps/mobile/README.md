# 手机 App（买家端 + 批发商端）

Flutter，一个 App 给买家和批发商用，登录后按角色显示不同的首页。说明见 [`docs/03-buyer-app.md`](../../docs/03-buyer-app.md)、
[`docs/04-seller-spec.md`](../../docs/04-seller-spec.md)。

## 不用服务器，先看画面（示范模式）

```bash
flutter run -t lib/main_demo.dart            # 手机或模拟器
flutter run -t lib/main_demo.dart -d chrome  # 浏览器
```

数据是本机数据库导出的真实样本，按什么都不会真的下单。网页版可以在网址加参数：
`?lang=zh`（或 `en`、`ms`；不加就先选语言）、`?free=1`（未付费老板）、`?new=1`（还没开店）、`?login=1`（从登录开始，验证码 `123456`）、
`?seller=1`（用示范批发商 A 的账号，进批发商端：订单、送货总结、商品、价目表导入都是真实样本，按了会跟着变）。

## 连本机的 Supabase

需要 Docker。

```bash
cd ../..                      # 回到仓库最上层
npx supabase start            # 第一次会下载，要等一阵
npx supabase db reset         # 建表 + 示范数据
npx supabase status           # 抄下 API URL 和 Publishable key（旧版 CLI 叫 anon key，一样能用）
cd apps/mobile
cp config/local.example.json config/local.json   # 把 key 填进去
flutter run --dart-define-from-file=config/local.json
```

本机测试号码（验证码都是 `123456`）：`012-000 0001`（示范店老板，试用中）、`012-000 0004`（示范店老板，未付费）。

> Android 模拟器连本机电脑要用 `http://10.0.2.2:54321`，不是 `127.0.0.1`。

## 推送通知（Firebase Cloud Messaging）

没有 Firebase 设定时 **App 照样能用**，只是收不到推送（新订单还是会出现在列表里，没装 App 的批发商用 WhatsApp）。
网页版永远不开推送。

### 1. 建 Firebase 专案（老板做一次）

1. [Firebase 主控台](https://console.firebase.google.com/) 建专案，加 Android App（套件名称 `my.jbwholesale.jb_wholesale`）和
   iOS App（Bundle ID `my.jbwholesale.jbWholesale`）。
2. 专案设定 → 服务帐户 → 产生新的私密金钥 → 这份 JSON 放进 Supabase 的秘密 `FCM_SERVICE_ACCOUNT_JSON`（服务器发推送用，
   **不要**放进 App 或 git）。
3. iOS：Apple Developer 产生 APNs 验证金钥（.p8），上传到 Firebase → 专案设定 → Cloud Messaging（要 Key ID 和 Team ID）。

### 2. 让 App 认得这个专案（两种做法，选一种）

**建议：`flutterfire configure`**（Android 背景 / App 被关掉时收推送最稳）

```bash
dart pub global activate flutterfire_cli
cd apps/mobile
flutterfire configure --platforms=android,ios
```

它会产生 `android/app/google-services.json`、`ios/Runner/GoogleService-Info.plist`、`lib/firebase_options.dart`，并在 Gradle 加
`com.google.gms.google-services` plugin。然后执行时加 `--dart-define=FIREBASE_NATIVE_CONFIG=true`（用原生设定档初始化），
或者照下面第二种把 `lib/firebase_options.dart` 里的值抄进 `config/firebase.json`（两个一起用也可以，dart-define 优先）。
这些档案是每个环境自己的，仓库里没有放。

**备用：只用 `--dart-define`**（不用改原生档案）

```bash
cp config/firebase.example.json config/firebase.json   # 填进 Firebase 主控台的值
flutter run --dart-define-from-file=config/local.json --dart-define-from-file=config/firebase.json
```

App 用 `FIREBASE_API_KEY`、`FIREBASE_APP_ID_ANDROID`、`FIREBASE_APP_ID_IOS`、`FIREBASE_MESSAGING_SENDER_ID`、`FIREBASE_PROJECT_ID`、
`FIREBASE_IOS_BUNDLE_ID` 组成 `FirebaseOptions`（`lib/push/push_config.dart`）。App 开着或在背景时都收得到；
**Android 上 App 被完全关掉时收不收得到，官方没有保证，要在真的手机上试**（收不到就改用 flutterfire configure）。

### 3. iOS 要在 Xcode 做的（这里没有 Xcode，没办法替你做）

打开 `ios/Runner.xcworkspace` → Runner → Signing & Capabilities：

- 加 **Push Notifications**
- 加 **Background Modes**，勾 **Remote notifications**（`Info.plist` 已经有 `UIBackgroundModes`）

推送一定要用**真的 iPhone** 测，模拟器收不到。

### App 里怎么做的（`lib/push/`）

- 用 Firebase Installation ID（FID，2026 年的新做法）：先订阅 `onRegistered` 再 `register()`，拿到的 FID →
  `register_device_token(fid, 'android' / 'ios', 'fid')`。买家、批发商登录后都登记，每次开 App 再登记一次；登出前删掉。
- 通知权限：批发商第一次打开首页、买家第一次下单后，先用 App 的话说明，再跳系统询问；只问一次，拒绝了 App 照样能用。
- App 开着时收到：Android 用本地通知显示（频道「订单通知」`orders`，高重要性，会响）；iOS 让系统照样显示横幅。
- 点通知：新订单 → `/seller/orders/<id>`；订单有更新 / 取消 → 买家 `/orders/<id>`、批发商 `/seller/orders/<id>`；
  每天的送货总结 → `/seller/summary?date=`；客服提醒（order_unconfirmed）不跳页。App 还在读登录资料时会先记着，读完再打开。
- 测试和示范模式用不做事的 `NoopPushService`（`test/push_test.dart` 用假的 PushService 测上面这些）。

## 打印用的中文字体

`google_fonts/NotoSansSC-Regular.ttf`（Google Fonts 的 TrueType 版，SIL Open Font License，见同一个文件夹的 `OFL.txt`）。
打印送货单时 `PdfGoogleFonts.notoSansSCRegular()` 会先找这个档案，不用上网下载（下载失败会静默变成方块字）。
只放 Regular（约 10 MB），粗体也用它。不要换成 Noto Sans CJK 的 `.otf`（pdf 套件只画得出英文字母）。

## 测试

```bash
flutter analyze
flutter test        # 用示范模式把整个 App 点一遍；另外有推送、示范批发商资料、中文字体的测试
```

## 更新示范数据

示范模式和测试用的数据在 `packages/core/test/fixtures/`（本机数据库真实返回的 JSON）。改了数据库函数之后，重新导出那些 JSON，然后：

```bash
python3 tool/gen_demo_data.py
```
