import { assert, assertEquals, assertMatch, assertStringIncludes } from "@std/assert";
import {
  buttonReplyText,
  formatDate,
  formatMoney,
  LOCALES,
  type NotificationItem,
  pushContent,
  renderTemplate,
  STATUS_LABELS,
  toLocale,
  truncateList,
  UNIT_LABELS,
  WHATSAPP_BODY_MAX,
  WHATSAPP_TEMPLATES,
  whatsappTemplate,
} from "../_shared/messages.ts";

const ORDER_ID = "5b1c2d3e-0000-4000-8000-123456789abc";

function item(over: Partial<NotificationItem>): NotificationItem {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    event_type: "order_new",
    payload: {},
    locale: "zh",
    channel: "push",
    push_targets: [],
    whatsapp_phone: null,
    details: null,
    ...over,
  };
}

const details = {
  order_id: ORDER_ID,
  order_no: "JHB261126-00012",
  status: "pending",
  shop_name: "阿成茶室",
  shop_address: "12, Jalan Kuning 2,\nTaman Pelangi",
  shop_phone: "60123456789",
  wholesaler_name: "新山包装批发",
  items_text: "16安士 PP杯 95口径 x2 箱; 95 平盖 x1 箱",
  item_count: 2,
  total_sen: 17800,
  expected_delivery_date: "2026-11-26",
  out_of_stock_count: 0,
};

Deno.test("钱：RM 两位小数、千位逗号", () => {
  assertEquals(formatMoney(0), "RM0.00");
  assertEquals(formatMoney(5), "RM0.05");
  assertEquals(formatMoney(17800), "RM178.00");
  assertEquals(formatMoney(128000), "RM1,280.00");
  assertEquals(formatMoney(123456789), "RM1,234,567.89");
  assertEquals(formatMoney(null), "RM0.00");
  assertEquals(formatMoney("4550"), "RM45.50");
});

Deno.test("日期：三语、马来西亚时间", () => {
  assertEquals(formatDate("2026-11-26", "zh"), "2026年11月26日（星期四）");
  assertEquals(formatDate("2026-11-26", "en"), "Thu, 26 Nov 2026");
  assertEquals(formatDate("2026-11-26", "ms"), "Khamis, 26 Nov 2026");
  assertEquals(formatDate("2026-11-29", "ms"), "Ahad, 29 Nov 2026");
  // UTC 17:30 = 马来西亚隔天 01:30
  assertEquals(formatDate("2026-11-25T17:30:00Z", "en"), "Thu, 26 Nov 2026");
  assertEquals(formatDate("2026-11-25T15:59:00+00:00", "en"), "Wed, 25 Nov 2026");
  assertEquals(formatDate("not a date", "zh"), null);
  assertEquals(formatDate(null, "zh"), null);
});

Deno.test("单位、状态三语都有；locale 不认识就用 zh", () => {
  for (const u of ["carton", "pack", "bag", "roll", "bundle", "box", "piece", "dozen", "kg"]) {
    for (const l of LOCALES) assert(UNIT_LABELS[u][l], `${u} ${l}`);
  }
  for (const s of ["pending", "confirmed", "out_of_stock", "delivering", "delivered", "cancelled"]) {
    for (const l of LOCALES) assert(STATUS_LABELS[s][l], `${s} ${l}`);
  }
  assertEquals(toLocale("ms"), "ms");
  assertEquals(toLocale("fr"), "zh");
  assertEquals(toLocale(null), "zh");
});

Deno.test("truncateList 截到某一样为止", () => {
  assertEquals(truncateList("a; b; c", 100), "a; b; c");
  assertEquals(truncateList("aaaa; bbbb; cccc", 13), "aaaa; bbbb; …");
  assert([...truncateList("x".repeat(50), 10)].length <= 10);
});

