import {
  createClient,
  type SupabaseClient,
  type User,
} from "npm:@supabase/supabase-js@2.110.7";
import { HttpError } from "./http.ts";

export function keyFromJsonBundle(
  raw: string | undefined,
  expectedPrefix: string,
): string | undefined {
  if (!raw?.trim()) return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return undefined;
  }
  const values: string[] = [];
  const visit = (value: unknown): void => {
    if (typeof value === "string") {
      if (value.trim()) values.push(value.trim());
    } else if (Array.isArray(value)) {
      value.forEach(visit);
    } else if (value !== null && typeof value === "object") {
      Object.values(value as Record<string, unknown>).forEach(visit);
    }
  };
  visit(parsed);
  return values.find((value) => value.startsWith(expectedPrefix));
}

function requiredEnv(
  name: string,
  fallbackName?: string,
  bundleName?: string,
  bundlePrefix?: string,
): string {
  const value = Deno.env.get(name) ??
    (fallbackName ? Deno.env.get(fallbackName) : undefined) ??
    (bundleName && bundlePrefix
      ? keyFromJsonBundle(Deno.env.get(bundleName), bundlePrefix)
      : undefined);
  if (!value?.trim()) {
    throw new HttpError(
      500,
      "server_not_configured",
      "Konfigurasi server pembayaran belum lengkap.",
    );
  }
  return value.trim();
}

function clientOptions(authorization?: string) {
  return {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: authorization
      ? { headers: { Authorization: authorization } }
      : undefined,
  };
}

export function createUserClient(request: Request): SupabaseClient {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    throw new HttpError(401, "not_authenticated", "Silakan masuk kembali.");
  }
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv(
      "SUPABASE_ANON_KEY",
      "SUPABASE_PUBLISHABLE_KEY",
      "SUPABASE_PUBLISHABLE_KEYS",
      "sb_publishable_",
    ),
    clientOptions(authorization),
  );
}

export function createServiceClient(): SupabaseClient {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv(
      "SUPABASE_SERVICE_ROLE_KEY",
      "SUPABASE_SECRET_KEY",
      "SUPABASE_SECRET_KEYS",
      "sb_secret_",
    ),
    clientOptions(),
  );
}

export async function requireUser(client: SupabaseClient): Promise<User> {
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) {
    throw new HttpError(401, "not_authenticated", "Sesi sudah berakhir.");
  }
  return data.user;
}

export async function selectOwnedOrder(
  client: SupabaseClient,
  orderId: string,
  actorKind: "consumer" | "merchant" = "consumer",
): Promise<Record<string, unknown>> {
  const view = actorKind === "merchant" ? "merchant_orders" : "consumer_orders";
  const { data, error } = await client
    .from(view)
    .select("*")
    .eq("order_id", orderId)
    .maybeSingle();
  if (error) {
    throw new HttpError(
      502,
      "database_unavailable",
      "Status pesanan belum dapat dimuat.",
    );
  }
  if (!data) {
    throw new HttpError(404, "order_not_found", "Pesanan tidak ditemukan.");
  }
  return data as Record<string, unknown>;
}
