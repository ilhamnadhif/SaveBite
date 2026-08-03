import { type SupabaseClient } from "npm:@supabase/supabase-js@2.110.7";
import {
  errorResponse,
  HttpError,
  jsonResponse,
  optionsResponse,
  readJsonObject,
  requiredUuid,
  requirePost,
} from "../_shared/http.ts";
import {
  applyStatusParams,
  cancelMidtransTransaction,
  getMidtransStatus,
  merchantCancellationAction,
  merchantRefundKey,
  MidtransApiError,
  type MidtransStatus,
  refundMidtransTransaction,
} from "../_shared/midtrans.ts";
import {
  createServiceClient,
  createUserClient,
  requireUser,
  selectOwnedOrder,
} from "../_shared/supabase.ts";

function object(value: unknown): Record<string, unknown> {
  return value !== null && !Array.isArray(value) && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
}

function claimFailure(message: string | undefined): HttpError {
  const normalized = (message ?? "").toLowerCase();
  if (normalized.includes("order not found")) {
    return new HttpError(404, "order_not_found", "Pesanan tidak ditemukan.");
  }
  if (normalized.includes("manual review")) {
    return new HttpError(
      409,
      "merchant_cancellation_requires_review",
      "Pembatalan perlu diperiksa operator sebelum pesanan dilanjutkan.",
    );
  }
  if (normalized.includes("cannot be cancelled")) {
    return new HttpError(
      409,
      "invalid_order_status",
      "Status pesanan sudah berubah dan tidak dapat dibatalkan.",
    );
  }
  return new HttpError(
    502,
    "cancellation_claim_failed",
    "Pembatalan belum dapat dimulai. Coba lagi.",
  );
}

async function recordFailure(
  service: SupabaseClient,
  orderId: string,
  code: string,
): Promise<void> {
  // Best effort only. The durable review marker was already written by claim,
  // so even a logging failure cannot reopen fulfilment.
  await service.rpc("record_midtrans_merchant_cancellation_error", {
    p_order_id: orderId,
    p_error_code: code,
  });
}

async function applyAuthoritativeStatus(
  service: SupabaseClient,
  status: MidtransStatus,
): Promise<Record<string, unknown>> {
  const { data, error } = await service.rpc(
    "apply_midtrans_payment_status",
    applyStatusParams(status),
  );
  if (error) {
    throw new HttpError(
      503,
      "payment_state_not_persisted",
      "Status pembatalan belum tersimpan. Coba lagi.",
    );
  }
  const reconciliation = object(data);
  if (reconciliation.applied !== true) {
    throw new HttpError(
      409,
      "merchant_cancellation_requires_review",
      "Status pembayaran tidak konsisten dan perlu diperiksa operator.",
    );
  }

  if (reconciliation.requires_manual_review === true) {
    const { data: attemptData, error: attemptError } = await service
      .from("payment_attempts")
      .select("requires_manual_review, review_reason")
      .eq("provider_order_id", status.order_id)
      .maybeSingle();
    if (attemptError || !attemptData) {
      throw new HttpError(
        503,
        "payment_state_not_persisted",
        "Status pembatalan belum dapat diverifikasi. Coba lagi.",
      );
    }
    const attempt = object(attemptData);
    if (
      attempt.requires_manual_review === true &&
      attempt.review_reason !== "merchant_cancellation_requested"
    ) {
      throw new HttpError(
        409,
        "merchant_cancellation_requires_review",
        "Status pembayaran perlu diperiksa operator sebelum dibatalkan.",
      );
    }
  }
  return reconciliation;
}

async function reclaimCancellation(
  service: SupabaseClient,
  orderId: string,
  actorId: string,
): Promise<Record<string, unknown>> {
  const { data, error } = await service.rpc(
    "claim_midtrans_merchant_cancellation",
    { p_order_id: orderId, p_actor_id: actorId },
  );
  if (error) throw claimFailure(error.message);
  return object(data);
}

async function terminalMerchantOrder(
  userClient: SupabaseClient,
  orderId: string,
): Promise<Record<string, unknown> | null> {
  const order = await selectOwnedOrder(userClient, orderId, "merchant");
  return ["cancelled", "refunded"].includes(String(order.status ?? ""))
    ? order
    : null;
}

