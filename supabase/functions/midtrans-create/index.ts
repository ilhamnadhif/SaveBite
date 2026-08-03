import { type SupabaseClient } from "npm:@supabase/supabase-js@2.110.7";
import {
  errorResponse,
  HttpError,
  jsonResponse,
  optionsResponse,
  readJsonObject,
  requiredString,
  requiredUuid,
  requirePost,
} from "../_shared/http.ts";
import {
  assertMidtransConfigured,
  buildSnapPayload,
  canonicalQrisPaymentMethod,
  type CheckoutItem,
  createSnapTransaction,
  MidtransApiError,
  type SnapCheckoutInput,
} from "../_shared/midtrans.ts";
import {
  createServiceClient,
  createUserClient,
  requireUser,
  selectOwnedOrder,
} from "../_shared/supabase.ts";

function databaseFailure(
  message: string | undefined,
  phase: "reserve" | "claim",
) {
  const normalized = (message ?? "").toLowerCase();
  if (normalized.includes("insufficient stock")) {
    return new HttpError(409, "insufficient_stock", "Stok tidak mencukupi.");
  }
  if (normalized.includes("not active") || normalized.includes("unavailable")) {
    return new HttpError(409, "bag_unavailable", "Bag sedang tidak tersedia.");
  }
  if (normalized.includes("pickup window has ended")) {
    return new HttpError(
      409,
      "pickup_ended",
      "Waktu pengambilan sudah berakhir.",
    );
  }
  if (normalized.includes("pickup window ends too soon for payment")) {
    return new HttpError(
      409,
      "pickup_ended",
      "Waktu pengambilan terlalu dekat untuk menyelesaikan pembayaran.",
    );
  }
  if (normalized.includes("idempotency key was already used")) {
    return new HttpError(
      409,
      "idempotency_conflict",
      "Permintaan checkout tidak cocok dengan permintaan sebelumnya.",
    );
  }
  if (normalized.includes("payment reservation has expired")) {
    return new HttpError(
      409,
      "payment_expired",
      "Waktu pembayaran sudah habis.",
    );
  }
  if (normalized.includes("no longer eligible")) {
    return new HttpError(
      409,
      "payment_not_eligible",
      "Pembayaran ini sudah tidak dapat dilanjutkan.",
    );
  }
  return new HttpError(
    502,
    phase === "reserve"
      ? "checkout_reservation_failed"
      : "checkout_claim_failed",
    "Checkout belum dapat dibuat. Coba lagi.",
  );
}

function object(value: unknown): Record<string, unknown> {
  return value !== null && !Array.isArray(value) && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
}

function checkoutInput(claim: Record<string, unknown>): SnapCheckoutInput {
  const customer = object(claim.customer);
  if (!Array.isArray(claim.items)) {
    throw new HttpError(500, "invalid_checkout", "Item checkout tidak valid.");
  }
  const items = claim.items.map((value) => {
    const item = object(value);
    return {
      id: typeof item.id === "string" ? item.id : "",
      price: item.price,
      quantity: item.quantity,
      name: typeof item.name === "string" ? item.name : "",
    } as CheckoutItem;
  });
  return {
    providerOrderId: String(claim.midtrans_order_id ?? ""),
    grossAmount: Number(claim.gross_amount),
    paymentExpiresAt: String(claim.payment_expires_at ?? ""),
    customer: {
      first_name: typeof customer.first_name === "string"
        ? customer.first_name
        : null,
      email: typeof customer.email === "string" ? customer.email : null,
      phone: typeof customer.phone === "string" ? customer.phone : null,
    },
    items,
  };
}

