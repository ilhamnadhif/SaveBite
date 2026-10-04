import { HttpError } from "./http.ts";

export interface CheckoutItem {
  id: string;
  price: number;
  quantity: number;
  name: string;
}

export interface QrisCheckoutInput {
  providerOrderId: string;
  grossAmount: number;
  paymentExpiresAt: string;
  customer: {
    first_name?: string | null;
    email?: string | null;
    phone?: string | null;
  };
  items: CheckoutItem[];
}

export interface QrisTransaction {
  transaction_id: string;
  payment_qr_url: string;
}

/// `QRIS`: Snap restricted to Other QRIS (the in-app WebView checkout).
/// `MIDTRANS`: the hosted Snap page with every payment method active on the
/// merchant account (the web checkout).
export type CheckoutPaymentMethod = "QRIS" | "MIDTRANS";

export interface SnapCheckoutInput extends QrisCheckoutInput {
  /// Defaults to QRIS, the original Snap contract.
  paymentMethod?: CheckoutPaymentMethod;
}

export interface SnapTransaction {
  token: string;
  redirect_url: string;
}

export type QrisAcquirer = "gopay" | "airpay shopee";
export type QrisProviderMode = "qris" | "gopay";

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

type MidtransOperation = "create" | "status" | "cancel" | "refund";

export type MerchantCancellationAction =
  | "cancel"
  | "refund"
  | "complete"
  | "review";

