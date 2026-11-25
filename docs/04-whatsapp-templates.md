# WhatsApp 模板：送审内容和步骤

> 给老板看的。没装 App 的批发商和店铺，订单是用 WhatsApp「模板消息」发的。
> 模板要先交给 Meta（WhatsApp 的公司）审核，批准了才能用。这份文件就是要送审的内容，照抄就可以。
> 技术用的 JSON 在最后的「附录」（点开才看得到）。

## 1. 一共三个模板

| 模板名字 | 发给谁 | 什么时候发 | 按钮 |
|---|---|---|---|
| `order_new_v1` | 批发商 | 有新订单 | 两个：「确认订单」「缺货」 |
| `order_status_v1` | 店铺（买家） | 订单确认了、缺货、送货中、送到了 | 没有 |
| `order_cancelled_v1` | 批发商 | 买家取消订单 | 没有 |

每个模板都要送 **三种语言**：华文（`zh_CN`，Chinese (CHN)）、英文（`en`，English）、马来文（`ms`，Malay）。
三种语言用**同一个模板名字**，每种语言各自审核。系统会照对方设定的语言发；哪一种语言还没批准，那种语言的人就收不到。

**分类一律选 UTILITY（实用 / Utility）**，不要选 MARKETING（营销）。内容只写订单资料，不要放任何促销字眼。

## 2. 送审的内容

下面的 `{{order_no}}` 这种是「变量」，每张订单会自动换成真的资料。送审时 Meta 会要求每个变量给一个例子，例子也在下面。

### 2.1 `order_new_v1`（新订单，发给批发商）

**华文 zh_CN**

```text
您有一张新订单 {{order_no}}。
店铺：{{shop_name}}
货品：{{items}}
总额：{{total}}
送货日期：{{delivery_date}}
地址：{{address}}
请按下面的按钮确认订单，或告诉我们缺货。
```

按钮（Quick reply / 快速回复，顺序不能换）：① `确认订单` ② `缺货`

**English en**

```text
You have a new order {{order_no}}.
Shop: {{shop_name}}
Items: {{items}}
Total: {{total}}
Delivery date: {{delivery_date}}
Address: {{address}}
Please tap a button below to confirm the order or tell us it is out of stock.
```

Buttons (Quick reply, keep this order): ① `Confirm order` ② `Out of stock`

**Bahasa Melayu ms**

```text
Anda menerima pesanan baharu {{order_no}}.
Kedai: {{shop_name}}
Barangan: {{items}}
Jumlah: {{total}}
Tarikh hantar: {{delivery_date}}
Alamat: {{address}}
Sila tekan butang di bawah untuk mengesahkan pesanan atau memaklumkan stok habis.
```

Butang (Quick reply, ikut susunan ini): ① `Sahkan pesanan` ② `Stok habis`

变量的例子（三种语言大同小异，附录里有每种语言的版本）：

| 变量 | 意思 | 例子 |
|---|---|---|
| `order_no` | 订单号码 | JHB261126-00012 |
| `shop_name` | 店名 | 阿成茶室 |
| `items` | 货品清单（一行，用「; 」隔开） | 16安士 PP杯 95口径 x2 箱; 95 平盖 x1 箱 |
| `total` | 总额 | RM178.00 |
| `delivery_date` | 送货日期 | 2026年11月26日（星期四） |
| `address` | 店的地址 | 12, Jalan Kuning 2, Taman Pelangi, 80400 Johor Bahru |

批发商按了按钮之后，系统会马上回一句普通文字（例如「✅ 已确认订单 JHB261126-00012。谢谢！请按时送货。」），这句**不用送审**。

### 2.2 `order_status_v1`（订单状态，发给店铺）

**华文 zh_CN**

```text
您的订单 {{order_no}} 有更新。
批发商：{{wholesaler_name}}
状态：{{status_text}}
总额：{{total}}
如有问题，请直接回复这条消息。
```

**English en**

```text
Your order {{order_no}} has been updated.
Wholesaler: {{wholesaler_name}}
Status: {{status_text}}
Total: {{total}}
If you have any questions, just reply to this message.
```

**Bahasa Melayu ms**

```text
Pesanan anda {{order_no}} telah dikemas kini.
Pemborong: {{wholesaler_name}}
Status: {{status_text}}
Jumlah: {{total}}
Jika ada sebarang pertanyaan, balas sahaja mesej ini.
```