async function releaseCheckoutLease(
  service: SupabaseClient,
  orderId: string,
  leaseToken: string,
  errorCode: string,
): Promise<void> {
  // Best effort only.  The short database lease expires even if this call is
  // interrupted; no provider body or credential is persisted.
  await service.rpc("fail_midtrans_checkout", {
    p_order_id: orderId,
    p_lease_token: leaseToken,
    p_error_code: errorCode,
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return optionsResponse();
  try {
    requirePost(request);
    const body = await readJsonObject(request);
    const bagId = requiredUuid(body.bag_id, "bag_id");
    const quantity = body.quantity;
    if (
      typeof quantity !== "number" || !Number.isSafeInteger(quantity) ||
      quantity < 1 || quantity > 100
    ) {
      throw new HttpError(400, "invalid_quantity", "Jumlah bag tidak valid.");
    }
    const paymentMethod = canonicalQrisPaymentMethod(body.payment_method);
    const idempotencyKey = requiredString(
      body.idempotency_key,
      "idempotency_key",
      8,
      128,
    );
    const userClient = createUserClient(request);
    const user = await requireUser(userClient);
    assertMidtransConfigured();
    const { data: reserved, error: reserveError } = await userClient.rpc(
      "purchase_bag",
      {
        p_bag_id: bagId,
        p_qty: quantity,
        p_method: paymentMethod,
        p_idempotency_key: idempotencyKey,
      },
    );
    if (reserveError) throw databaseFailure(reserveError.message, "reserve");
    const reservedOrder = object(reserved);
    const orderId = requiredUuid(
      reservedOrder.order_id ?? reservedOrder.id,
      "order_id",
    );

    const service = createServiceClient();
    const { data: claimed, error: claimError } = await service.rpc(
      "claim_midtrans_checkout",
      { p_order_id: orderId, p_consumer_id: user.id },
    );
    if (claimError) {
      if (
        claimError.message.toLowerCase().includes("reservation has expired")
      ) {
        const { error: expiryError } = await service.rpc("expire_orders", {
          p_limit: 5_000,
        });
        if (expiryError) throw databaseFailure(expiryError.message, "claim");
        const order = await selectOwnedOrder(userClient, orderId, "consumer");
        return jsonResponse({ order });
      }
      throw databaseFailure(claimError.message, "claim");
    }
    const claim = object(claimed);
    const mode = String(claim.mode ?? "");

    if (mode === "in_progress") {
      throw new HttpError(
        409,
        "checkout_in_progress",
        "Checkout sedang dibuat. Coba lagi sebentar.",
      );
    }
    if (mode === "create") {
      const leaseToken = requiredString(
        claim.lease_token,
        "lease_token",
        32,
        128,
      );
      let snap;
      try {
        const input = checkoutInput(claim);
        snap = await createSnapTransaction(
          buildSnapPayload(input, new Date()),
        );
      } catch (error) {
        const safeCode = error instanceof MidtransApiError
          ? error.safeCode
          : "checkout_payload_error";
        console.warn(JSON.stringify({
          event: "midtrans_create_failed",
          code: safeCode,
        }));
        await releaseCheckoutLease(service, orderId, leaseToken, safeCode);
        if (error instanceof HttpError) throw error;
        if (
          error instanceof MidtransApiError &&
          [401, 403].includes(error.httpStatus)
        ) {
          throw new HttpError(
            500,
            "midtrans_not_configured",
            "Credential Midtrans di server tidak valid.",
          );
        }
        if (error instanceof MidtransApiError && error.httpStatus === 402) {
          throw new HttpError(
            503,
            "midtrans_qris_not_enabled",
            "Kanal QRIS pada Snap Midtrans belum aktif.",
          );
        }
        throw new HttpError(
          error instanceof MidtransApiError && error.httpStatus === 503
            ? 503
            : 502,
          "midtrans_unavailable",
          "Halaman pembayaran Midtrans belum dapat dibuat. Coba lagi.",
        );
      }

      const completionParams = {
        p_order_id: orderId,
        p_lease_token: leaseToken,
        p_snap_token: snap.token,
        p_redirect_url: snap.redirect_url,
      };
      let completion = await service.rpc(
        "complete_midtrans_snap_checkout",
        completionParams,
      );
      // One immediate retry narrows the provider-created/database-write gap.
      if (completion.error) {
        completion = await service.rpc(
          "complete_midtrans_snap_checkout",
          completionParams,
        );
      }
      if (completion.error) {
        throw new HttpError(
          503,
          "checkout_persistence_failed",
          "Checkout dibuat tetapi belum dapat disimpan. Coba lagi sebentar.",
        );
      }
    } else if (mode !== "reuse" && mode !== "completed") {
      throw new HttpError(
        502,
        "invalid_checkout_state",
        "Status checkout dari server tidak valid.",
      );
    }

    const order = await selectOwnedOrder(userClient, orderId, "consumer");
    return jsonResponse({ order });
  } catch (error) {
    return errorResponse(error);
  }
});
