import { HttpError } from "./http.ts";

export interface CheckoutItem {
  id: string;
  price: number;
  quantity: number;
  name: string;
}

export interface SnapCheckoutInput {
  providerOrderId: string;
  grossAmount: number;
  requestedMethod: string;
  paymentExpiresAt: string;
  customer: {
    first_name?: string | null;
    email?: string | null;
    phone?: string | null;
  };
  items: CheckoutItem[];
}

export interface SnapTransaction {
  token: string;
  redirect_url: string;
}

export interface MidtransStatus {
  order_id: string;
  transaction_status: string;
  fraud_status: string | null;
  status_code: string;
  gross_amount: string;
  transaction_id: string | null;
  payment_type: string | null;
  status_timestamp: string | null;
}

export class MidtransApiError extends Error {
  constructor(
    public readonly httpStatus: number,
    public readonly operation: "create" | "status",
  ) {
    super(`Midtrans ${operation} request failed with HTTP ${httpStatus}`);
    this.name = "MidtransApiError";
  }

  get isNotFound(): boolean {
    return this.operation === "status" && this.httpStatus === 404;
  }

  get safeCode(): string {
    return `midtrans_${this.operation}_http_${this.httpStatus}`;
  }
}

interface MidtransConfig {
  serverKey: string;
  snapBaseUrl: string;
  apiBaseUrl: string;
  notificationUrl: string;
}

function requiredServerKey(): string {
  const key = Deno.env.get("MIDTRANS_SERVER_KEY")?.trim();
  if (!key) {
    throw new HttpError(
      500,
      "midtrans_not_configured",
      "Credential Midtrans belum dikonfigurasi di server.",
    );
  }
  return key;
}

function isProduction(): boolean {
  const environment = Deno.env.get("MIDTRANS_ENVIRONMENT")?.trim()
    .toLowerCase();
  const flag = Deno.env.get("MIDTRANS_IS_PRODUCTION")?.trim().toLowerCase();

  if (environment) {
    if (["production", "prod", "live"].includes(environment)) return true;
    if (["sandbox", "staging", "test"].includes(environment)) return false;
    throw new HttpError(
      500,
      "midtrans_not_configured",
      "Konfigurasi lingkungan Midtrans tidak valid.",
    );
  }
  if (!flag || ["false", "0", "no"].includes(flag)) return false;
  if (["true", "1", "yes"].includes(flag)) return true;
  throw new HttpError(
    500,
    "midtrans_not_configured",
    "Konfigurasi lingkungan Midtrans tidak valid.",
  );
}

function supabaseFunctionUrl(slug: string): string {
  const raw = Deno.env.get("SUPABASE_URL")?.trim();
  if (!raw) {
    throw new HttpError(
      500,
      "server_not_configured",
      "Konfigurasi server pembayaran belum lengkap.",
    );
  }
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new HttpError(
      500,
      "server_not_configured",
      "Konfigurasi server pembayaran tidak valid.",
    );
  }
  const isLocal = ["localhost", "127.0.0.1"].includes(url.hostname);
  if (url.protocol !== "https:" && !isLocal) {
    throw new HttpError(
      500,
      "server_not_configured",
      "Endpoint notifikasi pembayaran wajib HTTPS.",
    );
  }
  url.pathname = `/functions/v1/${slug}`;
  url.search = "";
  url.hash = "";
  return url.toString();
}

function overrideNotificationUrl(): string {
  return supabaseFunctionUrl("midtrans-webhook");
}

function finishCallbackUrl(): string {
  return supabaseFunctionUrl("midtrans-return");
}

function config(): MidtransConfig {
  const production = isProduction();
  return {
    serverKey: requiredServerKey(),
    snapBaseUrl: production
      ? "https://app.midtrans.com"
      : "https://app.sandbox.midtrans.com",
    apiBaseUrl: production
      ? "https://api.midtrans.com"
      : "https://api.sandbox.midtrans.com",
    notificationUrl: overrideNotificationUrl(),
  };
}

export function assertMidtransConfigured(): void {
  // Validate every operator-controlled value before checkout reserves stock.
  // The returned configuration is intentionally discarded and never logged.
  config();
  paymentCallbackUrl();
  finishCallbackUrl();
}

function basicAuthorization(serverKey: string): string {
  return `Basic ${btoa(`${serverKey}:`)}`;
}

