import {
  buildSnapPayload,
  constantTimeEqual,
  recognizedEnabledPayments,
  sha512Hex,
  verifyNotificationSignature,
} from "./midtrans.ts";

Deno.env.set("SUPABASE_URL", "https://test-project.supabase.co");

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) throw new Error(`expected ${right}, received ${left}`);
}

const checkout = {
  providerOrderId: "SB-0123456789ABCDEF0123456789ABCDEF",
  grossAmount: 21_000,
  requestedMethod: "Midtrans",
  paymentExpiresAt: "2030-01-01T00:15:00.000Z",
  customer: { first_name: "Pelanggan", email: null, phone: null },
  items: [
    { id: "bag-1", price: 10_000, quantity: 2, name: "Surprise Bag" },
    { id: "service-fee", price: 1_000, quantity: 1, name: "Biaya layanan" },
  ],
};

Deno.test("SHA-512 and notification signature use exact concatenation", async () => {
  assertEquals(
    await sha512Hex("abc"),
    "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a" +
      "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
  );
  const key = "SB-Mid-server-key";
  const orderId = "SB-0123456789ABCDEF0123456789ABCDEF";
  const statusCode = "200";
  const gross = "21000.00";
  const signature = await sha512Hex(`${orderId}${statusCode}${gross}${key}`);
  assert(
    await verifyNotificationSignature(
      orderId,
      statusCode,
      gross,
      signature,
      key,
    ),
  );
  assert(
    !await verifyNotificationSignature(
      orderId,
      statusCode,
      "21000",
      signature,
      key,
    ),
  );
});

Deno.test("constant-time comparator rejects changed values and lengths", () => {
  assert(constantTimeEqual("abc", "abc"));
  assert(!constantTimeEqual("abc", "abd"));
  assert(!constantTimeEqual("abc", "abc0"));
});

Deno.test("generic Midtrans checkout keeps provider channel selection open", () => {
  const payload = buildSnapPayload(checkout, new Date("2030-01-01T00:00:00Z"));
  assert(!Object.hasOwn(payload, "enabled_payments"));
  assertEquals(payload.transaction_details, {
    order_id: checkout.providerOrderId,
    gross_amount: 21_000,
  });
  assertEquals(payload.callbacks, {
    finish: "https://test-project.supabase.co/functions/v1/midtrans-return",
  });
  assertEquals(payload.gopay, {
    enable_callback: true,
    callback_url: "com.savebite://payment-callback/",
  });
  assertEquals(payload.shopeepay, {
    callback_url: "com.savebite://payment-callback/",
  });
  assertEquals(payload.credit_card, { secure: true });
});

Deno.test("only explicitly recognized methods restrict enabled payments", () => {
  assertEquals(recognizedEnabledPayments("GoPay"), ["gopay"]);
  assertEquals(recognizedEnabledPayments("Virtual Account BCA"), ["bca_va"]);
  assertEquals(recognizedEnabledPayments("Midtrans"), undefined);
  assertEquals(recognizedEnabledPayments("OVO"), undefined);
});

Deno.test("Snap item details must total the server gross amount exactly", () => {
  let threw = false;
  try {
    buildSnapPayload(
      { ...checkout, grossAmount: 20_999 },
      new Date("2030-01-01T00:00:00Z"),
    );
  } catch {
    threw = true;
  }
  assert(threw);
});
