import {
  errorResponse,
  HttpError,
  jsonResponse,
  optionsResponse,
  readJsonObject,
  requirePost,
} from "../_shared/http.ts";
import {
  applyStatusParams,
  getMidtransStatus,
  MidtransApiError,
  verifyNotificationSignature,
} from "../_shared/midtrans.ts";
import { createServiceClient } from "../_shared/supabase.ts";

function exactString(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  if (
    typeof value !== "string" || value.length === 0 ||
    value.length > maxLength
  ) {
    throw new HttpError(400, "invalid_notification", `${field} tidak valid.`);
  }
  return value;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return optionsResponse();
  try {
    requirePost(request);
    const body = await readJsonObject(request, 65_536);

    // Do not trim or numerically parse the signed fields.  Midtrans signs the
    // exact string concatenation order_id + status_code + gross_amount + key.
    const orderId = exactString(body.order_id, "order_id", 50);
    const statusCode = exactString(body.status_code, "status_code", 3);
    const grossAmount = exactString(body.gross_amount, "gross_amount", 64);
    const signature = exactString(body.signature_key, "signature_key", 128);
    if (
      !/^SB-[A-F0-9]{32}$/.test(orderId) || !/^[0-9]{3}$/.test(statusCode) ||
      !/^[0-9]+([.][0-9]{1,2})?$/.test(grossAmount) ||
      !/^[0-9a-fA-F]{128}$/.test(signature)
    ) {
      throw new HttpError(
        400,
        "invalid_notification",
        "Notifikasi tidak valid.",
      );
    }

    const signatureValid = await verifyNotificationSignature(
      orderId,
      statusCode,
      grossAmount,
      signature,
    );
    if (!signatureValid) {
      throw new HttpError(
        401,
        "invalid_signature",
        "Tanda tangan notifikasi tidak valid.",
      );
    }

    // Signature validation alone is not trusted.  Always fetch the current
    // authoritative state from Midtrans before touching order or stock state.
    let authoritative;
    try {
      authoritative = await getMidtransStatus(orderId);
    } catch (error) {
      throw new HttpError(
        error instanceof MidtransApiError && error.httpStatus === 503
          ? 503
          : 502,
        "midtrans_status_unavailable",
        "Status Midtrans belum dapat diverifikasi.",
      );
    }

    const service = createServiceClient();
    const { error: applyError } = await service.rpc(
      "apply_midtrans_payment_status",
      applyStatusParams(authoritative),
    );
    if (applyError) {
      // A non-2xx asks Midtrans to retry.  No SQL/provider details are returned.
      throw new HttpError(
        503,
        "payment_state_not_persisted",
        "Status pembayaran belum tersimpan.",
      );
    }
    return jsonResponse({ accepted: true });
  } catch (error) {
    return errorResponse(error);
  }
});