Deno.test("推送：新订单（三语），data 全部是字串", () => {
  const zh = pushContent(item({ details, payload: { order_id: ORDER_ID, order_no: "JHB261126-00012" } }));
  assertEquals(zh.title, "新订单 JHB261126-00012");
  assertStringIncludes(zh.body, "阿成茶室");
  assertStringIncludes(zh.body, "RM178.00");
  assertStringIncludes(zh.body, "2026年11月26日（星期四）送货");
  assertStringIncludes(zh.body, "95 平盖 x1 箱");
  assertEquals(zh.data, {
    type: "order_new",
    notification_id: "11111111-1111-4111-8111-111111111111",
    order_id: ORDER_ID,
    order_no: "JHB261126-00012",
  });
  assertEquals(zh.tag, `order-${ORDER_ID}`);
  for (const v of Object.values(zh.data)) assertEquals(typeof v, "string");

  const en = pushContent(item({ details, locale: "en" }));
  assertEquals(en.title, "New order JHB261126-00012");
  assertStringIncludes(en.body, "delivery Thu, 26 Nov 2026");
  const ms = pushContent(item({ details, locale: "ms" }));
  assertEquals(ms.title, "Pesanan baharu JHB261126-00012");
});

Deno.test("推送：状态改变（部分缺货）、取消、每日总结、客服提醒、不认识的事件", () => {
  const confirmed = pushContent(item({
    event_type: "order_status_changed",
    payload: { order_id: ORDER_ID, order_no: "JHB1", status: "confirmed", wholesaler_name: "ABC", total_sen: 9000 },
    details: { ...details, order_no: "JHB1", status: "delivering", out_of_stock_count: 2, total_sen: 9000 },
  }));
  assertEquals(confirmed.title, "订单已确认"); // 用 payload.status，不是现在的 details.status
  assertStringIncludes(confirmed.body, "RM90.00");
  assertStringIncludes(confirmed.body, "2 样缺货，不算钱");

  const delivered = pushContent(item({
    event_type: "order_status_changed",
    locale: "en",
    payload: { order_id: ORDER_ID, order_no: "JHB1", status: "delivered", wholesaler_name: "ABC" },
  }));
  assertEquals(delivered.title, "Delivered");

  const cancelled = pushContent(item({
    event_type: "order_cancelled",
    payload: { order_id: ORDER_ID, order_no: "JHB1", shop_name: "阿成", reason: null },
  }));
  assertEquals(cancelled.title, "订单已取消 JHB1");
  assertStringIncludes(cancelled.body, "原因：没有说明");

  const summary = pushContent(item({
    event_type: "daily_summary",
    locale: "ms",
    payload: { date: "2026-11-26", order_count: 3, pending_count: 1, total_sen: 47200 },
  }));
  assertEquals(summary.title, "3 pesanan untuk dihantar hari ini");
  assertStringIncludes(summary.body, "RM472.00");
  assertStringIncludes(summary.body, "1 masih menunggu pengesahan");
  assertEquals(summary.data.date, "2026-11-26");
  assertEquals(summary.tag, "daily-summary");
  assertEquals(summary.ttlSeconds, 43200);

  const pendingOnly = pushContent(item({
    event_type: "daily_summary",
    payload: { date: "2026-11-26", order_count: 0, pending_count: 2, total_sen: 0 },
  }));
  assertEquals(pendingOnly.title, "今天还有 2 张单没确认");

  const alert = pushContent(item({
    event_type: "order_unconfirmed",
    payload: {
      order_id: ORDER_ID,
      order_no: "JHB1",
      wholesaler_id: "w1",
      wholesaler_name: "ABC",
      wholesaler_phone: "60123",
      shop_name: "阿成",
      pending_minutes: 45,
    },
  }));
  assertEquals(alert.title, "订单 JHB1 等了 45 分钟还没确认");
  assertStringIncludes(alert.body, "ABC（60123）");
  assertEquals(alert.data.wholesaler_id, "w1");

  const other = pushContent(item({ event_type: "trial_ending", locale: "en", payload: {} }));
  assertEquals(other.title, "New notification");
  assert(!/\n/.test(other.body));
});

Deno.test("WhatsApp 模板定义：送审规则", () => {
  for (const def of Object.values(WHATSAPP_TEMPLATES)) {
    assertMatch(def.name, /^[a-z0-9_]+$/);
    for (const l of LOCALES) {
      const body = def.body[l];
      // 不能以变量开头或结尾
      assert(!body.trim().startsWith("{{"), `${def.name} ${l} starts with variable`);
      assert(!body.trim().endsWith("}}"), `${def.name} ${l} ends with variable`);
      // 变量跟参数清单一样（具名、小写加底线）
      const vars = [...body.matchAll(/\{\{(\w+)\}\}/g)].map((m) => m[1]);
      assertEquals(vars, [...def.params], `${def.name} ${l} variables`);
      for (const v of vars) assertMatch(v, /^[a-z_]+$/);
      // 例子换进去也不超过 1024 字
      const examples = Object.fromEntries(
        def.params.map((p) => [p, (def.examples as Record<string, Record<string, string>>)[p][l]]),
      );
      assert([...renderTemplate(def.name, l, examples)].length <= WHATSAPP_BODY_MAX);
      for (const b of def.buttons) assert([...b[l]].length <= 25, `${def.name} button ${b[l]}`);
    }
  }
  assertEquals(WHATSAPP_TEMPLATES.order_new_v1.buttons.length, 2);
});