| 变量 | 意思 | 例子 |
|---|---|---|
| `order_no` | 订单号码 | JHB261126-00012 |
| `wholesaler_name` | 批发商名字 | 新山包装批发 |
| `status_text` | 现在的状态 | 已确认（1 样缺货，不算钱） |
| `total` | 总额 | RM178.00 |

### 2.3 `order_cancelled_v1`（订单取消，发给批发商）

**华文 zh_CN**

```text
订单 {{order_no}} 已取消。
店铺：{{shop_name}}
原因：{{reason}}
这张订单不用再送货，谢谢。
```

**English en**

```text
Order {{order_no}} has been cancelled.
Shop: {{shop_name}}
Reason: {{reason}}
This order no longer needs to be delivered. Thank you.
```

**Bahasa Melayu ms**

```text
Pesanan {{order_no}} telah dibatalkan.
Kedai: {{shop_name}}
Sebab: {{reason}}
Pesanan ini tidak perlu dihantar lagi. Terima kasih.
```

| 变量 | 意思 | 例子 |
|---|---|---|
| `order_no` | 订单号码 | JHB261126-00012 |
| `shop_name` | 店名 | 阿成茶室 |
| `reason` | 取消原因（买家没写就是「没有说明」） | 下错单了 |

## 3. 怎么送审（在 WhatsApp Manager 里做）

1. 打开 Meta Business Suite →「WhatsApp Manager」→「Message templates（消息模板）」→「Create template（建立模板）」。
2. 分类选 **Utility**；名字照上面打（全部小写，例如 `order_new_v1`）；语言先选一种。
3. 「变量类型」选 **Name（具名）**，不要选 Number（数字）。打 `{{order_no}}` 这种名字。
4. 内文照第 2 节**一字不差**贴上（换行也一样）。每个变量填一个例子。
5. **页脚（Footer）可以不填**。要填的话只写公司或 App 名字（最多 60 个字），不要写「优惠」「促销」这些字。
6. 只有 `order_new_v1` 要加按钮：选「Quick reply（快速回复）」，加两个，**第一个是确认、第二个是缺货**（顺序很重要，系统是按顺序认按钮的）。
7. 送出。再建同一个名字的另外两种语言（选「Add language / 加语言」）。
8. 审核一般几分钟到 24 小时。批准后状态是「Active / Approved」。

### 送审小提醒

- **内容不能以变量开头或结尾**：上面每个模板前后都有固定的字，不要删。
- **变量里不能有换行**：系统已经自动把货品清单变成一行（用「; 」隔开），地址的换行也会变成空格。
- **整段内文最多 1024 个字**：货品太多时，系统会自动截短，后面加「; …」。
- **按钮的字最多 25 个字**：上面的都没超过。Meta 的文件写按钮「只能用字母和数字」，华文按钮能不能过要实际送一次才知道。如果华文按钮被拒绝，华文版的按钮可以改用英文 `Confirm order` / `Out of stock`（只改按钮的字就好，内文照旧，系统不用改）。
- **一定要看批准后的分类**：如果 Meta 觉得像广告，会直接**以 MARKETING 批准**（不会拒绝），费用贵 6 倍。批准后在模板列表看「Category」那一栏，是 Marketing 就删掉重写、再送一次（删掉的名字 30 天内不能再用，所以重送时改名，例如 `order_new_v2`，再告诉技术人员改代码里的名字）。
- **要不要设短一点的有效时间**：对方手机没开的话，Meta 默认会在 30 天内一直重试。送审画面如果有「消息有效期（Message validity period）」的设定，`order_new_v1` 建议设短一点（例如 12 小时），免得几天后才收到旧订单。
- 改模板：批准后的模板 30 天内最多改 10 次、24 小时内最多 1 次，而且分类不能改。所以送审前先检查好。
- 名字后面的 `_v1` 是版本。以后内容大改就用 `_v2`，旧的先留着，等新的批准再停用。

## 4. 发 WhatsApp 之前要做的事

- **对方要先同意**：Meta 规定，发 WhatsApp 之前要有对方同意收消息的记录。批发商在 App 设定打开「用 WhatsApp 收订单」，或客服在后台登记，系统才会发（没有同意的就不发）。
- **新账号每天只能主动发给 250 个不同号码**：做完「商业验证（Business verification）」会提高到 2,000 以上。新山第一阶段够用，但建议早点做验证。
- **同一个号码大约每 6 秒只能收 1 条**：系统已经自动排队，一个号码一次只发一条。
- 要用「系统用户（System user）」的**永久 token**（技术人员设定 `WHATSAPP_TOKEN`）。App Dashboard 上的临时 token 几个小时就过期。

