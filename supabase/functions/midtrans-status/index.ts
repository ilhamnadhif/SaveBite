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
  getMidtransStatus,
  MidtransApiError,
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

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return optionsResponse();
  try {
    requirePost(request);
    const body = await readJsonObject(request);
    const orderId = requiredUuid(body.order_id, "order_id");
    const userClient = createUserClient(request);
    const user = await requireUser(userClient);
    const service = createServiceClient();

    const { data: targetData, error: targetError } = await service.rpc(
      "get_midtrans_sync_target",
      { p_order_id: orderId, p_actor_id: user.id },
    );
    if (targetError) {
      throw new HttpError(404, "order_not_found", "Pesanan tidak ditemukan.");
    }
    const target = object(targetData);
    const providerOrderId = String(target.midtrans_order_id ?? "");
    const actorKind = target.actor_kind === "merchant"
      ? "merchant"
      : "consumer";

    let authoritative;
    try {
      authoritative = await getMidtransStatus(providerOrderId);
    } catch (error) {
      // Snap can return 404 until the customer has selected a payment method.
      // That is not evidence of failure and must not release the reservation.
      if (error instanceof MidtransApiError && error.isNotFound) {
        const order = await selectOwnedOrder(userClient, orderId, actorKind);
        return jsonResponse({ order, synced: false });
      }
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
      throw new HttpError(
        error instanceof MidtransApiError && error.httpStatus === 503
          ? 503
          : 502,
        "midtrans_unavailable",
        "Status pembayaran belum dapat diverifikasi ke Midtrans.",
      );
    }

    const { error: applyError } = await service.rpc(
      "apply_midtrans_payment_status",
      applyStatusParams(authoritative),
    );
    if (applyError) {
      throw new HttpError(
        409,
        "payment_reconciliation_required",
        "Status pembayaran perlu diperiksa sebelum pesanan dilanjutkan.",
      );
    }

    const order = await selectOwnedOrder(userClient, orderId, actorKind);
    return jsonResponse({ order, synced: true });
  } catch (error) {
    return errorResponse(error);
  }
});