Deno.test("WhatsApp：新订单模板参数和按钮 payload", () => {
  const t = whatsappTemplate(item({ channel: "whatsapp", details, payload: { order_id: ORDER_ID } }))!;
  assertEquals(t.name, "order_new_v1");
  assertEquals(t.languageCode, "zh_CN");
  assertEquals(Object.keys(t.params), [...WHATSAPP_TEMPLATES.order_new_v1.params]);
  assertEquals(t.params.total, "RM178.00");
  assertEquals(t.params.delivery_date, "2026年11月26日（星期四）");
  assertEquals(t.params.address, "12, Jalan Kuning 2, Taman Pelangi"); // 换行变空格
  assertEquals(t.buttons, [{ index: 0, payload: `CONFIRM:${ORDER_ID}` }, { index: 1, payload: `OOS:${ORDER_ID}` }]);
  for (const v of Object.values(t.params)) {
    assert(!/[\n\t]/.test(v) && !/ {2,}/.test(v) && v.length > 0, JSON.stringify(v));
  }

  const en = whatsappTemplate(item({ locale: "en", details: { ...details, shop_address: null } }))!;
  assertEquals(en.languageCode, "en");
  assertEquals(en.params.address, "(not provided)");
  assertEquals(whatsappTemplate(item({ locale: "ms", details }))!.languageCode, "ms");
});

Deno.test("WhatsApp：内文太长就缩短货品清单（≤ 1024 字）", () => {
  const many = Array.from({ length: 80 }, (_, i) => `货品${i} 很长的名字 ABCDEFGHIJ x${i + 1} 箱`).join("; ");
  const t = whatsappTemplate(item({
    details: { ...details, items_text: many, shop_address: "地址".repeat(200) },
  }))!;
  const body = renderTemplate(t.name, "zh", t.params);
  assert([...body].length <= WHATSAPP_BODY_MAX, String([...body].length));
  assert(t.params.items.endsWith("; …"));
});

Deno.test("WhatsApp：状态 / 取消模板；没有模板的事件 → null", () => {
  const s = whatsappTemplate(item({
    event_type: "order_status_changed",
    locale: "ms",
    payload: { order_id: ORDER_ID, order_no: "JHB1", status: "confirmed", wholesaler_name: "ABC", total_sen: 100 },
    details: { ...details, out_of_stock_count: 1, total_sen: 100 },
  }))!;
  assertEquals(s.name, "order_status_v1");
  assertEquals(s.params.status_text, "Disahkan (1 barang habis stok, tidak dicaj)");
  assertEquals(s.params.total, "RM1.00");
  assertEquals(s.buttons, []);

  const c = whatsappTemplate(item({
    event_type: "order_cancelled",
    locale: "en",
    payload: { order_id: ORDER_ID, order_no: "JHB1", shop_name: "Ah Seng", reason: "  wrong\norder  " },
  }))!;
  assertEquals(c.name, "order_cancelled_v1");
  assertEquals(c.params, { order_no: "JHB1", shop_name: "Ah Seng", reason: "wrong order" });

  assertEquals(whatsappTemplate(item({ event_type: "daily_summary" })), null);
  assertEquals(whatsappTemplate(item({ event_type: "order_new", payload: {}, details: null })), null); // 没有订单 id
});