function paymentCallbackUrl(): string {
  const configured = Deno.env.get("MIDTRANS_CALLBACK_URL")?.trim() ??
    "com.savebite://payment-callback/";
  let parsed: URL;
  try {
    parsed = new URL(configured);
  } catch {
    throw new HttpError(
      500,
      "midtrans_not_configured",
      "Callback aplikasi pembayaran tidak valid.",
    );
  }
  const isSaveBiteDeepLink = parsed.protocol === "com.savebite:" &&
    parsed.hostname === "payment-callback";
  if (parsed.protocol !== "https:" && !isSaveBiteDeepLink) {
    throw new HttpError(
      500,
      "midtrans_not_configured",
      "Callback aplikasi pembayaran tidak valid.",
    );
  }
  return parsed.toString();
}

export function recognizedEnabledPayments(
  method: string,
): string[] | undefined {
  const normalized = method.trim().toLowerCase().replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ");
  const mapping: Record<string, string[]> = {
    "gopay": ["gopay"],
    "shopeepay": ["shopeepay"],
    "shopee pay": ["shopeepay"],
    "credit card": ["credit_card"],
    "kartu kredit": ["credit_card"],
    "virtual account bca": ["bca_va"],
    "bca virtual account": ["bca_va"],
  };
  return mapping[normalized];
}

function integer(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new HttpError(
      500,
      "invalid_checkout",
      `${field} checkout tidak valid.`,
    );
  }
  return value;
}

export function buildSnapPayload(
  input: SnapCheckoutInput,
  now = new Date(),
): Record<string, unknown> {
  if (
    !/^SB-[A-F0-9]{32}$/.test(input.providerOrderId) ||
    input.providerOrderId.length > 50
  ) {
    throw new HttpError(500, "invalid_checkout", "ID checkout tidak valid.");
  }
  const grossAmount = integer(input.grossAmount, "Total");
  if (!Array.isArray(input.items) || input.items.length === 0) {
    throw new HttpError(500, "invalid_checkout", "Item checkout tidak valid.");
  }

  const itemDetails = input.items.map((item) => ({
    id: item.id.slice(0, 50),
    price: integer(item.price, "Harga item"),
    quantity: integer(item.quantity, "Jumlah item"),
    name: item.name.trim().slice(0, 50) || "Item SaveBite",
  }));
  const itemTotal = itemDetails.reduce(
    (sum, item) => sum + item.price * item.quantity,
    0,
  );
  if (!Number.isSafeInteger(itemTotal) || itemTotal !== grossAmount) {
    throw new HttpError(
      500,
      "checkout_total_mismatch",
      "Rincian dan total checkout tidak cocok.",
    );
  }

  const expiresAt = Date.parse(input.paymentExpiresAt);
  if (!Number.isFinite(expiresAt) || expiresAt <= now.getTime()) {
    throw new HttpError(
      409,
      "payment_expired",
      "Waktu pembayaran sudah habis.",
    );
  }
  const duration = Math.max(
    1,
    Math.min(15, Math.ceil((expiresAt - now.getTime()) / 60_000)),
  );
  const callbackUrl = paymentCallbackUrl();
  const enabledPayments = recognizedEnabledPayments(input.requestedMethod);
  const customerDetails = Object.fromEntries(
    Object.entries(input.customer).filter(([, value]) =>
      typeof value === "string" && value.trim().length > 0
    ),
  );

  return {
    transaction_details: {
      order_id: input.providerOrderId,
      gross_amount: grossAmount,
    },
    item_details: itemDetails,
    ...(Object.keys(customerDetails).length > 0
      ? { customer_details: customerDetails }
      : {}),
    ...(enabledPayments ? { enabled_payments: enabledPayments } : {}),
    expiry: { duration, unit: "minutes" },
    // Snap's generic finish callback is documented as an HTTPS URL. This
    // server-hosted bridge safely hands the customer back to the mobile deep
    // link without treating any callback parameter as payment proof.
    callbacks: { finish: finishCallbackUrl() },
    gopay: { enable_callback: true, callback_url: callbackUrl },
    shopeepay: { callback_url: callbackUrl },
    credit_card: { secure: true },
  };
}

async function readProviderJson(
  response: Response,
  operation: "create" | "status",
): Promise<Record<string, unknown>> {
  const text = await response.text();
  if (text.length > 65_536) {
    throw new MidtransApiError(response.status || 502, operation);
  }
  try {
    const parsed = JSON.parse(text);
    if (
      parsed !== null && !Array.isArray(parsed) && typeof parsed === "object"
    ) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    // Converted to a generic provider failure below; the raw body is discarded.
  }
  return {};
}

