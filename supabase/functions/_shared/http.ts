export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

const jsonHeaders = {
  ...corsHeaders,
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

export class HttpError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...jsonHeaders, ...extraHeaders },
  });
}

export function optionsResponse(): Response {
  return new Response(null, { status: 204, headers: corsHeaders });
}

export function requirePost(request: Request): void {
  if (request.method !== "POST") {
    throw new HttpError(405, "method_not_allowed", "Gunakan metode POST.");
  }
}

export async function readJsonObject(
  request: Request,
  maxBytes = 16_384,
): Promise<Record<string, unknown>> {
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new HttpError(413, "payload_too_large", "Payload terlalu besar.");
  }

  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > maxBytes) {
    throw new HttpError(413, "payload_too_large", "Payload terlalu besar.");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new HttpError(400, "invalid_json", "Payload JSON tidak valid.");
  }
  if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object") {
    throw new HttpError(
      400,
      "invalid_json",
      "Payload JSON harus berupa objek.",
    );
  }
  return parsed as Record<string, unknown>;
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return jsonResponse(
      { code: error.code, message: error.message, error: error.message },
      error.status,
      error.status === 405 ? { Allow: "POST, OPTIONS" } : {},
    );
  }

  // Never return stack traces, provider bodies, SQL details, or credentials.
  return jsonResponse(
    {
      code: "internal_error",
      message: "Layanan pembayaran sedang bermasalah. Coba lagi.",
      error: "Layanan pembayaran sedang bermasalah. Coba lagi.",
    },
    500,
  );
}

export function requiredString(
  value: unknown,
  field: string,
  minLength: number,
  maxLength: number,
): string {
  if (typeof value !== "string") {
    throw new HttpError(400, "invalid_request", `${field} tidak valid.`);
  }
  const result = value.trim();
  if (result.length < minLength || result.length > maxLength) {
    throw new HttpError(400, "invalid_request", `${field} tidak valid.`);
  }
  return result;
}

export function requiredUuid(value: unknown, field: string): string {
  const result = requiredString(value, field, 36, 36).toLowerCase();
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(
        result,
      )
  ) {
    throw new HttpError(400, "invalid_request", `${field} tidak valid.`);
  }
  return result;
}
