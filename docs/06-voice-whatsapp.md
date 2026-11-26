# 第六步：语音下单、WhatsApp 下单

> 程序：`supabase/migrations/20261129000100_voice_whatsapp.sql`（测试 `09_voice_whatsapp.test.sql`）、
> Edge Functions `voice-order`、`whatsapp-webhook`（扩充）、`dispatch-notifications`（WhatsApp 回复），
> App 的麦克风和「确认语音订单」页，客服后台的「WhatsApp 订单」。

## 1. 语音转文字选哪家（2026-11 查的）

| | 华语 | 广东话 | 福建话 | 马来文 / 英文混着讲 | 价钱（批量） |
|---|---|---|---|---|---|
| **ElevenLabs Scribe（选这个）** | 有 | 有（yue） | 没有列出 | 自动判断；v3 可以给几种「第二语言」；可以给商品名当 keyterms | 约 USD 0.20–0.40 / 小时 |
| Speechmatics（备选） | 有，`cmn_en` 双语 | 有（单语） | 没有 | `en_ms` 双语、`cmn_en_ms_ta` 一个模型混着讲 | 约 USD 0.24 / 小时起 |
| Google Chirp 3 / Deepgram / AssemblyAI | 有 | 部分 | 没有 | 部分支持 | 差不多 |

- **没有一家正式支持福建话**（新马口音更没有）。所以：转出来的字照样交给 Claude，提示词里说明广东话 / 福建话可能被写成近音的华语字或拼音；
  老板一定会看到「我听到的」和每一行「你说：…」，AI 不确定的行标黄色，**不会自己下单**。
- 选 ElevenLabs：广东话、华语、马来文、英文都在同一个模型、可以混着讲，还能把这家店的商品名当 keyterms（「十六安士」「kotak」认得比较准）。
  马来文 + 英文为主的店多了、或 ElevenLabs 不好用时，改用 Speechmatics `cmn_en_ms_ta`（`_shared/stt.ts` 只有一个 `transcribe()`，换起来只改这个档）。
- 上线前照第一步说的：录 20–30 段新山老板真实的下单语音，两家都测，再定。

