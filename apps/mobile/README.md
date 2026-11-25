# 手机 App（买家端；批发商端在第四步加进来）

Flutter，一个 App 给买家和批发商用，登录后按角色显示不同的首页。说明见 [`docs/03-buyer-app.md`](../../docs/03-buyer-app.md)。

## 不用服务器，先看画面（示范模式）

```bash
flutter run -t lib/main_demo.dart            # 手机或模拟器
flutter run -t lib/main_demo.dart -d chrome  # 浏览器
```

数据是本机数据库导出的真实样本，按什么都不会真的下单。网页版可以在网址加参数：
`?lang=zh`（或 `en`、`ms`；不加就先选语言）、`?free=1`（未付费老板）、`?new=1`（还没开店）、`?login=1`（从登录开始，验证码 `123456`）。

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

## 测试

```bash
flutter analyze
flutter test        # 用示范模式把整个 App 点一遍（13 项）
```

## 更新示范数据

示范模式和测试用的数据在 `packages/core/test/fixtures/`（本机数据库真实返回的 JSON）。改了数据库函数之后，重新导出那些 JSON，然后：

```bash
python3 tool/gen_demo_data.py
```