## 5. 费用（2026 年 10 月 1 日起的价钱）

| 消息 | 马来西亚号码每条 | 说明 |
|---|---|---|
| UTILITY 模板（新订单、状态、取消） | 约 **RM0.0564**（USD 0.014） | 送达才收钱；就算对方 24 小时内刚发过消息也照收 |
| 按按钮之后回的普通文字 | **免费**（每个号码每月前 1,000 条） | 第 1,001 条起每条约 RM0.0564 |
| 被判成 MARKETING 的模板 | 约 **RM0.3467**（USD 0.086） | 贵 6 倍，所以分类一定要是 UTILITY |
| 对方发给我们的消息 | 免费 | |

- 一张订单通常是：1 条新订单模板（约 6 仙）+ 1 句免费回复 + 店铺 1–3 条状态模板（如果店铺也没装 App）。
- 有装 App 的人收**推送**，完全免费；只有没装 App 的才发 WhatsApp。每天早上的「今天送货总结」和「订单太久没确认」的提醒**不走 WhatsApp**（省钱）。
- 账号里**一定要有付款方式**，不然超过免费额度的消息会发不出去。
- 用马币（MYR）还是美金结账，是开 WhatsApp 账号时选的，之后不能随便改。价钱每季（1 月、4 月、7 月、10 月 1 日）可能调整。

## 6. 出问题时看这里

| 情况 | 原因 | 怎么办 |
|---|---|---|
| 某个批发商一直收不到 | 号码不是 WhatsApp、没接受新条款或 App 太旧（错误 131026） | 打电话请他更新 WhatsApp；系统不会自动一直重发 |
| 某种语言的人收不到 | 那种语言的模板还没批准（错误 132001） | 去 WhatsApp Manager 看那种语言的状态 |
| 全部都发不出去 | token 过期（错误 190）、付款有问题（131042）、账号被限制 | 通知技术人员；修好后系统会自动补发（最多再试 4 次，大约半小时内） |
| 同一个人短时间很多张单 | 每 6 秒只能 1 条（131056） | 系统会自己等一下再发 |
| 全部都发不出去，日志有 `whatsapp_alert` 131048 | 号码品质太差（太多人封锁 / 检举），Meta 限制发送量 | 去 WhatsApp Manager 看号码的品质评分；系统**不会**自动重发（重发也没用） |
| 用 Meta 给的 555 号码时全部发不出去（131037） | 号码的显示名称还没批准 | 在 WhatsApp Manager 改 / 送审显示名称；系统会重试几次并通知技术人员 |

---

## 附录：技术用的 JSON

<details>
<summary>点开看：用 API 建模板的 JSON（每种语言一个请求）</summary>

用 `POST https://graph.facebook.com/v27.0/<WHATSAPP_BUSINESS_ACCOUNT_ID>/message_templates`
（`Authorization: Bearer <system user token>`）。回传 `{"id": "...", "status": "PENDING", "category": "UTILITY"}`，
**要检查回传的 `category` 是不是 `UTILITY`**。

发送时（`dispatch-notifications` 已经做好）：`to` 用 `+60...`，`template.language.code` 用 `zh_CN` / `en` / `ms`，
body 参数用 `parameter_name`（具名）；`order_new_v1` 另外送两个 `button` component：
`{"type":"button","sub_type":"quick_reply","index":"0","parameters":[{"type":"payload","payload":"CONFIRM:<order_id>"}]}`
和 `index` `"1"` 的 `OOS:<order_id>`。这个按钮格式在 Meta 现在的文件里只见于轮播模板的例子，**上线前要用测试号码实际试一次**。
模板名字、变量名、内文都在 `supabase/functions/_shared/messages.ts`（`WHATSAPP_TEMPLATES`），测试会检查这份文件跟代码一字不差。

#### order_new_v1 · zh_CN