来源：[ElevenLabs Speech to Text](https://elevenlabs.io/docs/capabilities/speech-to-text)、
[ElevenLabs API（convert）](https://elevenlabs.io/docs/api-reference/speech-to-text/convert)、
[ElevenLabs 价钱](https://elevenlabs.io/pricing/api)、
[Speechmatics 东南亚双语模型](https://www.speechmatics.com/company/articles-and-news/speechmatics-launches-worlds-first-bilingual-voice-ai-models-for-southeast-asia)、
[Speechmatics English/Mandarin/Malay/Tamil](https://www.speechmatics.com/speech-to-text/english-mandarin-malay-tamil)、
[Speechmatics 价钱](https://www.speechmatics.com/pricing)、
[Google Chirp 3](https://docs.cloud.google.com/speech-to-text/docs/models/chirp-3)、
[Deepgram Malay](https://deepgram.com/product/speech-to-text/malay)、
[AssemblyAI code-switching](https://www.assemblyai.com/blog/real-time-transcription-code-switches-multilingual-speakers)。

## 2. 流程

**App 语音：** 按住麦克风（首页、购物车）→ 录 16 kHz 单声道 WAV（最多 60 秒）→ 上传 `voice-orders/<店>/<uuid>.wav`（私人 bucket，3 MB，
只有自己店和客服读得到）→ `voice-order`：验 JWT → `reserve_voice_order_run`（成员、路径、用量：每家店 10 分钟 6 次 / 1 小时 20 / 1 天 60）→
下载 → 转文字 → `get_voice_order_context`（这家店**现在能下单**的商品：审核过、送这一区、未付费只算免费那几家；最近买过的排前面）→
Claude（`claude-opus-5-5`，json_schema，商品用代号 p1、p2……）→ `create_order_draft`（对不上的商品 / 不能下单的放进「没听懂」）→
App 打开「确认语音订单」：改数量、换一样、删掉、加一样 → `submit_order_draft` 走 `place_order`（`source = voice`）。

**WhatsApp：** webhook 记好消息 → `reserve_whatsapp_order`：
注册过的店发文字 / 语音 → 背景做草稿（语音先从 Graph 下载、存进 `voice-orders`）→ 回「收到（n 样），客服确认后帮您下单」；
不认识的号码 → 「请先注册」（24 小时内只回第一条）；照片 / 文件 → 「请用文字或语音」；批发商的号码不处理。
AI 失败的照样放进队列（空草稿 + 原因），客服自己听。客服后台「WhatsApp 订单」→ 改好 → `submit_order_draft`（`source = whatsapp`，操作记录）
→ 排一条 `whatsapp_reply`「已经帮您下单：订单号、总额」；不处理 → `reject_order_draft` 回原因。
`whatsapp_reply` 只在 24 小时客服窗口内用普通文字发，窗口过了不发（客服后台显示「请打电话」）。
老板自己发 WhatsApp 来下单，记成同意用 WhatsApp 收这张单的通知（`shops.whatsapp_opt_in_at` 空的才填）。

**通知渠道：** 买家有 App（推送 token）就一定推送，`notify_channel = whatsapp` 也一样；WhatsApp 只给没装 App 的买家。
批发商照第四步（客服可以设成 WhatsApp）。老板自己按「收到了」不再通知他自己。

## 3. 数据库函数

| 给谁 | 函数 |
|---|---|
| 服务器 | `reserve_voice_order_run(p_shop_id, p_user_id, p_run_id, p_source, p_audio_path, p_whatsapp_message_id)`、`reserve_whatsapp_order(p_message_id, p_run_id)`、`get_voice_order_context(p_shop_id)`、`create_order_draft(p_run_id, p_transcript, p_language, p_lines, p_unmatched, p_ai_meta, p_audio_path)`、`fail_voice_order_run(p_run_id, p_error_code)` |
| 老板 / 客服 | `get_order_draft(p_draft_id)`、`list_order_drafts(p_shop_id, p_limit)`、`save_order_draft(p_draft_id, p_items, p_unmatched)`、`submit_order_draft(p_draft_id, p_expected_total_sen, p_note)`、`reject_order_draft(p_draft_id, p_reason)` |
| 客服 | `admin_list_order_drafts(p_status, p_channel, p_limit)` |

新表 `order_draft_items`、`voice_order_runs`；`order_drafts` 加 `unmatched`、`language`、`ai_meta`、`reject_reason`、`run_id`。
新的错误代码：`DRAFT_NOT_FOUND`、`DRAFT_NOT_PENDING`、`DRAFT_EMPTY`、`RUN_NOT_RUNNING`、`INVALID_PRODUCT`（detail = 商品 id）、`INVALID_QTY`。
`voice-order` 的：`TOO_MANY_VOICE_ORDERS`（429，`retry_after`）、`NO_SPEECH`、`AUDIO_TOO_LONG`、`UNSUPPORTED_AUDIO`、`STT_NOT_CONFIGURED`、`AI_NOT_CONFIGURED`……

## 4. 设定（没有就安全地不做）

Edge Function secrets：`ELEVENLABS_API_KEY`（没设 → `STT_NOT_CONFIGURED`，App 显示「语音下单现在不能用」；WhatsApp 语音进队列给客服听）、
`STT_MODEL`（默认 `scribe_v2`；`scribe_v3` 会多送 `secondary_language_codes`）、`ANTHROPIC_API_KEY`、`WHATSAPP_TOKEN` / `WHATSAPP_PHONE_NUMBER_ID`（下载语音、回复）。
部署：`deno task deploy`（会打包 `voice-order`）。示范数据：`apps/admin_web/tool/export_draft_fixtures.sh`。
录音保存多久要写进 PDPA 隐私政策（现在没有自动删除）。