export class MidtransApiError extends Error {
  constructor(
    public readonly httpStatus: number,
    public readonly operation: MidtransOperation,
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

class MidtransProtocolError extends MidtransApiError {
  constructor(
    operation: "create" | "status",
    private readonly reason: string,
  ) {
    super(502, operation);
  }

  override get safeCode(): string {
    return `midtrans_${this.operation}_invalid_${this.reason}`;
  }
}

interface MidtransConfig {
  serverKey: string;
  snapBaseUrl: string;
  apiBaseUrl: string;
  notificationUrl: string;
}

type MidtransEnvironment = "sandbox" | "production";

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

function configuredMidtransEnvironment(): MidtransEnvironment {
  const environment = Deno.env.get("MIDTRANS_ENVIRONMENT")?.trim();
  if (environment !== "sandbox" && environment !== "production") {
    throw new HttpError(
      500,
      "midtrans_not_configured",
      "Konfigurasi lingkungan Midtrans tidak valid.",
    );
  }

  // Transitional compatibility only: the legacy flag never selects an
  // environment. When it is still present it must be a canonical boolean and
  // agree with MIDTRANS_ENVIRONMENT, otherwise the backend fails closed.
  const legacyFlag = Deno.env.get("MIDTRANS_IS_PRODUCTION");
  if (legacyFlag == null) return environment;

  const normalizedLegacyFlag = legacyFlag.trim();
  if (
    (normalizedLegacyFlag !== "true" && normalizedLegacyFlag !== "false") ||
    (normalizedLegacyFlag === "true") !== (environment === "production")
  ) {
    throw new HttpError(
      500,
      "midtrans_not_configured",
      "Konfigurasi lingkungan Midtrans tidak valid.",
    );
  }
  return environment;
}

function isProduction(): boolean {
  return configuredMidtransEnvironment() === "production";
}

function simulatorHelpersEnabled(): boolean {
  return Deno.env.get("MIDTRANS_ENABLE_SIMULATOR_HELPERS")?.trim() === "true";
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

function finishCallbackUrl(target: "app" | "web" = "app"): string {
  const url = supabaseFunctionUrl("midtrans-return");
  return target === "web" ? `${url}?target=web` : url;
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
  finishCallbackUrl();
}

export function configuredQrisAcquirer(): QrisAcquirer {
  const value = Deno.env.get("MIDTRANS_QRIS_ACQUIRER")?.trim().toLowerCase() ??
    "gopay";
  if (value === "gopay" || value === "airpay shopee") return value;
  throw new HttpError(
    500,
    "midtrans_not_configured",
    "Konfigurasi acquirer QRIS Midtrans tidak valid.",
  );
}

export function configuredQrisProviderMode(): QrisProviderMode {
  const value = Deno.env.get("MIDTRANS_QRIS_PROVIDER_MODE")?.trim()
    .toLowerCase() ?? "qris";
  if (value === "qris" || value === "gopay") return value;
  throw new HttpError(
    500,
    "midtrans_not_configured",
    "Konfigurasi mode QRIS Midtrans tidak valid.",
  );
}

function basicAuthorization(serverKey: string): string {
  return `Basic ${btoa(`${serverKey}:`)}`;
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

export function canonicalQrisPaymentMethod(value: unknown): "QRIS" {
  if (typeof value !== "string" || value.trim().toLowerCase() !== "qris") {
    throw new HttpError(
      400,
      "invalid_payment_method",
      "Metode pembayaran harus QRIS.",
    );
  }
  return "QRIS";
}

export function canonicalCheckoutPaymentMethod(
  value: unknown,
): CheckoutPaymentMethod {
  const method = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (method === "qris") return "QRIS";
  if (method === "midtrans") return "MIDTRANS";
  throw new HttpError(
    400,
    "invalid_payment_method",
    "Metode pembayaran tidak didukung.",
  );
}

export function buildQrisChargePayload(
  input: QrisCheckoutInput,
  now = new Date(),
  acquirer: QrisAcquirer = "gopay",
  providerMode: QrisProviderMode = "qris",
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

  const itemDetails = input.items.map((item) => {
    const id = item.id.trim().slice(0, 50);
    if (!id) {
      throw new HttpError(500, "invalid_checkout", "ID item tidak valid.");
    }
    return {
      id,
      price: integer(item.price, "Harga item"),
      quantity: integer(item.quantity, "Jumlah item"),
      name: item.name.trim().slice(0, 50) || "Item SaveBite",
    };
  });
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
  const remainingMinutes = Math.floor(
    (expiresAt - now.getTime()) / 60_000,
  );
  if (remainingMinutes < 1) {
    throw new HttpError(
      409,
      "payment_expired",
      "Waktu pembayaran sudah terlalu singkat.",
    );
  }
  const duration = Math.min(15, remainingMinutes);
  const customerDetails = Object.fromEntries(
    Object.entries(input.customer)
      .filter(([, value]) =>
        typeof value === "string" && value.trim().length > 0
      )
      .map(([key, value]) => [key, String(value).trim()]),
  );

  const providerFields = providerMode === "gopay"
    ? {
      // Midtrans Core GoPay returns both a native QRIS image action and a
      // deeplink. SaveBite persists and exposes only the QR image action.
      payment_type: "gopay",
      gopay: { enable_callback: false },
    }
    : {
      payment_type: "qris",
      qris: { acquirer },
    };

  return {
    ...providerFields,
    transaction_details: {
      order_id: input.providerOrderId,
      gross_amount: grossAmount,
    },
    item_details: itemDetails,
    ...(Object.keys(customerDetails).length > 0
      ? { customer_details: customerDetails }
      : {}),
    custom_expiry: {
      order_time: now.toISOString().replace("T", " ")
        .replace(/\.\d{3}Z$/, " +0000"),
      expiry_duration: duration,
      unit: "minute",
    },
  };
}

/// Build the server-owned Snap contract used by SaveBite. The payment list is
/// owned by the server: a QRIS checkout can never be widened to another rail,
/// and a MIDTRANS checkout offers every method active on the merchant account.
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
  const paymentMethod = input.paymentMethod ?? "QRIS";
  if (paymentMethod !== "QRIS" && paymentMethod !== "MIDTRANS") {
    throw new HttpError(500, "invalid_checkout", "Metode checkout tidak valid.");
  }
  if (!Array.isArray(input.items) || input.items.length === 0) {
    throw new HttpError(500, "invalid_checkout", "Item checkout tidak valid.");
  }

  const itemDetails = input.items.map((item) => {
    const id = item.id.trim().slice(0, 50);
    if (!id) {
      throw new HttpError(500, "invalid_checkout", "ID item tidak valid.");
    }
    return {
      id,
      price: integer(item.price, "Harga item"),
      quantity: integer(item.quantity, "Jumlah item"),
      name: item.name.trim().slice(0, 50) || "Item SaveBite",
    };
  });
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
  // Snap accepts a whole-minute expiry. Floor keeps the provider deadline at
  // or before the database reservation, so a released bag cannot still be
  // paid through a checkout that outlived SaveBite's local clock.
  const remainingMinutes = Math.floor(
    (expiresAt - now.getTime()) / 60_000,
  );
  if (remainingMinutes < 1) {
    throw new HttpError(
      409,
      "payment_expired",
      "Waktu pembayaran sudah terlalu singkat.",
    );
  }
  const customerDetails = Object.fromEntries(
    Object.entries(input.customer)
      .filter(([, value]) =>
        typeof value === "string" && value.trim().length > 0
      )
      .map(([key, value]) => [key, String(value).trim()]),
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
    // `other_qris` always renders a QR instead of choosing a wallet deeplink
    // based on the device form factor. Without a list, Snap shows every
    // method active on the merchant account.
    ...(paymentMethod === "QRIS" ? { enabled_payments: ["other_qris"] } : {}),
    expiry: {
      start_time: now.toISOString().replace("T", " ")
        .replace(/\.\d{3}Z$/, " +0000"),
      duration: Math.min(15, remainingMinutes),
      unit: "minutes",
    },
    // The hosted checkout leaves the web app, so it returns there; the QRIS
    // WebView checkout returns to the mobile app.
    callbacks: {
      finish: finishCallbackUrl(paymentMethod === "MIDTRANS" ? "web" : "app"),
    },
  };
}

function snapToken(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const result = value.trim();
  return /^[A-Za-z0-9_-]{8,512}$/.test(result) ? result : null;
}

function snapRedirectId(value: string): string | null {
  let decoded: string;
  try {
    decoded = decodeURIComponent(value);
  } catch {
    return null;
  }
  return /^[A-Za-z0-9_-]{8,512}$/.test(decoded) ? decoded : null;
}

export function parseSnapTransaction(
  body: Record<string, unknown>,
  expectedBaseUrl: string,
): SnapTransaction {
  const token = snapToken(body.token);
  const rawRedirect = boundedString(body.redirect_url, 2048);
  if (!token || !rawRedirect) {
    throw new MidtransProtocolError("create", "snap_fields");
  }

  let expectedOrigin: URL;
  let redirect: URL;
  try {
    expectedOrigin = new URL(expectedBaseUrl);
    redirect = new URL(rawRedirect);
  } catch {
    throw new MidtransProtocolError("create", "snap_url");
  }
  const segments = redirect.pathname.split("/").filter(Boolean);
  // Midtrans can return /snap/v3|v4/redirection/{id}; older sandbox accounts
  // can still return /snap/v2/vtweb/{id}. The redirect id is not contractually
  // equal to the Snap token, so validate each independently.
  const pathMatches = segments.length === 4 && segments[0] === "snap" &&
    (((segments[1] === "v3" || segments[1] === "v4") &&
      segments[2] === "redirection") ||
      (segments[1] === "v2" && segments[2] === "vtweb")) &&
    snapRedirectId(segments[3]) !== null;
  if (
    redirect.protocol !== "https:" ||
    redirect.origin !== expectedOrigin.origin ||
    redirect.username || redirect.password || redirect.port ||
    redirect.search || redirect.hash || !pathMatches
  ) {
    throw new MidtransProtocolError("create", "snap_url");
  }
  return { token, redirect_url: redirect.toString() };
}

export async function createSnapTransaction(
  payload: Record<string, unknown>,
): Promise<SnapTransaction> {
  const cfg = config();
  const details = payload.transaction_details;
  const transaction = details !== null && !Array.isArray(details) &&
      typeof details === "object"
    ? details as Record<string, unknown>
    : {};
  const providerOrderId = boundedString(transaction.order_id, 50);
  if (!providerOrderId || !/^SB-[A-F0-9]{32}$/.test(providerOrderId)) {
    throw new HttpError(500, "invalid_checkout", "ID checkout tidak valid.");
  }
  for (let attempt = 0; attempt < 4; attempt++) {
    let response: Response;
    try {
      response = await fetch(`${cfg.snapBaseUrl}/snap/v1/transactions`, {
        method: "POST",
        headers: {
          Authorization: basicAuthorization(cfg.serverKey),
          "Content-Type": "application/json",
          Accept: "application/json",
          "Idempotency-Key": providerOrderId,
          "X-Override-Notification": cfg.notificationUrl,
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(12_000),
      });
    } catch {
      if (attempt < 3) {
        await new Promise((resolve) =>
          setTimeout(resolve, 200 * (attempt + 1))
        );
        continue;
      }
      throw new MidtransApiError(503, "create");
    }

    const body = await readProviderJson(response, "create");
    const providerCode = canonicalStatusCode(body.status_code);
    const retryableCode = providerCode == null ? null : Number(providerCode);
    const retryable = response.status === 202 || response.status === 408 ||
      response.status === 425 || response.status === 429 ||
      response.status >= 500 || retryableCode === 202 ||
      retryableCode === 408 || retryableCode === 425 ||
      retryableCode === 429 || (retryableCode !== null && retryableCode >= 500);
    if (retryable && attempt < 3) {
      await new Promise((resolve) => setTimeout(resolve, 200 * (attempt + 1)));
      continue;
    }
    if (
      providerCode && providerCode !== "201" &&
      /^[45][0-9]{2}$/.test(providerCode)
    ) {
      throw new MidtransApiError(Number(providerCode), "create");
    }
    if (response.status !== 201) {
      throw new MidtransApiError(response.status || 502, "create");
    }
    return parseSnapTransaction(body, cfg.snapBaseUrl);
  }
  throw new MidtransApiError(503, "create");
}

async function readProviderJson(
  response: Response,
  operation: MidtransOperation,
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

export async function createQrisTransaction(
  payload: Record<string, unknown>,
  idempotencyKey: string,
): Promise<QrisTransaction> {
  const cfg = config();
  if (!/^SB-[A-F0-9]{32}$/.test(idempotencyKey)) {
    throw new HttpError(500, "invalid_checkout", "ID checkout tidak valid.");
  }
  const details = payload.transaction_details;
  const transaction = details !== null && !Array.isArray(details) &&
      typeof details === "object"
    ? details as Record<string, unknown>
    : {};
  const expectedGrossAmount = Number(transaction.gross_amount);
  const expectedPaymentType = boundedString(payload.payment_type, 32)
    ?.toLowerCase();
  const qris = payload.qris !== null && !Array.isArray(payload.qris) &&
      typeof payload.qris === "object"
    ? payload.qris as Record<string, unknown>
    : {};
  const expectedAcquirer = boundedString(qris.acquirer, 32)?.toLowerCase();
  const gopay = payload.gopay !== null && !Array.isArray(payload.gopay) &&
      typeof payload.gopay === "object"
    ? payload.gopay as Record<string, unknown>
    : {};
  const validProviderContract = expectedPaymentType === "qris"
    ? (expectedAcquirer === "gopay" ||
      expectedAcquirer === "airpay shopee") &&
      !Object.hasOwn(payload, "gopay")
    : expectedPaymentType === "gopay" &&
      gopay.enable_callback === false &&
      !Object.hasOwn(payload, "qris");
  if (
    transaction.order_id !== idempotencyKey ||
    !Number.isSafeInteger(expectedGrossAmount) || expectedGrossAmount <= 0 ||
    !validProviderContract
  ) {
    throw new HttpError(
      500,
      "invalid_checkout",
      "Payload checkout tidak valid.",
    );
  }
  for (let attempt = 0; attempt < 4; attempt++) {
    let response: Response;
    try {
      response = await fetch(`${cfg.apiBaseUrl}/v2/charge`, {
        method: "POST",
        headers: {
          Authorization: basicAuthorization(cfg.serverKey),
          "Content-Type": "application/json",
          Accept: "application/json",
          "Idempotency-Key": idempotencyKey,
          "X-Override-Notification": cfg.notificationUrl,
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(12_000),
      });
    } catch {
      // A timeout is ambiguous: Midtrans may have created the transaction
      // after our connection was lost. Recover only from an authoritative,
      // exact pending QRIS status; otherwise keep the failure retryable.
      try {
        return await recoverExistingQrisTransaction(
          idempotencyKey,
          expectedGrossAmount,
          cfg.apiBaseUrl,
          expectedPaymentType as QrisProviderMode,
        );
      } catch {
        throw new MidtransApiError(503, "create");
      }
    }
    const body = await readProviderJson(response, "create");
    if (response.status === 202) {
      if (attempt < 3) {
        await new Promise((resolve) => setTimeout(resolve, 350));
        continue;
      }
      throw new MidtransApiError(503, "create");
    }
    const providerCode = canonicalStatusCode(body.status_code);
    if (response.status === 406 || providerCode === "406") {
      return await recoverExistingQrisTransaction(
        idempotencyKey,
        expectedGrossAmount,
        cfg.apiBaseUrl,
        expectedPaymentType as QrisProviderMode,
      );
    }
    if (
      providerCode && providerCode !== "201" &&
      /^[45][0-9]{2}$/.test(providerCode)
    ) {
      throw new MidtransApiError(Number(providerCode), "create");
    }
    if (!response.ok) {
      throw new MidtransApiError(response.status, "create");
    }
    return parseQrisChargeResponse(
      body,
      idempotencyKey,
      expectedGrossAmount,
      cfg.apiBaseUrl,
      expectedPaymentType as QrisProviderMode,
      expectedAcquirer as QrisAcquirer | null,
    );
  }
  throw new MidtransApiError(503, "create");
}

function optionalString(value: unknown, maxLength = 255): string | null {
  if (typeof value !== "string") return null;
  const result = value.trim();
  return result ? result.slice(0, maxLength) : null;
}

function boundedString(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;
  const result = value.trim();
  return result && result.length <= maxLength ? result : null;
}

function canonicalStatusCode(value: unknown): string | null {
  if (typeof value === "number") {
    return Number.isInteger(value) && value >= 100 && value <= 999
      ? String(value)
      : null;
  }
  const result = boundedString(value, 3);
  return result && /^[0-9]{3}$/.test(result) ? result : null;
}

function canonicalQrisUrl(
  apiBaseUrl: string,
  transactionId: string,
  providerMode: QrisProviderMode = "qris",
): string {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(transactionId)
  ) {
    throw new MidtransApiError(502, "create");
  }
  let base: URL;
  try {
    base = new URL(apiBaseUrl);
  } catch {
    throw new MidtransApiError(502, "create");
  }
  const approvedHost = ["api.midtrans.com", "api.sandbox.midtrans.com"]
    .includes(base.hostname);
  if (
    base.protocol !== "https:" || !approvedHost || base.port ||
    base.username || base.password
  ) {
    throw new MidtransApiError(502, "create");
  }
  base.pathname = `/v2/${providerMode}/${transactionId}/qr-code`;
  base.search = "";
  base.hash = "";
  return base.toString();
}

export function pendingQrisPaymentUrl(
  status: MidtransStatus,
): string | null {
  const providerMode = status.payment_type?.trim().toLowerCase();
  if (
    (providerMode !== "qris" && providerMode !== "gopay") ||
    status.transaction_status.trim().toLowerCase() !== "pending"
  ) {
    return null;
  }
  if (!status.transaction_id) {
    throw new MidtransApiError(502, "status");
  }
  return canonicalQrisUrl(
    config().apiBaseUrl,
    status.transaction_id,
    providerMode,
  );
}

/// Convenience URL khusus pengujian manual melalui Midtrans QRIS Simulator.
///
/// Fail closed: fitur ini membutuhkan helper dan environment sandbox eksplisit,
/// menolak config production yang bertentangan, dan hanya menerima transaksi
/// QRIS pending dengan transaction_id UUID dari respons status provider yang
/// telah diparse.
export function sandboxSimulatorQrisImageUrl(
  status: MidtransStatus,
): string | null {
  if (
    !simulatorHelpersEnabled() ||
    isProduction() ||
    status.payment_type?.trim().toLowerCase() !== "qris" ||
    status.transaction_status.trim().toLowerCase() !== "pending" ||
    !status.transaction_id ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(status.transaction_id)
  ) {
    return null;
  }
  return canonicalQrisUrl(
    "https://api.sandbox.midtrans.com",
    status.transaction_id,
    "qris",
  );
}

async function recoverExistingQrisTransaction(
  expectedOrderId: string,
  expectedGrossAmount: number,
  apiBaseUrl: string,
  expectedProviderMode: QrisProviderMode,
): Promise<QrisTransaction> {
  let status: MidtransStatus;
  try {
    status = await getMidtransStatus(expectedOrderId);
  } catch (error) {
    const httpStatus = error instanceof MidtransApiError
      ? error.httpStatus
      : 502;
    throw new MidtransApiError(httpStatus, "create");
  }
  const transactionId = status.transaction_id;
  if (
    status.order_id !== expectedOrderId ||
    status.payment_type?.toLowerCase() !== expectedProviderMode ||
    status.transaction_status.toLowerCase() !== "pending" ||
    !transactionId ||
    !/^[0-9]+(?:\.[0-9]{1,2})?$/.test(status.gross_amount) ||
    Number(status.gross_amount) !== expectedGrossAmount
  ) {
    throw new MidtransApiError(502, "create");
  }
  return {
    transaction_id: transactionId,
    payment_qr_url: canonicalQrisUrl(
      apiBaseUrl,
      transactionId,
      expectedProviderMode,
    ),
  };
}

export function parseQrisChargeResponse(
  body: Record<string, unknown>,
  expectedOrderId: string,
  expectedGrossAmount: number,
  expectedApiBaseUrl: string,
  expectedProviderMode: QrisProviderMode = "qris",
  expectedAcquirer: QrisAcquirer | null = "gopay",
): QrisTransaction {
  const statusCode = canonicalStatusCode(body.status_code);
  const orderId = boundedString(body.order_id, 50);
  const paymentType = boundedString(body.payment_type, 32)?.toLowerCase();
  const transactionStatus = boundedString(body.transaction_status, 32)
    ?.toLowerCase();
  const currency = boundedString(body.currency, 3)?.toUpperCase();
  const acquirer = boundedString(body.acquirer, 32)?.toLowerCase();
  const transactionId = boundedString(body.transaction_id, 255);
  const grossAmount = boundedString(body.gross_amount, 64);
  if (statusCode !== "201") {
    throw new MidtransProtocolError("create", "status_code");
  }
  if (orderId !== expectedOrderId) {
    throw new MidtransProtocolError("create", "order_id");
  }
  if (paymentType !== expectedProviderMode) {
    throw new MidtransProtocolError("create", "payment_type");
  }
  if (transactionStatus !== "pending") {
    throw new MidtransProtocolError("create", "transaction_status");
  }
  if (currency !== "IDR") {
    throw new MidtransProtocolError("create", "currency");
  }
  if (
    expectedProviderMode === "qris" && acquirer !== expectedAcquirer ||
    expectedProviderMode === "gopay" &&
      acquirer != null && acquirer !== "gopay"
  ) {
    throw new MidtransProtocolError("create", "acquirer");
  }
  if (
    !transactionId ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(transactionId)
  ) {
    throw new MidtransProtocolError("create", "transaction_id");
  }
  if (
    !grossAmount || !/^[0-9]+(?:\.[0-9]{1,2})?$/.test(grossAmount) ||
    !Number.isSafeInteger(expectedGrossAmount) ||
    Number(grossAmount) !== expectedGrossAmount
  ) {
    throw new MidtransProtocolError("create", "amount");
  }

  const actions = Array.isArray(body.actions) ? body.actions : [];
  const qrActions = actions.map((value) =>
    value !== null && !Array.isArray(value) && typeof value === "object"
      ? value as Record<string, unknown>
      : {}
  ).filter((action) => action.name === "generate-qr-code");
  if (qrActions.length !== 1) {
    throw new MidtransProtocolError("create", "qr_action_count");
  }
  const qrAction = qrActions[0];
  const method = boundedString(qrAction.method, 16)?.toUpperCase();
  const rawQrUrl = boundedString(qrAction.url, 2_048);
  let qrUrl: URL;
  try {
    qrUrl = new URL(rawQrUrl ?? "");
  } catch {
    throw new MidtransProtocolError("create", "qr_url");
  }
  const canonicalUrl = canonicalQrisUrl(
    expectedApiBaseUrl,
    transactionId,
    expectedProviderMode,
  );
  if (method !== "GET") {
    throw new MidtransProtocolError("create", "qr_method");
  }
  if (qrUrl.toString() !== canonicalUrl) {
    throw new MidtransProtocolError("create", "qr_origin_or_path");
  }

  return {
    transaction_id: transactionId,
    payment_qr_url: canonicalUrl,
  };
}

export function parseMidtransStatus(
  body: Record<string, unknown>,
  expectedOrderId: string,
): MidtransStatus {
  const orderId = optionalString(body.order_id, 50);
  const transactionStatus = optionalString(body.transaction_status, 64);
  const statusCode = canonicalStatusCode(body.status_code);
  const grossAmount = optionalString(body.gross_amount, 64);
  if (
    orderId !== expectedOrderId || !transactionStatus ||
    !statusCode || !grossAmount
  ) {
    throw new MidtransProtocolError("status", "fields");
  }
  const providerTimes = [
    optionalString(body.settlement_time, 64),
    optionalString(body.transaction_time, 64),
  ].filter((value): value is string =>
    value !== null && Number.isFinite(Date.parse(value))
  );
  const refunds = Array.isArray(body.refunds) ? body.refunds : [];
  for (const value of refunds) {
    if (value === null || Array.isArray(value) || typeof value !== "object") {
      continue;
    }
    const createdAt = optionalString(
      (value as Record<string, unknown>).created_at,
      64,
    );
    if (createdAt && Number.isFinite(Date.parse(createdAt))) {
      providerTimes.push(createdAt);
    }
  }
  providerTimes.sort((left, right) => Date.parse(right) - Date.parse(left));
  const statusTimestamp = providerTimes[0] ?? null;
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

export function merchantCancellationAction(
  transactionStatus: string,
): MerchantCancellationAction {
  switch (transactionStatus.trim().toLowerCase()) {
    case "pending":
    case "authorize":
    case "capture":
      return "cancel";
    case "settlement":
      return "refund";
    case "cancel":
    case "refund":
      return "complete";
    default:
      return "review";
  }
}

export function merchantRefundKey(providerOrderId: string): string {
  if (!/^SB-[A-F0-9]{32}$/.test(providerOrderId)) {
    throw new HttpError(400, "invalid_order", "ID pembayaran tidak valid.");
  }
  // Midtrans refund_key accepts letters, numbers, dash, and underscore. The
  // deterministic value makes a retry the same refund instead of a second one.
  return `SB_CANCEL_${providerOrderId.slice(3)}`;
}

function providerReference(value: string): string {
  const result = value.trim();
  if (
    result.length < 1 || result.length > 255 ||
    !/^[A-Za-z0-9_-]+$/.test(result)
  ) {
    throw new HttpError(
      500,
      "invalid_payment",
      "Referensi pembayaran tidak valid.",
    );
  }
  return result;
}

async function mutateMidtransTransaction(
  operation: "cancel" | "refund",
  reference: string,
  payload?: Record<string, unknown>,
): Promise<void> {
  const cfg = config();
  let response: Response;
  try {
    response = await fetch(
      `${cfg.apiBaseUrl}/v2/${
        encodeURIComponent(providerReference(reference))
      }/${operation}`,
      {
        method: "POST",
        headers: {
          Authorization: basicAuthorization(cfg.serverKey),
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        ...(payload ? { body: JSON.stringify(payload) } : {}),
        signal: AbortSignal.timeout(12_000),
      },
    );
  } catch {
    throw new MidtransApiError(503, operation);
  }

  const body = await readProviderJson(response, operation);
  const providerCode = canonicalStatusCode(body.status_code);
  const providerStatus = optionalString(body.transaction_status, 64)
    ?.toLowerCase();
  const acceptedStatus = operation === "cancel"
    ? providerStatus === "cancel"
    : providerStatus === "refund" || providerStatus === "partial_refund";
  if (
    !response.ok || !providerCode || !/^2[0-9]{2}$/.test(providerCode) ||
    !acceptedStatus
  ) {
    const safeStatus = providerCode && /^[0-9]{3}$/.test(providerCode)
      ? Number(providerCode)
      : response.status || 502;
    throw new MidtransApiError(safeStatus, operation);
  }
}

export async function cancelMidtransTransaction(
  reference: string,
): Promise<void> {
  await mutateMidtransTransaction("cancel", reference);
}

export async function refundMidtransTransaction(
  reference: string,
  refundKey: string,
  reason: string,
): Promise<void> {
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(refundKey)) {
    throw new HttpError(500, "invalid_refund", "Referensi refund tidak valid.");
  }
  const safeReason = reason.trim();
  if (safeReason.length < 3 || safeReason.length > 255) {
    throw new HttpError(500, "invalid_refund", "Alasan refund tidak valid.");
  }
  // Omitting amount is an intentional full refund according to Midtrans. This
  // returns the service fee as well as the bag subtotal to the customer.
  await mutateMidtransTransaction("refund", reference, {
    refund_key: refundKey,
    reason: safeReason,
  });
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