```json
{
  "name": "order_new_v1",
  "language": "zh_CN",
  "category": "UTILITY",
  "parameter_format": "named",
  "components": [
    {
      "type": "body",
      "text": "您有一张新订单 {{order_no}}。\n店铺：{{shop_name}}\n货品：{{items}}\n总额：{{total}}\n送货日期：{{delivery_date}}\n地址：{{address}}\n请按下面的按钮确认订单，或告诉我们缺货。",
      "example": {
        "body_text_named_params": [
          {
            "param_name": "order_no",
            "example": "JHB261126-00012"
          },
          {
            "param_name": "shop_name",
            "example": "阿成茶室"
          },
          {
            "param_name": "items",
            "example": "16安士 PP杯 95口径 x2 箱; 95 平盖 x1 箱"
          },
          {
            "param_name": "total",
            "example": "RM178.00"
          },
          {
            "param_name": "delivery_date",
            "example": "2026年11月26日（星期四）"
          },
          {
            "param_name": "address",
            "example": "12, Jalan Kuning 2, Taman Pelangi, 80400 Johor Bahru"
          }
        ]
      }
    },
    {
      "type": "buttons",
      "buttons": [
        {
          "type": "quick_reply",
          "text": "确认订单"
        },
        {
          "type": "quick_reply",
          "text": "缺货"
        }
      ]
    }
  ]
}
```

#### order_new_v1 · en

```json
{
  "name": "order_new_v1",
  "language": "en",
  "category": "UTILITY",
  "parameter_format": "named",
  "components": [
    {
      "type": "body",
      "text": "You have a new order {{order_no}}.\nShop: {{shop_name}}\nItems: {{items}}\nTotal: {{total}}\nDelivery date: {{delivery_date}}\nAddress: {{address}}\nPlease tap a button below to confirm the order or tell us it is out of stock.",
      "example": {
        "body_text_named_params": [
          {
            "param_name": "order_no",
            "example": "JHB261126-00012"
          },
          {
            "param_name": "shop_name",
            "example": "Kedai Kopi Ah Seng"
          },
          {
            "param_name": "items",
            "example": "16oz PP cup 95mm x2 carton; 95mm flat lid x1 carton"
          },
          {
            "param_name": "total",
            "example": "RM178.00"
          },
          {
            "param_name": "delivery_date",
            "example": "Thu, 26 Nov 2026"
          },
          {
            "param_name": "address",
            "example": "12, Jalan Kuning 2, Taman Pelangi, 80400 Johor Bahru"
          }
        ]
      }
    },
    {
      "type": "buttons",
      "buttons": [
        {
          "type": "quick_reply",
          "text": "Confirm order"
        },
        {
          "type": "quick_reply",
          "text": "Out of stock"
        }
      ]
    }
  ]
}
```

#### order_new_v1 · ms

```json
{
  "name": "order_new_v1",
  "language": "ms",
  "category": "UTILITY",
  "parameter_format": "named",
  "components": [
    {
      "type": "body",
      "text": "Anda menerima pesanan baharu {{order_no}}.\nKedai: {{shop_name}}\nBarangan: {{items}}\nJumlah: {{total}}\nTarikh hantar: {{delivery_date}}\nAlamat: {{address}}\nSila tekan butang di bawah untuk mengesahkan pesanan atau memaklumkan stok habis.",
      "example": {
        "body_text_named_params": [
          {
            "param_name": "order_no",
            "example": "JHB261126-00012"
          },
          {
            "param_name": "shop_name",
            "example": "Kedai Kopi Ah Seng"
          },
          {
            "param_name": "items",
            "example": "Cawan PP 16oz 95mm x2 karton; Penutup rata 95mm x1 karton"
          },
          {
            "param_name": "total",
            "example": "RM178.00"
          },
          {
            "param_name": "delivery_date",
            "example": "Khamis, 26 Nov 2026"
          },
          {
            "param_name": "address",
            "example": "12, Jalan Kuning 2, Taman Pelangi, 80400 Johor Bahru"
          }
        ]
      }
    },
    {
      "type": "buttons",
      "buttons": [
        {
          "type": "quick_reply",
          "text": "Sahkan pesanan"
        },
        {
          "type": "quick_reply",
          "text": "Stok habis"
        }
      ]
    }
  ]
}
```

#### order_status_v1 · zh_CN

```json
{
  "name": "order_status_v1",
  "language": "zh_CN",
  "category": "UTILITY",
  "parameter_format": "named",
  "components": [
    {
      "type": "body",
      "text": "您的订单 {{order_no}} 有更新。\n批发商：{{wholesaler_name}}\n状态：{{status_text}}\n总额：{{total}}\n如有问题，请直接回复这条消息。",
      "example": {
        "body_text_named_params": [
          {
            "param_name": "order_no",
            "example": "JHB261126-00012"
          },
          {
            "param_name": "wholesaler_name",
            "example": "新山包装批发"
          },
          {
            "param_name": "status_text",
            "example": "已确认（1 样缺货，不算钱）"
          },
          {
            "param_name": "total",
            "example": "RM178.00"
          }
        ]
      }
    }
  ]
}
```

