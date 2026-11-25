// 所有给人看的通知文字都在这里（三语：zh / en / ms）：
//   * 推送的标题和内容（每种 event_type）
//   * WhatsApp 模板名字、语言代码、具名参数（模板内文送审版本也在这里，docs/04-whatsapp-templates.md 照抄）
//   * 按钮按下后回的普通文字
//   * 单位、订单状态、钱（RM1,280.00）、日期（马来西亚时间）

export type Locale = "zh" | "en" | "ms";
export const LOCALES: readonly Locale[] = ["zh", "en", "ms"];

export function toLocale(v: unknown): Locale {
  return v === "en" || v === "ms" || v === "zh" ? v : "zh";
}

type Tri = Record<Locale, string>;

/** 跟数据库的 public._unit_label 一样 */
export const UNIT_LABELS: Record<string, Tri> = {
  carton: { zh: "箱", en: "carton", ms: "karton" },
  pack: { zh: "包", en: "pack", ms: "paket" },
  bag: { zh: "袋", en: "bag", ms: "beg" },
  roll: { zh: "卷", en: "roll", ms: "gulung" },
  bundle: { zh: "扎", en: "bundle", ms: "ikat" },
  box: { zh: "盒", en: "box", ms: "kotak" },
  piece: { zh: "个", en: "piece", ms: "biji" },
  dozen: { zh: "打", en: "dozen", ms: "dozen" },
  kg: { zh: "公斤", en: "kg", ms: "kg" },
};

export function unitLabel(unit: string, locale: Locale): string {
  return UNIT_LABELS[unit]?.[locale] ?? unit;
}

export const STATUS_LABELS: Record<string, Tri> = {
  pending: { zh: "待确认", en: "Waiting for confirmation", ms: "Menunggu pengesahan" },
  confirmed: { zh: "已确认", en: "Confirmed", ms: "Disahkan" },
  out_of_stock: { zh: "缺货", en: "Out of stock", ms: "Stok habis" },
  delivering: { zh: "送货中", en: "Out for delivery", ms: "Sedang dihantar" },
  delivered: { zh: "已送达", en: "Delivered", ms: "Telah dihantar" },
  cancelled: { zh: "已取消", en: "Cancelled", ms: "Dibatalkan" },
};

export function statusLabel(status: string, locale: Locale): string {
  return STATUS_LABELS[status]?.[locale] ?? status;
}

// ---------------------------------------------------------------------------
// 钱和日期
// ---------------------------------------------------------------------------

