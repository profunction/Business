// 环境变量（每次调用时才读，测试可以随时改）。
// 平台自动给：SUPABASE_URL、SUPABASE_SECRET_KEYS、SUPABASE_PUBLISHABLE_KEYS（JSON，取 "default"），
// 旧项目退回 SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY。
// 自己设（名字不能以 SUPABASE_ 开头）：FCM_SERVICE_ACCOUNT_JSON、WHATSAPP_TOKEN、WHATSAPP_PHONE_NUMBER_ID、
// WHATSAPP_APP_SECRET、WHATSAPP_VERIFY_TOKEN、WHATSAPP_GRAPH_VERSION（默认 v27.0）、ANTHROPIC_API_KEY、
// ELEVENLABS_API_KEY（语音转文字）、STT_MODEL（默认 scribe_v2）、
// HITPAY_API_KEY + HITPAY_SALT（付款网关）、HITPAY_ENV（sandbox 默认 / production）、PAYMENT_RETURN_URL（付完回到哪里，https）。
// 可以选设的服务没设定时回传 null（调用的地方跳过并在日志说明）。

export class ConfigError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "ConfigError";
  }
}

function get(name: string): string | null {
  const v = Deno.env.get(name);
  return v != null && v.trim() !== "" ? v.trim() : null;
}

/** SUPABASE_SECRET_KEYS / SUPABASE_PUBLISHABLE_KEYS 是 JSON（{"default": "sb_..."}）；也接受直接是钥匙的字串。 */
export function readKeyMap(name: string): string | null {
  const raw = get(name);
  if (!raw) return null;
  if (raw.startsWith("{")) {
    try {
      const parsed = JSON.parse(raw) as unknown;
      if (parsed && typeof parsed === "object") {
        const v = (parsed as Record<string, unknown>)["default"];
        return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
      }
    } catch {
      return null;
    }
    return null;
  }
  return raw.startsWith("sb_") ? raw : null;
}

export interface SupabaseEnv {
  url: string;
  /** 新的 sb_secret_ 钥匙；旧项目是 service_role JWT */
  secretKey: string;
  /** 新的 sb_publishable_ 钥匙；旧项目是 anon JWT（只有 parse-price-list 要用） */
  publishableKey: string | null;
}

export function supabaseEnv(): SupabaseEnv {
  const url = get("SUPABASE_URL");
  const secretKey = readKeyMap("SUPABASE_SECRET_KEYS") ?? get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secretKey) throw new ConfigError("SUPABASE_ENV_MISSING");
  const publishableKey = readKeyMap("SUPABASE_PUBLISHABLE_KEYS") ?? get("SUPABASE_ANON_KEY");
  return { url: url.replace(/\/+$/, ""), secretKey, publishableKey };
}

/**
 * dispatch-notifications 接受的钥匙：默认 secret key；项目同时还有旧的 service_role key 时也接受
 * （两个权限一样大；Vault 的 secret_key 照规格应该放新的 secret key）。
 */
export function serviceKeys(): string[] {
  const keys = [readKeyMap("SUPABASE_SECRET_KEYS"), get("SUPABASE_SERVICE_ROLE_KEY")];
  return [...new Set(keys.filter((k): k is string => !!k))];
}

export interface FcmServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri: string;
}

/** FCM_SERVICE_ACCOUNT_JSON = Firebase 主控台下载的服务账号 JSON 整份。没设或格式不对 → null。 */
export function fcmServiceAccount(): FcmServiceAccount | null {
  const raw = get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) return null;
  try {
    const sa = JSON.parse(raw) as Record<string, unknown>;
    const email = sa.client_email, key = sa.private_key, project = sa.project_id;
    if (typeof email !== "string" || typeof key !== "string" || typeof project !== "string") return null;
    const tokenUri = typeof sa.token_uri === "string" && sa.token_uri.startsWith("https://")
      ? sa.token_uri
      : "https://oauth2.googleapis.com/token";
    return { client_email: email, private_key: key, project_id: project, token_uri: tokenUri };
  } catch {
    return null;
  }
}

export const DEFAULT_GRAPH_VERSION = "v27.0";

export interface WhatsAppConfig {
  token: string;
  phoneNumberId: string;
  graphVersion: string;
}

/** 发 WhatsApp 要的设定（token + phone number id）。没设 → null。 */
export function whatsappConfig(): WhatsAppConfig | null {
  const token = get("WHATSAPP_TOKEN");
  const phoneNumberId = get("WHATSAPP_PHONE_NUMBER_ID");
  if (!token || !phoneNumberId) return null;
  let graphVersion = get("WHATSAPP_GRAPH_VERSION") ?? DEFAULT_GRAPH_VERSION;
  if (!/^v\d+\.\d+$/.test(graphVersion)) graphVersion = DEFAULT_GRAPH_VERSION;
  return { token, phoneNumberId, graphVersion };
}

export function whatsappAppSecret(): string | null {
  return get("WHATSAPP_APP_SECRET");
}

export function whatsappVerifyToken(): string | null {
  return get("WHATSAPP_VERIFY_TOKEN");
}

export function anthropicApiKey(): string | null {
  return get("ANTHROPIC_API_KEY");
}

/** 语音转文字（ElevenLabs Scribe）。没设钥匙 → null */
export function sttConfig(): { apiKey: string; model: string } | null {
  const apiKey = get("ELEVENLABS_API_KEY");
  if (!apiKey) return null;
  const model = get("STT_MODEL") ?? "scribe_v2";
  return { apiKey, model: /^[a-z0-9_]{1,40}$/.test(model) ? model : "scribe_v2" };
}

/** 整数环境变量（测试或付费方案调整时间预算用）；没设或不合理就用默认值。 */
export function intEnv(name: string, fallback: number, min: number, max: number): number {
  const raw = get(name);
  const n = raw == null ? NaN : Number(raw);
  return Number.isInteger(n) && n >= min && n <= max ? n : fallback;
}

export interface PaymentGatewayConfig {
  gateway: "hitpay";
  apiKey: string;
  /** webhook 签名用的 salt（Dashboard → Developers → Webhook endpoints） */
  salt: string | null;
  baseUrl: string;
  /** 付完浏览器回到哪里（App 的网页 / deep link 的 https 网址）；没设 → 网关自己的「付款成功」页 */
  returnUrl: string | null;
}

export const HITPAY_URLS = {
  sandbox: "https://api.sandbox.hit-pay.com/v1",
  production: "https://api.hit-pay.com/v1",
} as const;

/** 付款网关（HitPay）。没设 HITPAY_API_KEY → null（create-payment 回 503 PAYMENT_NOT_CONFIGURED）。默认用 sandbox。 */
export function paymentConfig(): PaymentGatewayConfig | null {
  const apiKey = get("HITPAY_API_KEY");
  if (!apiKey) return null;
  const env = get("HITPAY_ENV") === "production" ? "production" : "sandbox";
  const ret = get("PAYMENT_RETURN_URL");
  return {
    gateway: "hitpay",
    apiKey,
    salt: get("HITPAY_SALT"),
    baseUrl: HITPAY_URLS[env],
    returnUrl: ret && /^https:\/\/[^\s]+$/.test(ret) ? ret : null,
  };
}

/** webhook 只要 salt 就能验签名（开单要 API key） */
export function paymentWebhookSalt(): string | null {
  return get("HITPAY_SALT");
}