function providerFailure(error: unknown): HttpError {
  if (error instanceof HttpError) return error;
  if (
    error instanceof MidtransApiError &&
    [401, 403].includes(error.httpStatus)
  ) {
    return new HttpError(
      500,
      "midtrans_not_configured",
      "Credential Midtrans di server tidak valid.",
    );
  }
  if (error instanceof MidtransApiError && error.httpStatus === 412) {
    return new HttpError(
      409,
      "merchant_cancellation_requires_review",
      "Midtrans belum dapat membatalkan pembayaran ini secara otomatis. " +
        "Pesanan ditahan untuk pemeriksaan operator.",
    );
  }
  return new HttpError(
    error instanceof MidtransApiError && error.httpStatus === 503 ? 503 : 502,
    "merchant_cancellation_pending",
    "Konfirmasi pembatalan dari Midtrans masih diproses. Coba lagi sebentar.",
  );
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return optionsResponse();
  try {
    requirePost(request);
    const body = await readJsonObject(request);
    const orderId = requiredUuid(body.order_id, "order_id");
    const userClient = createUserClient(request);
    const user = await requireUser(userClient);
    const service = createServiceClient();

    const { data: claimData, error: claimError } = await service.rpc(
      "claim_midtrans_merchant_cancellation",
      { p_order_id: orderId, p_actor_id: user.id },
    );
    if (claimError) throw claimFailure(claimError.message);
    let claim = object(claimData);
    const providerOrderId = String(claim.midtrans_order_id ?? "");

    if (claim.mode === "completed") {
      const order = await terminalMerchantOrder(userClient, orderId);
      if (order) return jsonResponse({ order, provider_confirmed: true });
      throw new HttpError(
        409,
        "merchant_cancellation_requires_review",
        "Status pembatalan perlu direkonsiliasi oleh operator.",
      );
    }

    let authoritative: MidtransStatus;
    try {
      authoritative = await getMidtransStatus(providerOrderId);
      await applyAuthoritativeStatus(service, authoritative);
      // The payment state machine can replace our marker with a stronger
      // manual-review reason. Re-claim atomically proves that the only active
      // review hold is still this merchant cancellation before using the
      // provider transaction ID for cancel/refund.
      claim = await reclaimCancellation(service, orderId, user.id);
    } catch (error) {
      const code = error instanceof MidtransApiError
        ? error.safeCode
        : "merchant_cancel_status_error";
      await recordFailure(service, orderId, code);
      throw providerFailure(error);
    }

    let action = merchantCancellationAction(authoritative.transaction_status);
    if (claim.mode === "completed") {
      const order = await terminalMerchantOrder(userClient, orderId);
      if (order) return jsonResponse({ order, provider_confirmed: true });
    }
    if (claim.mode !== "resume") {
      throw new HttpError(
        409,
        "merchant_cancellation_requires_review",
        "Status pembatalan perlu direkonsiliasi oleh operator.",
      );
    }
    if (action === "complete") {
      const order = await terminalMerchantOrder(userClient, orderId);
      if (order) return jsonResponse({ order, provider_confirmed: true });
      await recordFailure(
        service,
        orderId,
        "merchant_cancel_terminal_state_not_persisted",
      );
      throw new HttpError(
        409,
        "merchant_cancellation_requires_review",
        "Status pembatalan Midtrans belum tersimpan dengan konsisten.",
      );
    }
    if (action === "review") {
      await recordFailure(
        service,
        orderId,
        `merchant_cancel_status_${authoritative.transaction_status}`,
      );
      throw new HttpError(
        409,
        "merchant_cancellation_requires_review",
        "Status pembayaran tidak mendukung pembatalan otomatis. " +
          "Pesanan ditahan untuk pemeriksaan operator.",
      );
    }

    const providerReference = authoritative.transaction_id?.trim() ||
      String(claim.provider_transaction_id ?? "").trim() || providerOrderId;
    let mutationError: unknown;
    try {
      if (action === "refund") {
        await refundMidtransTransaction(
          providerReference,
          merchantRefundKey(providerOrderId),
          "Pesanan dibatalkan merchant SaveBite",
        );
      } else {
        await cancelMidtransTransaction(providerReference);
      }
    } catch (error) {
      // A timeout or duplicate request is ambiguous. Never undo the local hold;
      // GET Status below is the only evidence used to decide the outcome.
      mutationError = error;
    }

    // Midtrans normally reflects cancel/refund immediately. A short bounded
    // retry handles propagation delay; later webhook delivery remains the
    // durable recovery path when this request ends first.
    for (let attempt = 0; attempt < 4; attempt += 1) {
      if (attempt > 0) {
        await new Promise((resolve) => setTimeout(resolve, 350 * attempt));
      }
      try {
        authoritative = await getMidtransStatus(providerOrderId);
        await applyAuthoritativeStatus(service, authoritative);
        action = merchantCancellationAction(authoritative.transaction_status);
        if (action === "complete") {
          const order = await terminalMerchantOrder(userClient, orderId);
          if (order) {
            return jsonResponse({ order, provider_confirmed: true });
          }
        }
      } catch (error) {
        mutationError ??= error;
      }
    }

    const code = mutationError instanceof MidtransApiError
      ? mutationError.safeCode
      : mutationError instanceof HttpError
      ? mutationError.code
      : "merchant_cancel_confirmation_pending";
    await recordFailure(service, orderId, code);
    throw providerFailure(mutationError);
  } catch (error) {
    return errorResponse(error);
  }
});