/** 仙 → "RM1,280.00" */
export function formatMoney(sen: unknown): string {
  const n = Math.round(Number(sen) || 0);
  const abs = Math.abs(n);
  const ringgit = Math.floor(abs / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  const cents = (abs % 100).toString().padStart(2, "0");
  return `${n < 0 ? "-" : ""}RM${ringgit}.${cents}`;
}

const MYT_OFFSET_MS = 8 * 3600 * 1000;

/** "2026-11-26" 或时间戳 → 马来西亚日期的 年、月、日、星期（0 = 星期日）。看不懂 → null。 */
export function mytDateParts(value: unknown): { y: number; m: number; d: number; dow: number } | null {
  if (typeof value !== "string" || value.trim() === "") return null;
  const s = value.trim();
  let t: number;
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (dateOnly) {
    t = Date.UTC(Number(dateOnly[1]), Number(dateOnly[2]) - 1, Number(dateOnly[3]));
  } else {
    const parsed = Date.parse(s);
    if (Number.isNaN(parsed)) return null;
    t = parsed + MYT_OFFSET_MS;
  }
  const dt = new Date(t);
  if (Number.isNaN(dt.getTime())) return null;
  return { y: dt.getUTCFullYear(), m: dt.getUTCMonth() + 1, d: dt.getUTCDate(), dow: dt.getUTCDay() };
}

const EN_DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const EN_MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const MS_DOW = ["Ahad", "Isnin", "Selasa", "Rabu", "Khamis", "Jumaat", "Sabtu"];
const MS_MON = ["Jan", "Feb", "Mac", "Apr", "Mei", "Jun", "Jul", "Ogo", "Sep", "Okt", "Nov", "Dis"];
const ZH_DOW = "日一二三四五六";

/** 2026-11-26 → zh「2026年11月26日（星期四）」、en「Thu, 26 Nov 2026」、ms「Khamis, 26 Nov 2026」 */
export function formatDate(value: unknown, locale: Locale): string | null {
  const p = mytDateParts(value);
  if (!p) return null;
  if (locale === "en") return `${EN_DOW[p.dow]}, ${p.d} ${EN_MON[p.m - 1]} ${p.y}`;
  if (locale === "ms") return `${MS_DOW[p.dow]}, ${p.d} ${MS_MON[p.m - 1]} ${p.y}`;
  return `${p.y}年${p.m}月${p.d}日（星期${ZH_DOW[p.dow]}）`;
}

// ---------------------------------------------------------------------------
// 字串整理
// ---------------------------------------------------------------------------

/** 换行、tab、一串空白都变成一个空格（WhatsApp 模板参数不能有） */
export function oneLine(v: unknown): string {
  return (v == null ? "" : String(v)).replace(/\s+/g, " ").trim();
}

export function truncate(s: string, max: number): string {
  const chars = [...s];
  return chars.length <= max ? s : chars.slice(0, Math.max(1, max - 1)).join("") + "…";
}

/** 「a; b; c」太长就截到某一样为止，后面加「; …」 */
export function truncateList(s: string, max: number): string {
  if ([...s].length <= max) return s;
  const parts = s.split("; ");
  let out = "";
  for (const p of parts) {
    const next = out ? `${out}; ${p}` : p;
    if ([...next].length + 3 > max) break;
    out = next;
  }
  return out ? `${out}; …` : truncate(s, max);
}

function str(v: unknown): string | null {
  if (v == null) return null;
  const s = oneLine(v);
  return s === "" ? null : s;
}

function int(v: unknown): number | null {
  const n = Number(v);
  return v != null && v !== "" && Number.isFinite(n) ? Math.trunc(n) : null;
}

// ---------------------------------------------------------------------------
// dispatcher 领到的通知（claim_notifications 回传的每一条）
// ---------------------------------------------------------------------------

export interface PushTarget {
  target: string;
  kind: "token" | "fid";
}

/** _notification_order_details 回传的订单资料 */
export interface OrderDetails {
  order_id?: string;
  order_no?: string;
  status?: string;
  shop_name?: string;
  shop_address?: string | null;
  shop_phone?: string | null;
  wholesaler_name?: string;
  items_text?: string;
  item_count?: number;
  total_sen?: number;
  expected_delivery_date?: string | null;
  out_of_stock_count?: number;
}

export interface NotificationItem {
  id: string;
  event_type: string;
  payload: Record<string, unknown>;
  locale: string | null;
  channel: "push" | "whatsapp" | null;
  push_targets: PushTarget[];
  whatsapp_phone: string | null;
  attempts?: number;
  details: OrderDetails | null;
}

/** 从 payload 和 details 拿值：details（发送时的最新资料）优先，没有再看 payload。 */
function pick(item: NotificationItem, key: string): unknown {
  const d = item.details as Record<string, unknown> | null;
  if (d && d[key] != null && d[key] !== "") return d[key];
  return item.payload?.[key];
}

// ---------------------------------------------------------------------------
// 推送
// ---------------------------------------------------------------------------

export interface PushContent {
  title: string;
  body: string;
  /** FCM data：值全部是字串。App 按 type / order_id 打开页面 */
  data: Record<string, string>;
  ttlSeconds: number;
  /** Android 同一个 tag 的通知会取代旧的（同一张订单的状态更新只留最新一条） */
  tag: string | null;
}

function tpl(s: string, vars: Record<string, string | number>): string {
  return s.replace(/\{(\w+)\}/g, (_, k: string) => (k in vars ? String(vars[k]) : `{${k}}`));
}

const PUSH = {
  order_new: {
    title: { zh: "新订单 {order_no}", en: "New order {order_no}", ms: "Pesanan baharu {order_no}" },
    body: {
      zh: "{shop_name}，{total}，{date}送货。{items}",
      en: "{shop_name} · {total} · delivery {date}. {items}",
      ms: "{shop_name} · {total} · hantar {date}. {items}",
    },
  },
  order_cancelled: {
    title: { zh: "订单已取消 {order_no}", en: "Order cancelled {order_no}", ms: "Pesanan dibatalkan {order_no}" },
    body: {
      zh: "{shop_name} 的订单已取消，不用送货。原因：{reason}",
      en: "{shop_name}'s order has been cancelled. No delivery needed. Reason: {reason}",
      ms: "Pesanan {shop_name} telah dibatalkan. Tidak perlu dihantar. Sebab: {reason}",
    },
  },
  status: {
    confirmed: {
      title: { zh: "订单已确认", en: "Order confirmed", ms: "Pesanan disahkan" },
      body: {
        zh: "{wholesaler_name} 确认了订单 {order_no}，共 {total}。",
        en: "{wholesaler_name} confirmed order {order_no}. Total {total}.",
        ms: "{wholesaler_name} telah mengesahkan pesanan {order_no}. Jumlah {total}.",
      },
    },
    out_of_stock: {
      title: { zh: "订单缺货", en: "Order out of stock", ms: "Pesanan stok habis" },
      body: {
        zh: "{wholesaler_name} 说订单 {order_no} 的货缺了，这张单不会送。",
        en: "{wholesaler_name} is out of stock for order {order_no}. It will not be delivered.",
        ms: "{wholesaler_name} kehabisan stok untuk pesanan {order_no}. Pesanan ini tidak akan dihantar.",
      },
    },
    delivering: {
      title: { zh: "正在送货", en: "Out for delivery", ms: "Sedang dihantar" },
      body: {
        zh: "{wholesaler_name} 正在送订单 {order_no}。",
        en: "{wholesaler_name} is delivering order {order_no}.",
        ms: "{wholesaler_name} sedang menghantar pesanan {order_no}.",
      },
    },
    delivered: {
      title: { zh: "已送达", en: "Delivered", ms: "Telah dihantar" },
      body: {
        zh: "订单 {order_no} 已送达。记得给批发商评分。",
        en: "Order {order_no} has been delivered. Remember to rate the wholesaler.",
        ms: "Pesanan {order_no} telah dihantar. Jangan lupa beri penilaian kepada pemborong.",
      },
    },
    other: {
      title: { zh: "订单有更新", en: "Order update", ms: "Kemas kini pesanan" },
      body: {
        zh: "订单 {order_no}：{status_text}",
        en: "Order {order_no}: {status_text}",
        ms: "Pesanan {order_no}: {status_text}",
      },
    },
  },
  oos_suffix: {
    zh: "{n} 样缺货，不算钱。",
    en: "{n} item(s) out of stock, not charged.",
    ms: "{n} barang habis stok, tidak dicaj.",
  },
  daily_summary: {
    title: {
      zh: "今天要送 {count} 张单",
      en: "{count} order(s) to deliver today",
      ms: "{count} pesanan untuk dihantar hari ini",
    },
    title_pending_only: {
      zh: "今天还有 {pending} 张单没确认",
      en: "{pending} order(s) for today not confirmed yet",
      ms: "{pending} pesanan hari ini belum disahkan",
    },
    body: { zh: "共 {total}。", en: "Total {total}.", ms: "Jumlah {total}." },
    pending: {
      zh: "还有 {pending} 张没确认。",
      en: "{pending} still waiting for confirmation.",
      ms: "{pending} masih menunggu pengesahan.",
    },
    tap: { zh: "点这里看送货单。", en: "Tap to see the delivery list.", ms: "Tekan untuk lihat senarai penghantaran." },
  },
  order_unconfirmed: {
    title: {
      zh: "订单 {order_no} 等了 {minutes} 分钟还没确认",
      en: "Order {order_no} unconfirmed for {minutes} min",
      ms: "Pesanan {order_no} belum disahkan selama {minutes} minit",
    },
    body: {
      zh: "{wholesaler_name}（{phone}）还没确认 {shop_name} 的订单，请打电话提醒。",
      en: "{wholesaler_name} ({phone}) has not confirmed {shop_name}'s order yet. Please give them a call.",
      ms: "{wholesaler_name} ({phone}) belum mengesahkan pesanan {shop_name}. Sila hubungi mereka.",
    },
  },
  generic: {
    title: { zh: "新通知", en: "New notification", ms: "Pemberitahuan baharu" },
    body: {
      zh: "请打开 App 查看。",
      en: "Open the app to see the details.",
      ms: "Buka aplikasi untuk melihat butiran.",
    },
  },
};

const FALLBACK = {
  reason: { zh: "没有说明", en: "Not stated", ms: "Tiada sebab diberi" },
  date: { zh: "待定", en: "to be confirmed", ms: "belum ditetapkan" },
  address: { zh: "（没有填写）", en: "(not provided)", ms: "(tiada)" },
  unknown: { zh: "-", en: "-", ms: "-" },
} satisfies Record<string, Tri>;

const PUSH_TITLE_MAX = 80;
const PUSH_BODY_MAX = 300;

export function pushContent(item: NotificationItem): PushContent {
  const loc = toLocale(item.locale);
  const orderId = str(pick(item, "order_id"));
  const orderNo = str(pick(item, "order_no")) ?? "";
  const data: Record<string, string> = { type: item.event_type, notification_id: item.id };
  if (orderId) data.order_id = orderId;
  if (orderNo) data.order_no = orderNo;
  let title: string;
  let body: string;
  let ttl = 86400;
  let tag: string | null = orderId ? `order-${orderId}` : null;

  switch (item.event_type) {
    case "order_new": {
      const vars = {
        order_no: orderNo,
        shop_name: str(pick(item, "shop_name")) ?? "",
        total: formatMoney(pick(item, "total_sen")),
        date: formatDate(pick(item, "expected_delivery_date"), loc) ?? FALLBACK.date[loc],
        items: str(item.details?.items_text) ?? "",
      };
      title = tpl(PUSH.order_new.title[loc], vars);
      body = tpl(PUSH.order_new.body[loc], vars);
      break;
    }
    case "order_cancelled": {
      const vars = {
        order_no: orderNo,
        shop_name: str(pick(item, "shop_name")) ?? "",
        reason: str(item.payload?.reason) ?? FALLBACK.reason[loc],
      };
      title = tpl(PUSH.order_cancelled.title[loc], vars);
      body = tpl(PUSH.order_cancelled.body[loc], vars);
      break;
    }
    case "order_status_changed": {
      // payload.status 是这次通知说的状态（details.status 可能已经又变了）
      const status = str(item.payload?.status) ?? str(item.details?.status) ?? "";
      const key = (status in PUSH.status ? status : "other") as keyof typeof PUSH.status;
      const vars = {
        order_no: orderNo,
        wholesaler_name: str(pick(item, "wholesaler_name")) ?? "",
        total: formatMoney(pick(item, "total_sen")),
        status_text: statusLabel(status, loc),
      };
      title = tpl(PUSH.status[key].title[loc], vars);
      body = tpl(PUSH.status[key].body[loc], vars);
      const oos = int(pick(item, "out_of_stock_count")) ?? 0;
      if (status === "confirmed" && oos > 0) body += (loc === "zh" ? "" : " ") + tpl(PUSH.oos_suffix[loc], { n: oos });
      break;
    }
    case "daily_summary": {
      const count = int(item.payload?.order_count) ?? 0;
      const pending = int(item.payload?.pending_count) ?? 0;
      const vars = { count, pending, total: formatMoney(item.payload?.total_sen) };
      title = count === 0 && pending > 0
        ? tpl(PUSH.daily_summary.title_pending_only[loc], vars)
        : tpl(PUSH.daily_summary.title[loc], vars);
      const sep = loc === "zh" ? "" : " ";
      const parts = [count > 0 ? tpl(PUSH.daily_summary.body[loc], vars) : null];
      if (pending > 0) parts.push(tpl(PUSH.daily_summary.pending[loc], vars));
      parts.push(PUSH.daily_summary.tap[loc]);
      body = parts.filter(Boolean).join(sep);
      const date = str(item.payload?.date);
      if (date) data.date = date;
      ttl = 12 * 3600;
      tag = "daily-summary";
      break;
    }
    case "order_unconfirmed": {
      const vars = {
        order_no: orderNo,
        minutes: int(item.payload?.pending_minutes) ?? 0,
        wholesaler_name: str(item.payload?.wholesaler_name) ?? "",
        phone: str(item.payload?.wholesaler_phone) ?? "-",
        shop_name: str(pick(item, "shop_name")) ?? "",
      };
      title = tpl(PUSH.order_unconfirmed.title[loc], vars);
      body = tpl(PUSH.order_unconfirmed.body[loc], vars);
      const wid = str(item.payload?.wholesaler_id);
      if (wid) data.wholesaler_id = wid;
      ttl = 3600;
      break;
    }
    default: {
      title = PUSH.generic.title[loc];
      body = str(item.payload?.message) ?? PUSH.generic.body[loc];
    }
  }
  return {
    title: truncate(oneLine(title), PUSH_TITLE_MAX),
    body: truncate(oneLine(body), PUSH_BODY_MAX),
    data,
    ttlSeconds: ttl,
    tag,
  };
}

// ---------------------------------------------------------------------------
// WhatsApp 模板（送审的内文；docs/04-whatsapp-templates.md 必须一字不差）
// ---------------------------------------------------------------------------

export const WHATSAPP_LANGUAGE: Record<Locale, string> = { zh: "zh_CN", en: "en", ms: "ms" };

export interface TemplateDefinition {
  name: string;
  /** 变量顺序（具名参数；送审时每个都要给例子） */
  params: readonly string[];
  examples: Record<string, Tri>;
  body: Tri;
  /** quick reply 按钮（index 0, 1, ...），每个 ≤ 25 字 */
  buttons: readonly Tri[];
  /** 每个参数的长度上限（模板内文连变量最多 1024 字） */
  maxLen: Record<string, number>;
}

export const WHATSAPP_TEMPLATES = {
  order_new_v1: {
    name: "order_new_v1",
    params: ["order_no", "shop_name", "items", "total", "delivery_date", "address"],
    examples: {
      order_no: { zh: "JHB261126-00012", en: "JHB261126-00012", ms: "JHB261126-00012" },
      shop_name: { zh: "阿成茶室", en: "Kedai Kopi Ah Seng", ms: "Kedai Kopi Ah Seng" },
      items: {
        zh: "16安士 PP杯 95口径 x2 箱; 95 平盖 x1 箱",
        en: "16oz PP cup 95mm x2 carton; 95mm flat lid x1 carton",
        ms: "Cawan PP 16oz 95mm x2 karton; Penutup rata 95mm x1 karton",
      },
      total: { zh: "RM178.00", en: "RM178.00", ms: "RM178.00" },
      delivery_date: { zh: "2026年11月26日（星期四）", en: "Thu, 26 Nov 2026", ms: "Khamis, 26 Nov 2026" },
      address: {
        zh: "12, Jalan Kuning 2, Taman Pelangi, 80400 Johor Bahru",
        en: "12, Jalan Kuning 2, Taman Pelangi, 80400 Johor Bahru",
        ms: "12, Jalan Kuning 2, Taman Pelangi, 80400 Johor Bahru",
      },
    },
    body: {
      zh:
        "您有一张新订单 {{order_no}}。\n店铺：{{shop_name}}\n货品：{{items}}\n总额：{{total}}\n送货日期：{{delivery_date}}\n地址：{{address}}\n请按下面的按钮确认订单，或告诉我们缺货。",
      en:
        "You have a new order {{order_no}}.\nShop: {{shop_name}}\nItems: {{items}}\nTotal: {{total}}\nDelivery date: {{delivery_date}}\nAddress: {{address}}\nPlease tap a button below to confirm the order or tell us it is out of stock.",
      ms:
        "Anda menerima pesanan baharu {{order_no}}.\nKedai: {{shop_name}}\nBarangan: {{items}}\nJumlah: {{total}}\nTarikh hantar: {{delivery_date}}\nAlamat: {{address}}\nSila tekan butang di bawah untuk mengesahkan pesanan atau memaklumkan stok habis.",
    },
    buttons: [
      { zh: "确认订单", en: "Confirm order", ms: "Sahkan pesanan" },
      { zh: "缺货", en: "Out of stock", ms: "Stok habis" },
    ],
    maxLen: { order_no: 40, shop_name: 80, items: 600, total: 20, delivery_date: 40, address: 160 },
  },
  order_status_v1: {
    name: "order_status_v1",
    params: ["order_no", "wholesaler_name", "status_text", "total"],
    examples: {
      order_no: { zh: "JHB261126-00012", en: "JHB261126-00012", ms: "JHB261126-00012" },
      wholesaler_name: { zh: "新山包装批发", en: "JB Packaging Supply", ms: "JB Packaging Supply" },
      status_text: {
        zh: "已确认（1 样缺货，不算钱）",
        en: "Confirmed (1 item out of stock, not charged)",
        ms: "Disahkan (1 barang habis stok, tidak dicaj)",
      },
      total: { zh: "RM178.00", en: "RM178.00", ms: "RM178.00" },
    },
    body: {
      zh:
        "您的订单 {{order_no}} 有更新。\n批发商：{{wholesaler_name}}\n状态：{{status_text}}\n总额：{{total}}\n如有问题，请直接回复这条消息。",
      en:
        "Your order {{order_no}} has been updated.\nWholesaler: {{wholesaler_name}}\nStatus: {{status_text}}\nTotal: {{total}}\nIf you have any questions, just reply to this message.",
      ms:
        "Pesanan anda {{order_no}} telah dikemas kini.\nPemborong: {{wholesaler_name}}\nStatus: {{status_text}}\nJumlah: {{total}}\nJika ada sebarang pertanyaan, balas sahaja mesej ini.",
    },
    buttons: [],
    maxLen: { order_no: 40, wholesaler_name: 80, status_text: 120, total: 20 },
  },
  order_cancelled_v1: {
    name: "order_cancelled_v1",
    params: ["order_no", "shop_name", "reason"],
    examples: {
      order_no: { zh: "JHB261126-00012", en: "JHB261126-00012", ms: "JHB261126-00012" },
      shop_name: { zh: "阿成茶室", en: "Kedai Kopi Ah Seng", ms: "Kedai Kopi Ah Seng" },
      reason: { zh: "下错单了", en: "Ordered by mistake", ms: "Tersalah pesan" },
    },
    body: {
      zh: "订单 {{order_no}} 已取消。\n店铺：{{shop_name}}\n原因：{{reason}}\n这张订单不用再送货，谢谢。",
      en:
        "Order {{order_no}} has been cancelled.\nShop: {{shop_name}}\nReason: {{reason}}\nThis order no longer needs to be delivered. Thank you.",
      ms:
        "Pesanan {{order_no}} telah dibatalkan.\nKedai: {{shop_name}}\nSebab: {{reason}}\nPesanan ini tidak perlu dihantar lagi. Terima kasih.",
    },
    buttons: [],
    maxLen: { order_no: 40, shop_name: 80, reason: 200 },
  },
} as const satisfies Record<string, TemplateDefinition>;

export type TemplateName = keyof typeof WHATSAPP_TEMPLATES;

export interface TemplateMessage {
  name: TemplateName;
  languageCode: string;
  /** 具名参数（值已经整理过：一行、不空、不太长） */
  params: Record<string, string>;
  /** quick reply 按钮的 payload（index 跟模板一样：0 = 确认，1 = 缺货） */
  buttons: { index: number; payload: string }[];
}

export const WHATSAPP_BODY_MAX = 1024;

/** 模板内文（变量换成值）的长度，用来检查 ≤ 1024 */
export function renderTemplate(name: TemplateName, locale: Locale, params: Record<string, string>): string {
  return WHATSAPP_TEMPLATES[name].body[locale].replace(/\{\{(\w+)\}\}/g, (_, k: string) => params[k] ?? "");
}

function param(v: unknown, max: number, fallback: string): string {
  const s = oneLine(v);
  return s === "" ? fallback : truncate(s, max);
}

function statusText(status: string, oosCount: number, loc: Locale): string {
  if (status === "confirmed" && oosCount > 0) {
    return {
      zh: `已确认（${oosCount} 样缺货，不算钱）`,
      en: `Confirmed (${oosCount} item(s) out of stock, not charged)`,
      ms: `Disahkan (${oosCount} barang habis stok, tidak dicaj)`,
    }[loc];
  }
  if (status === "out_of_stock") {
    return {
      zh: "缺货，这张订单不会送",
      en: "Out of stock, this order will not be delivered",
      ms: "Stok habis, pesanan ini tidak akan dihantar",
    }[loc];
  }
  return statusLabel(status, loc);
}

/** 每种事件用哪个 WhatsApp 模板；没有模板的事件回传 null（dispatcher 标 skipped）。 */
export function whatsappTemplate(item: NotificationItem): TemplateMessage | null {
  const loc = toLocale(item.locale);
  const orderNo = pick(item, "order_no");
  const dash = FALLBACK.unknown[loc];
  let name: TemplateName;
  let raw: Record<string, string>;
  let buttons: { index: number; payload: string }[] = [];

  switch (item.event_type) {
    case "order_new": {
      name = "order_new_v1";
      const max = WHATSAPP_TEMPLATES[name].maxLen;
      raw = {
        order_no: param(orderNo, max.order_no, dash),
        shop_name: param(pick(item, "shop_name"), max.shop_name, dash),
        items: truncateList(param(item.details?.items_text, 100000, dash), max.items),
        total: formatMoney(pick(item, "total_sen")),
        delivery_date: formatDate(pick(item, "expected_delivery_date"), loc) ?? FALLBACK.date[loc],
        address: param(item.details?.shop_address, max.address, FALLBACK.address[loc]),
      };
      const orderId = str(pick(item, "order_id"));
      if (!orderId) return null; // 没有订单 id 就没办法放按钮
      buttons = [{ index: 0, payload: `CONFIRM:${orderId}` }, { index: 1, payload: `OOS:${orderId}` }];
      break;
    }
    case "order_status_changed": {
      name = "order_status_v1";
      const max = WHATSAPP_TEMPLATES[name].maxLen;
      const status = str(item.payload?.status) ?? str(item.details?.status) ?? "";
      raw = {
        order_no: param(orderNo, max.order_no, dash),
        wholesaler_name: param(pick(item, "wholesaler_name"), max.wholesaler_name, dash),
        status_text: param(statusText(status, int(pick(item, "out_of_stock_count")) ?? 0, loc), max.status_text, dash),
        total: formatMoney(pick(item, "total_sen")),
      };
      break;
    }
    case "order_cancelled": {
      name = "order_cancelled_v1";
      const max = WHATSAPP_TEMPLATES[name].maxLen;
      raw = {
        order_no: param(orderNo, max.order_no, dash),
        shop_name: param(pick(item, "shop_name"), max.shop_name, dash),
        reason: param(item.payload?.reason, max.reason, FALLBACK.reason[loc]),
      };
      break;
    }
    default:
      return null;
  }

  // 整段内文最多 1024 字：太长就再缩短货品清单
  const over = [...renderTemplate(name, loc, raw)].length - WHATSAPP_BODY_MAX;
  if (over > 0 && raw.items) raw.items = truncateList(raw.items, Math.max(20, [...raw.items].length - over));

  return { name, languageCode: WHATSAPP_LANGUAGE[loc], params: raw, buttons };
}

// ---------------------------------------------------------------------------
// 按钮按下之后回的普通文字（客户刚发消息，24 小时内可以回普通文字，每月前 1,000 条免费）
// ---------------------------------------------------------------------------

const REPLY = {
  confirmed: {
    zh: "✅ 已确认订单 {order_no}。谢谢！请按时送货。",
    en: "✅ Order {order_no} confirmed. Thank you! Please deliver on time.",
    ms: "✅ Pesanan {order_no} telah disahkan. Terima kasih! Sila hantar mengikut jadual.",
  },
  out_of_stock: {
    zh: "已记录订单 {order_no} 缺货，我们会通知买家。谢谢！",
    en: "Noted: order {order_no} is out of stock. We will let the buyer know. Thank you!",
    ms: "Baik, pesanan {order_no} ditanda stok habis. Kami akan maklumkan kepada pembeli. Terima kasih!",
  },
  already_confirmed: {
    zh: "订单 {order_no} 之前已经确认了，不用再按。",
    en: "Order {order_no} was already confirmed. No need to tap again.",
    ms: "Pesanan {order_no} sudah disahkan sebelum ini. Tidak perlu tekan lagi.",
  },
  already_out_of_stock: {
    zh: "订单 {order_no} 之前已经标记缺货了。",
    en: "Order {order_no} was already marked as out of stock.",
    ms: "Pesanan {order_no} sudah ditanda stok habis sebelum ini.",
  },
  already_cancelled: {
    zh: "订单 {order_no} 已经取消了，不用送货。",
    en: "Order {order_no} has already been cancelled. No delivery needed.",
    ms: "Pesanan {order_no} sudah dibatalkan. Tidak perlu dihantar.",
  },
  already_other: {
    zh: "订单 {order_no} 现在是「{status}」，这次没有改动。",
    en: 'Order {order_no} is already "{status}". Nothing was changed.',
    ms: 'Pesanan {order_no} kini berstatus "{status}". Tiada perubahan dibuat.',
  },
  not_authorized: {
    zh: "这个号码不能处理这张订单。如果有问题，请联系客服。",
    en: "This number is not allowed to update this order. Please contact our support team if this is a mistake.",
    ms:
      "Nombor ini tidak dibenarkan mengemas kini pesanan ini. Sila hubungi khidmat pelanggan jika ini satu kesilapan.",
  },
  not_found: {
    zh: "找不到这张订单。请打开 App 查看，或联系客服。",
    en: "We could not find this order. Please check in the app or contact our support team.",
    ms: "Pesanan ini tidak dijumpai. Sila semak dalam aplikasi atau hubungi khidmat pelanggan.",
  },
} satisfies Record<string, Tri>;

/**
 * handle_whatsapp_button 的 result → 回给按按钮的人的一句话。
 * duplicate（Meta 重送）和看不懂的结果 → null（不回）。
 */
export function buttonReplyText(result: string, orderNo: string | null, locale: Locale): string | null {
  const vars = { order_no: orderNo ?? "", status: "" };
  let t: Tri | null = null;
  if (result === "confirmed") t = REPLY.confirmed;
  else if (result === "out_of_stock") t = REPLY.out_of_stock;
  else if (result === "already_confirmed") t = REPLY.already_confirmed;
  else if (result === "already_out_of_stock") t = REPLY.already_out_of_stock;
  else if (result === "already_cancelled") t = REPLY.already_cancelled;
  else if (result.startsWith("already_")) {
    t = REPLY.already_other;
    vars.status = statusLabel(result.slice("already_".length), locale);
  } else if (result === "not_authorized") t = REPLY.not_authorized;
  else if (result === "order_not_found" || result === "invalid_payload") t = REPLY.not_found;
  if (!t) return null;
  return tpl(t[locale], vars).replace(/\s{2,}/g, " ");
}