#### order_status_v1 · en

```json
{
  "name": "order_status_v1",
  "language": "en",
  "category": "UTILITY",
  "parameter_format": "named",
  "components": [
    {
      "type": "body",
      "text": "Your order {{order_no}} has been updated.\nWholesaler: {{wholesaler_name}}\nStatus: {{status_text}}\nTotal: {{total}}\nIf you have any questions, just reply to this message.",
      "example": {
        "body_text_named_params": [
          {
            "param_name": "order_no",
            "example": "JHB261126-00012"
          },
          {
            "param_name": "wholesaler_name",
            "example": "JB Packaging Supply"
          },
          {
            "param_name": "status_text",
            "example": "Confirmed (1 item out of stock, not charged)"
          },
          {
            "param_name": "total",
            "example": "RM178.00"
          }
        ]
      }
    }
  ]
}
```

#### order_status_v1 · ms

```json
{
  "name": "order_status_v1",
  "language": "ms",
  "category": "UTILITY",
  "parameter_format": "named",
  "components": [
    {
      "type": "body",
      "text": "Pesanan anda {{order_no}} telah dikemas kini.\nPemborong: {{wholesaler_name}}\nStatus: {{status_text}}\nJumlah: {{total}}\nJika ada sebarang pertanyaan, balas sahaja mesej ini.",
      "example": {
        "body_text_named_params": [
          {
            "param_name": "order_no",
            "example": "JHB261126-00012"
          },
          {
            "param_name": "wholesaler_name",
            "example": "JB Packaging Supply"
          },
          {
            "param_name": "status_text",
            "example": "Disahkan (1 barang habis stok, tidak dicaj)"
          },
          {
            "param_name": "total",
            "example": "RM178.00"
          }
        ]
      }
    }
  ]
}
```

#### order_cancelled_v1 · zh_CN

```json
{
  "name": "order_cancelled_v1",
  "language": "zh_CN",
  "category": "UTILITY",
  "parameter_format": "named",
  "components": [
    {
      "type": "body",
      "text": "订单 {{order_no}} 已取消。\n店铺：{{shop_name}}\n原因：{{reason}}\n这张订单不用再送货，谢谢。",
      "example": {
        "body_text_named_params": [
          {
            "param_name": "order_no",
            "example": "JHB261126-00012"
          },
          {
            "param_name": "shop_name",
            "example": "阿成茶室"
          },
          {
            "param_name": "reason",
            "example": "下错单了"
          }
        ]
      }
    }
  ]
}
```

#### order_cancelled_v1 · en

```json
{
  "name": "order_cancelled_v1",
  "language": "en",
  "category": "UTILITY",
  "parameter_format": "named",
  "components": [
    {
      "type": "body",
      "text": "Order {{order_no}} has been cancelled.\nShop: {{shop_name}}\nReason: {{reason}}\nThis order no longer needs to be delivered. Thank you.",
      "example": {
        "body_text_named_params": [
          {
            "param_name": "order_no",
            "example": "JHB261126-00012"
          },
          {
            "param_name": "shop_name",
            "example": "Kedai Kopi Ah Seng"
          },
          {
            "param_name": "reason",
            "example": "Ordered by mistake"
          }
        ]
      }
    }
  ]
}
```

#### order_cancelled_v1 · ms

```json
{
  "name": "order_cancelled_v1",
  "language": "ms",
  "category": "UTILITY",
  "parameter_format": "named",
  "components": [
    {
      "type": "body",
      "text": "Pesanan {{order_no}} telah dibatalkan.\nKedai: {{shop_name}}\nSebab: {{reason}}\nPesanan ini tidak perlu dihantar lagi. Terima kasih.",
      "example": {
        "body_text_named_params": [
          {
            "param_name": "order_no",
            "example": "JHB261126-00012"
          },
          {
            "param_name": "shop_name",
            "example": "Kedai Kopi Ah Seng"
          },
          {
            "param_name": "reason",
            "example": "Tersalah pesan"
          }
        ]
      }
    }
  ]
}
```

</details>