Deno.test("按钮回复文字：三语；duplicate 不回", () => {
  assertEquals(buttonReplyText("confirmed", "JHB1", "zh"), "✅ 已确认订单 JHB1。谢谢！请按时送货。");
  assertEquals(
    buttonReplyText("confirmed", "JHB1", "en"),
    "✅ Order JHB1 confirmed. Thank you! Please deliver on time.",
  );
  assertStringIncludes(buttonReplyText("out_of_stock", "JHB1", "ms")!, "stok habis");
  assertStringIncludes(buttonReplyText("already_confirmed", "JHB1", "zh")!, "之前已经确认了");
  assertStringIncludes(buttonReplyText("already_cancelled", "JHB1", "en")!, "already been cancelled");
  assertStringIncludes(buttonReplyText("already_delivered", "JHB1", "zh")!, "「已送达」");
  assertStringIncludes(buttonReplyText("not_authorized", null, "zh")!, "这个号码不能处理");
  assertStringIncludes(buttonReplyText("order_not_found", null, "en")!, "could not find");
  assertStringIncludes(buttonReplyText("invalid_payload", null, "ms")!, "tidak dijumpai");
  assertEquals(buttonReplyText("duplicate", "JHB1", "zh"), null);
  assertEquals(buttonReplyText("something_else", "JHB1", "zh"), null);
});

Deno.test("docs/04-whatsapp-templates.md 的模板内文跟代码一模一样", async () => {
  const doc = await Deno.readTextFile(new URL("../../../docs/04-whatsapp-templates.md", import.meta.url));
  for (const def of Object.values(WHATSAPP_TEMPLATES)) {
    assertStringIncludes(doc, def.name);
    for (const l of LOCALES) {
      // 文件里的 JSON 是 JSON 字串（换行写成 \n）
      assertStringIncludes(doc, JSON.stringify(def.body[l]), `${def.name} ${l}`);
      for (const b of def.buttons) assertStringIncludes(doc, JSON.stringify(b[l]));
    }
  }
});

Deno.test("推送：收件人是批发商 → 每一种通知都带 wholesaler_id；每日总结的 tag 分开每一家", () => {
  const W1 = "cccccccc-0000-4000-8000-000000000001";
  const W2 = "cccccccc-0000-4000-8000-000000000002";
  const kinds: Partial<NotificationItem>[] = [
    { event_type: "order_new", payload: { order_id: ORDER_ID }, details },
    { event_type: "order_cancelled", payload: { order_id: ORDER_ID } },
    { event_type: "order_status_changed", payload: { order_id: ORDER_ID, status: "confirmed" } },
    { event_type: "daily_summary", payload: { date: "2026-11-26", order_count: 1, pending_count: 0 } },
    { event_type: "invoice_issued", payload: { invoice_id: "9b1c2d3e-0000-4000-8000-123456789abc" } },
    { event_type: "invoice_due_soon", payload: {} },
    { event_type: "invoice_overdue", payload: {} },
    { event_type: "payment_received", payload: { purpose: "listing_fee" } },
    { event_type: "something_new", payload: {} },
  ];
  for (const k of kinds) {
    const p1 = pushContent(item({ ...k, wholesaler_id: W1 }));
    const p2 = pushContent(item({ ...k, wholesaler_id: W2 }));
    assertEquals(p1.data.wholesaler_id, W1, k.event_type);
    assertEquals(p2.data.wholesaler_id, W2, k.event_type);
    // 同一种通知、两家批发商：tag 不一样（不会互相取代）；或者是同一张订单 / 账单（只属于一家）
    if (p1.tag !== null && p1.tag === p2.tag) assertMatch(p1.tag, /^(order|invoice)-/, k.event_type);
    if (p1.tag) assert(p1.tag.length <= 64, "apns-collapse-id 最多 64 字");
  }
  const s1 = pushContent(item({ ...kinds[3], wholesaler_id: W1 }));
  assertEquals(s1.tag, `daily-summary-${W1}`);
  // 收件人是店 / 客服：不带（客服提醒照旧用 payload 的 wholesaler_id）
  assertEquals(pushContent(item({ ...kinds[2], shop_id: W2 })).data.wholesaler_id, undefined);
  const alert = pushContent(
    item({ event_type: "order_unconfirmed", payload: { order_id: ORDER_ID, wholesaler_id: W2 } }),
  );
  assertEquals(alert.data.wholesaler_id, W2);
});

Deno.test("WhatsApp 模板不受 wholesaler_id 影响", () => {
  const base = item({ channel: "whatsapp", whatsapp_phone: "60123", details, payload: { order_id: ORDER_ID } });
  assertEquals(
    whatsappTemplate({ ...base, wholesaler_id: "cccccccc-0000-4000-8000-000000000001" }),
    whatsappTemplate(base),
  );
});