export async function createSnapTransaction(
  payload: Record<string, unknown>,
): Promise<SnapTransaction> {
  const cfg = config();
  let response: Response;
  try {
    response = await fetch(`${cfg.snapBaseUrl}/snap/v1/transactions`, {
      method: "POST",
      headers: {
        Authorization: basicAuthorization(cfg.serverKey),
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-Override-Notification": cfg.notificationUrl,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(12_000),
    });
  } catch {
    throw new MidtransApiError(503, "create");
  }
  const body = await readProviderJson(response, "create");
  if (!response.ok) throw new MidtransApiError(response.status, "create");

  const token = typeof body.token === "string" ? body.token.trim() : "";
  const redirectUrl = typeof body.redirect_url === "string"
    ? body.redirect_url.trim()
    : "";
  if (!token || !redirectUrl) throw new MidtransApiError(502, "create");
  return { token, redirect_url: redirectUrl };
}

function optionalString(value: unknown, maxLength = 255): string | null {
  if (typeof value !== "string") return null;
  const result = value.trim();
  return result ? result.slice(0, maxLength) : null;
}

export function parseMidtransStatus(
  body: Record<string, unknown>,
  expectedOrderId: string,
): MidtransStatus {
  const orderId = optionalString(body.order_id, 50);
  const transactionStatus = optionalString(body.transaction_status, 64);
  const statusCode = optionalString(body.status_code, 3);
  const grossAmount = optionalString(body.gross_amount, 64);
  if (
    orderId !== expectedOrderId || !transactionStatus ||
    !statusCode || !/^[0-9]{3}$/.test(statusCode) || !grossAmount
  ) {
    throw new MidtransApiError(502, "status");
  }
  const statusTimestamp = optionalString(body.status_timestamp, 64);
  return {
    order_id: orderId,
    transaction_status: transactionStatus,
    fraud_status: optionalString(body.fraud_status, 64),
    status_code: statusCode,
    gross_amount: grossAmount,
    transaction_id: optionalString(body.transaction_id, 255),
    payment_type: optionalString(body.payment_type, 100),
    status_timestamp:
      statusTimestamp && Number.isFinite(Date.parse(statusTimestamp))
        ? statusTimestamp
        : null,
  };
}

export async function getMidtransStatus(
  providerOrderId: string,
): Promise<MidtransStatus> {
  if (!/^SB-[A-F0-9]{32}$/.test(providerOrderId)) {
    throw new HttpError(400, "invalid_order", "ID pembayaran tidak valid.");
  }
  const cfg = config();
  let response: Response;
  try {
    response = await fetch(
      `${cfg.apiBaseUrl}/v2/${encodeURIComponent(providerOrderId)}/status`,
      {
        headers: {
          Authorization: basicAuthorization(cfg.serverKey),
          Accept: "application/json",
        },
        signal: AbortSignal.timeout(9_000),
      },
    );
  } catch {
    throw new MidtransApiError(503, "status");
  }
  const body = await readProviderJson(response, "status");
  if (!response.ok) throw new MidtransApiError(response.status, "status");
  return parseMidtransStatus(body, providerOrderId);
}

export async function sha512Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-512",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function constantTimeEqual(left: string, right: string): boolean {
  const length = Math.max(left.length, right.length);
  let mismatch = left.length ^ right.length;
  for (let index = 0; index < length; index += 1) {
    mismatch |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }
  return mismatch === 0;
}

export async function verifyNotificationSignature(
  orderId: string,
  statusCode: string,
  grossAmount: string,
  suppliedSignature: string,
  serverKey = requiredServerKey(),
): Promise<boolean> {
  const expected = await sha512Hex(
    `${orderId}${statusCode}${grossAmount}${serverKey}`,
  );
  return constantTimeEqual(expected, suppliedSignature.toLowerCase());
}

export function applyStatusParams(status: MidtransStatus) {
  return {
    p_provider_order_id: status.order_id,
    p_transaction_status: status.transaction_status,
    p_fraud_status: status.fraud_status,
    p_status_code: status.status_code,
    p_gross_amount: status.gross_amount,
    p_transaction_id: status.transaction_id,
    p_payment_type: status.payment_type,
    p_provider_event_at: status.status_timestamp,
  };
}
