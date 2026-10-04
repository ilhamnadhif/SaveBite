import {
  assertMidtransConfigured,
  buildQrisChargePayload,
  buildSnapPayload,
  canonicalCheckoutPaymentMethod,
  canonicalQrisPaymentMethod,
  configuredQrisAcquirer,
  configuredQrisProviderMode,
  constantTimeEqual,
  createQrisTransaction,
  createSnapTransaction,
  merchantCancellationAction,
  merchantRefundKey,
  MidtransApiError,
  parseMidtransStatus,
  parseQrisChargeResponse,
  parseSnapTransaction,
  pendingQrisPaymentUrl,
  sandboxSimulatorQrisImageUrl,
  sha512Hex,
  verifyNotificationSignature,
} from "./midtrans.ts";
import { HttpError } from "./http.ts";

Deno.env.set("SUPABASE_URL", "https://test-project.supabase.co");
Deno.env.delete("MIDTRANS_IS_PRODUCTION");
Deno.env.delete("MIDTRANS_ENABLE_SIMULATOR_HELPERS");

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

function assertMidtransConfigurationRejected(action: () => void): void {
  let failure: unknown;
  try {
    action();
  } catch (error) {
    failure = error;
  }
  assert(failure instanceof HttpError);
  assertEquals(failure.status, 500);
  assertEquals(failure.code, "midtrans_not_configured");
}

const checkout = {
  providerOrderId: "SB-0123456789ABCDEF0123456789ABCDEF",
  grossAmount: 21_000,
  paymentExpiresAt: "2030-01-01T00:15:00.000Z",
  customer: { first_name: "Pelanggan", email: null, phone: null },
  items: [
    { id: "bag-1", price: 10_000, quantity: 2, name: "Surprise Bag" },
    { id: "service-fee", price: 1_000, quantity: 1, name: "Biaya layanan" },
  ],
};

Deno.test("Midtrans environment is explicit, canonical, and fail-closed", () => {
  const previousKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  const previousEnvironment = Deno.env.get("MIDTRANS_ENVIRONMENT");
  const previousProduction = Deno.env.get("MIDTRANS_IS_PRODUCTION");
  Deno.env.set("MIDTRANS_SERVER_KEY", "test-server-key");
  try {
    Deno.env.delete("MIDTRANS_ENVIRONMENT");
    Deno.env.delete("MIDTRANS_IS_PRODUCTION");
    assertMidtransConfigurationRejected(assertMidtransConfigured);

    for (const invalidEnvironment of ["staging", "test", "prod", "SANDBOX"]) {
      Deno.env.set("MIDTRANS_ENVIRONMENT", invalidEnvironment);
      assertMidtransConfigurationRejected(assertMidtransConfigured);
    }

    Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
    Deno.env.set("MIDTRANS_IS_PRODUCTION", "true");
    assertMidtransConfigurationRejected(assertMidtransConfigured);

    Deno.env.set("MIDTRANS_ENVIRONMENT", "production");
    Deno.env.set("MIDTRANS_IS_PRODUCTION", "false");
    assertMidtransConfigurationRejected(assertMidtransConfigured);

    Deno.env.set("MIDTRANS_IS_PRODUCTION", "0");
    assertMidtransConfigurationRejected(assertMidtransConfigured);

    Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
    Deno.env.delete("MIDTRANS_IS_PRODUCTION");
    assertMidtransConfigured();
    Deno.env.set("MIDTRANS_IS_PRODUCTION", "false");
    assertMidtransConfigured();

    Deno.env.set("MIDTRANS_ENVIRONMENT", "production");
    Deno.env.set("MIDTRANS_IS_PRODUCTION", "true");
    assertMidtransConfigured();
  } finally {
    if (previousKey == null) Deno.env.delete("MIDTRANS_SERVER_KEY");
    else Deno.env.set("MIDTRANS_SERVER_KEY", previousKey);
    if (previousEnvironment == null) Deno.env.delete("MIDTRANS_ENVIRONMENT");
    else Deno.env.set("MIDTRANS_ENVIRONMENT", previousEnvironment);
    if (previousProduction == null) {
      Deno.env.delete("MIDTRANS_IS_PRODUCTION");
    } else {
      Deno.env.set("MIDTRANS_IS_PRODUCTION", previousProduction);
    }
  }
});

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

Deno.test("Snap payload is QRIS-only with a server-owned bounded expiry", () => {
  const sevenMinutePayload = buildSnapPayload(
    { ...checkout, paymentExpiresAt: "2030-01-01T00:07:59.999Z" },
    new Date("2030-01-01T00:00:00.000Z"),
  );
  assertEquals(sevenMinutePayload.enabled_payments, ["other_qris"]);
  assertEquals(sevenMinutePayload.expiry, {
    start_time: "2030-01-01 00:00:00 +0000",
    duration: 7,
    unit: "minutes",
  });
  assertEquals(sevenMinutePayload.callbacks, {
    finish: "https://test-project.supabase.co/functions/v1/midtrans-return",
  });
  assertEquals(sevenMinutePayload.transaction_details, {
    order_id: checkout.providerOrderId,
    gross_amount: checkout.grossAmount,
  });
  assert(!Object.hasOwn(sevenMinutePayload, "payment_type"));
  assert(!Object.hasOwn(sevenMinutePayload, "qris"));
  assert(!Object.hasOwn(sevenMinutePayload, "gopay"));

  const cappedPayload = buildSnapPayload(
    { ...checkout, paymentExpiresAt: "2030-01-01T00:30:59.999Z" },
    new Date("2030-01-01T00:00:00.000Z"),
  );
  assertEquals(cappedPayload.expiry, {
    start_time: "2030-01-01 00:00:00 +0000",
    duration: 15,
    unit: "minutes",
  });
});

Deno.test("hosted MIDTRANS Snap payload offers every method and returns to the web app", () => {
  const payload = buildSnapPayload(
    { ...checkout, paymentMethod: "MIDTRANS" },
    new Date("2030-01-01T00:00:00.000Z"),
  );
  assert(!Object.hasOwn(payload, "enabled_payments"));
  assertEquals(payload.callbacks, {
    finish:
      "https://test-project.supabase.co/functions/v1/midtrans-return?target=web",
  });
  assertEquals(payload.expiry, {
    start_time: "2030-01-01 00:00:00 +0000",
    duration: 15,
    unit: "minutes",
  });
  assertEquals(payload.transaction_details, {
    order_id: checkout.providerOrderId,
    gross_amount: checkout.grossAmount,
  });
  assert(!Object.hasOwn(payload, "payment_type"));

  // An explicit QRIS checkout keeps the Other-QRIS-only app contract.
  const qrisPayload = buildSnapPayload(
    { ...checkout, paymentMethod: "QRIS" },
    new Date("2030-01-01T00:00:00.000Z"),
  );
  assertEquals(qrisPayload.enabled_payments, ["other_qris"]);
  assertEquals(qrisPayload.callbacks, {
    finish: "https://test-project.supabase.co/functions/v1/midtrans-return",
  });
});

Deno.test("Snap parser accepts current and legacy official redirects with independent IDs", () => {
  const token = "11111111-1111-4111-8111-111111111111";
  const redirectId = "22222222-2222-4222-8222-222222222222";
  assertEquals(
    parseSnapTransaction(
      {
        token,
        redirect_url:
          `https://app.sandbox.midtrans.com/snap/v4/redirection/${redirectId}`,
      },
      "https://app.sandbox.midtrans.com",
    ),
    {
      token,
      redirect_url:
        `https://app.sandbox.midtrans.com/snap/v4/redirection/${redirectId}`,
    },
  );
  assertEquals(
    parseSnapTransaction(
      {
        token,
        redirect_url:
          `https://app.sandbox.midtrans.com/snap/v3/redirection/${redirectId}`,
      },
      "https://app.sandbox.midtrans.com",
    ),
    {
      token,
      redirect_url:
        `https://app.sandbox.midtrans.com/snap/v3/redirection/${redirectId}`,
    },
  );
  assertEquals(
    parseSnapTransaction(
      {
        token,
        redirect_url:
          `https://app.sandbox.midtrans.com/snap/v2/vtweb/${redirectId}`,
      },
      "https://app.sandbox.midtrans.com",
    ),
    {
      token,
      redirect_url:
        `https://app.sandbox.midtrans.com/snap/v2/vtweb/${redirectId}`,
    },
  );
});

Deno.test("Snap parser rejects untrusted redirect origins and URL decorations", () => {
  const token = "11111111-1111-4111-8111-111111111111";
  const redirectId = "22222222-2222-4222-8222-222222222222";
  const invalidUrls = [
    `https://evil.example/snap/v3/redirection/${redirectId}`,
    `https://app.sandbox.midtrans.com/snap/v3/redirection/${redirectId}?next=evil`,
    `https://app.sandbox.midtrans.com/snap/v3/redirection/${redirectId}#fragment`,
    `https://user:password@app.sandbox.midtrans.com/snap/v3/redirection/${redirectId}`,
    `https://app.sandbox.midtrans.com:8443/snap/v3/redirection/${redirectId}`,
    `https://app.sandbox.midtrans.com/snap/v3/checkout/${redirectId}`,
    `https://app.sandbox.midtrans.com/snap/v2/vtweb/short`,
  ];
  for (const redirectUrl of invalidUrls) {
    let rejected = false;
    try {
      parseSnapTransaction(
        { token, redirect_url: redirectUrl },
        "https://app.sandbox.midtrans.com",
      );
    } catch (error) {
      rejected = error instanceof MidtransApiError &&
        error.safeCode === "midtrans_create_invalid_snap_url";
    }
    assert(rejected, `expected Snap URL to be rejected: ${redirectUrl}`);
  }
});

Deno.test("Snap create sends authenticated idempotent server request and parses 201", async () => {
  const originalFetch = globalThis.fetch;
  const previousKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  const previousEnvironment = Deno.env.get("MIDTRANS_ENVIRONMENT");
  const serverKey = "sandbox-snap-server-key";
  const token = "11111111-1111-4111-8111-111111111111";
  const redirectId = "22222222-2222-4222-8222-222222222222";
  let requestUrl = "";
  let requestMethod = "";
  let requestHeaders = new Headers();
  let requestBody: unknown;
  Deno.env.set("MIDTRANS_SERVER_KEY", serverKey);
  Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
  globalThis.fetch = (input: string | URL | Request, init?: RequestInit) => {
    requestUrl = input instanceof Request ? input.url : String(input);
    requestMethod = init?.method ?? "GET";
    requestHeaders = new Headers(init?.headers);
    requestBody = JSON.parse(String(init?.body));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          token,
          redirect_url:
            `https://app.sandbox.midtrans.com/snap/v3/redirection/${redirectId}`,
        }),
        { status: 201, headers: { "content-type": "application/json" } },
      ),
    );
  };

  try {
    const payload = buildSnapPayload(
      checkout,
      new Date("2030-01-01T00:00:00.000Z"),
    );
    assertEquals(await createSnapTransaction(payload), {
      token,
      redirect_url:
        `https://app.sandbox.midtrans.com/snap/v3/redirection/${redirectId}`,
    });
    assertEquals(
      requestUrl,
      "https://app.sandbox.midtrans.com/snap/v1/transactions",
    );
    assertEquals(requestMethod, "POST");
    assertEquals(
      requestHeaders.get("Authorization"),
      `Basic ${btoa(`${serverKey}:`)}`,
    );
    assertEquals(
      requestHeaders.get("Idempotency-Key"),
      checkout.providerOrderId,
    );
    assertEquals(
      requestHeaders.get("X-Override-Notification"),
      "https://test-project.supabase.co/functions/v1/midtrans-webhook",
    );
    assertEquals(requestHeaders.get("Content-Type"), "application/json");
    assertEquals(requestBody, payload);
  } finally {
    globalThis.fetch = originalFetch;
    if (previousKey == null) Deno.env.delete("MIDTRANS_SERVER_KEY");
    else Deno.env.set("MIDTRANS_SERVER_KEY", previousKey);
    if (previousEnvironment == null) Deno.env.delete("MIDTRANS_ENVIRONMENT");
    else Deno.env.set("MIDTRANS_ENVIRONMENT", previousEnvironment);
  }
});

Deno.test("Snap create retries ambiguous timeout and 202 with one idempotency key", async () => {
  const originalFetch = globalThis.fetch;
  const previousKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  const previousEnvironment = Deno.env.get("MIDTRANS_ENVIRONMENT");
  const token = "11111111-1111-4111-8111-111111111111";
  const redirectId = "22222222-2222-4222-8222-222222222222";
  const seenKeys: Array<string | null> = [];
  let calls = 0;
  Deno.env.set("MIDTRANS_SERVER_KEY", "sandbox-retry-server-key");
  Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
  globalThis.fetch = (_input: string | URL | Request, init?: RequestInit) => {
    calls++;
    seenKeys.push(new Headers(init?.headers).get("Idempotency-Key"));
    if (calls === 1) {
      return Promise.reject(new TypeError("ambiguous network failure"));
    }
    if (calls === 2) {
      return Promise.resolve(
        new Response(JSON.stringify({ status_code: "202" }), {
          status: 202,
          headers: { "content-type": "application/json" },
        }),
      );
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({
          token,
          redirect_url:
            `https://app.sandbox.midtrans.com/snap/v3/redirection/${redirectId}`,
        }),
        { status: 201, headers: { "content-type": "application/json" } },
      ),
    );
  };

  try {
    const result = await createSnapTransaction(
      buildSnapPayload(checkout, new Date("2030-01-01T00:00:00.000Z")),
    );
    assertEquals(result, {
      token,
      redirect_url:
        `https://app.sandbox.midtrans.com/snap/v3/redirection/${redirectId}`,
    });
    assertEquals(calls, 3);
    assertEquals(seenKeys, [
      checkout.providerOrderId,
      checkout.providerOrderId,
      checkout.providerOrderId,
    ]);
  } finally {
    globalThis.fetch = originalFetch;
    if (previousKey == null) Deno.env.delete("MIDTRANS_SERVER_KEY");
    else Deno.env.set("MIDTRANS_SERVER_KEY", previousKey);
    if (previousEnvironment == null) Deno.env.delete("MIDTRANS_ENVIRONMENT");
    else Deno.env.set("MIDTRANS_ENVIRONMENT", previousEnvironment);
  }
});

Deno.test("Snap create converts non-201 responses to safe provider errors", async () => {
  const originalFetch = globalThis.fetch;
  const previousKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  const previousEnvironment = Deno.env.get("MIDTRANS_ENVIRONMENT");
  const serverKey = "sandbox-snap-secret-never-logged";
  Deno.env.set("MIDTRANS_SERVER_KEY", serverKey);
  Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
  try {
    for (
      const response of [
        new Response(
          JSON.stringify({
            status_code: "401",
            status_message: `credential ${serverKey} rejected`,
          }),
          { status: 401, headers: { "content-type": "application/json" } },
        ),
        new Response(JSON.stringify({ status_code: "402" }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      ]
    ) {
      globalThis.fetch = () => Promise.resolve(response);
      let failure: unknown;
      try {
        await createSnapTransaction(
          buildSnapPayload(
            checkout,
            new Date("2030-01-01T00:00:00.000Z"),
          ),
        );
      } catch (error) {
        failure = error;
      }
      assert(failure instanceof MidtransApiError);
      assert(
        failure.safeCode === "midtrans_create_http_401" ||
          failure.safeCode === "midtrans_create_http_402",
      );
      assert(!failure.message.includes(serverKey));
      assert(!failure.message.includes("credential"));
    }
  } finally {
    globalThis.fetch = originalFetch;
    if (previousKey == null) Deno.env.delete("MIDTRANS_SERVER_KEY");
    else Deno.env.set("MIDTRANS_SERVER_KEY", previousKey);
    if (previousEnvironment == null) Deno.env.delete("MIDTRANS_ENVIRONMENT");
    else Deno.env.set("MIDTRANS_ENVIRONMENT", previousEnvironment);
  }
});

Deno.test("native QRIS payload uses Core charge contract and bounded expiry", () => {
  const payload = buildQrisChargePayload(
    checkout,
    new Date("2030-01-01T00:00:00Z"),
  );
  assertEquals(payload.payment_type, "qris");
  assertEquals(payload.transaction_details, {
    order_id: checkout.providerOrderId,
    gross_amount: 21_000,
  });
  assertEquals(payload.qris, { acquirer: "gopay" });
  assertEquals(payload.custom_expiry, {
    order_time: "2030-01-01 00:00:00 +0000",
    expiry_duration: 15,
    unit: "minute",
  });
  assert(!Object.hasOwn(payload, "callbacks"));
  assert(!Object.hasOwn(payload, "enabled_payments"));
});

Deno.test("QRIS acquirer sandbox is explicit and allow-listed", () => {
  const previous = Deno.env.get("MIDTRANS_QRIS_ACQUIRER");
  try {
    Deno.env.set("MIDTRANS_QRIS_ACQUIRER", "AIRPAY SHOPEE");
    assertEquals(configuredQrisAcquirer(), "airpay shopee");
    const payload = buildQrisChargePayload(
      checkout,
      new Date("2030-01-01T00:00:00Z"),
      configuredQrisAcquirer(),
    );
    assertEquals(payload.qris, { acquirer: "airpay shopee" });

    Deno.env.set("MIDTRANS_QRIS_ACQUIRER", "untrusted-acquirer");
    let rejected = false;
    try {
      configuredQrisAcquirer();
    } catch {
      rejected = true;
    }
    assert(rejected);
  } finally {
    if (previous == null) Deno.env.delete("MIDTRANS_QRIS_ACQUIRER");
    else Deno.env.set("MIDTRANS_QRIS_ACQUIRER", previous);
  }
});

Deno.test("QRIS provider mode is explicit and allow-listed", () => {
  const previous = Deno.env.get("MIDTRANS_QRIS_PROVIDER_MODE");
  try {
    Deno.env.set("MIDTRANS_QRIS_PROVIDER_MODE", "GOPAY");
    assertEquals(configuredQrisProviderMode(), "gopay");

    Deno.env.set("MIDTRANS_QRIS_PROVIDER_MODE", "snap");
    let rejected = false;
    try {
      configuredQrisProviderMode();
    } catch {
      rejected = true;
    }
    assert(rejected);
  } finally {
    if (previous == null) Deno.env.delete("MIDTRANS_QRIS_PROVIDER_MODE");
    else Deno.env.set("MIDTRANS_QRIS_PROVIDER_MODE", previous);
  }
});

Deno.test("GoPay Core payload exposes only a native QRIS checkout contract", () => {
  const payload = buildQrisChargePayload(
    checkout,
    new Date("2030-01-01T00:00:00Z"),
    "gopay",
    "gopay",
  );
  assertEquals(payload.payment_type, "gopay");
  assertEquals(payload.gopay, { enable_callback: false });
  assert(!Object.hasOwn(payload, "qris"));
  assert(!Object.hasOwn(payload, "callbacks"));
  assert(!Object.hasOwn(payload, "enabled_payments"));
});

Deno.test("checkout accepts only QRIS and returns the canonical DB value", () => {
  assertEquals(canonicalQrisPaymentMethod("qris"), "QRIS");
  assertEquals(canonicalQrisPaymentMethod("  QRIS  "), "QRIS");
  for (
    const method of [
      "Midtrans",
      "GoPay",
      "other_qris",
      "qris-sandbox",
      null,
      1,
    ]
  ) {
    let rejected = false;
    try {
      canonicalQrisPaymentMethod(method);
    } catch (error) {
      rejected = error instanceof Error &&
        "code" in error && error.code === "invalid_payment_method";
    }
    assert(rejected);
  }
});

Deno.test("checkout accepts QRIS or the hosted MIDTRANS checkout", () => {
  assertEquals(canonicalCheckoutPaymentMethod("qris"), "QRIS");
  assertEquals(canonicalCheckoutPaymentMethod("  QRIS  "), "QRIS");
  assertEquals(canonicalCheckoutPaymentMethod("Midtrans"), "MIDTRANS");
  assertEquals(canonicalCheckoutPaymentMethod(" MIDTRANS "), "MIDTRANS");
  for (
    const method of ["GoPay", "other_qris", "bank_transfer", "", null, 1]
  ) {
    let rejected = false;
    try {
      canonicalCheckoutPaymentMethod(method);
    } catch (error) {
      rejected = error instanceof HttpError && error.status === 400 &&
        error.code === "invalid_payment_method";
    }
    assert(rejected, String(method));
  }
});

Deno.test("native QRIS response extracts only canonical generate-qr-code action", () => {
  const transactionId = "0d8178e1-c6c7-4ab4-81a6-893be9d924ab";
  const result = parseQrisChargeResponse(
    {
      status_code: 201,
      order_id: checkout.providerOrderId,
      gross_amount: "21000.00",
      currency: "IDR",
      payment_type: "qris",
      transaction_status: "pending",
      transaction_id: transactionId,
      acquirer: "gopay",
      actions: [
        {
          name: "generate-qr-code",
          method: "GET",
          url:
            `https://api.sandbox.midtrans.com/v2/qris/${transactionId}/qr-code`,
        },
        {
          name: "generate-qr-code-v2",
          method: "GET",
          url: "https://api.sandbox.midtrans.com/v4/qris/aspi/qr-code",
        },
      ],
    },
    checkout.providerOrderId,
    checkout.grossAmount,
    "https://api.sandbox.midtrans.com",
  );

  assertEquals(result, {
    transaction_id: transactionId,
    payment_qr_url:
      `https://api.sandbox.midtrans.com/v2/qris/${transactionId}/qr-code`,
  });

  const airpayResult = parseQrisChargeResponse(
    {
      status_code: "201",
      order_id: checkout.providerOrderId,
      gross_amount: "21000.00",
      currency: "IDR",
      payment_type: "qris",
      transaction_status: "pending",
      transaction_id: transactionId,
      acquirer: "airpay shopee",
      actions: [{
        name: "generate-qr-code",
        method: "GET",
        url:
          `https://api.sandbox.midtrans.com/v2/qris/${transactionId}/qr-code`,
      }],
    },
    checkout.providerOrderId,
    checkout.grossAmount,
    "https://api.sandbox.midtrans.com",
    "qris",
    "airpay shopee",
  );
  assertEquals(airpayResult, result);
});

Deno.test("GoPay Core response accepts only its canonical QRIS image action", () => {
  const transactionId = "0d8178e1-c6c7-4ab4-81a6-893be9d924ab";
  const result = parseQrisChargeResponse(
    {
      status_code: "201",
      order_id: checkout.providerOrderId,
      gross_amount: "21000.00",
      currency: "IDR",
      payment_type: "gopay",
      transaction_status: "pending",
      transaction_id: transactionId,
      actions: [
        {
          name: "generate-qr-code",
          method: "GET",
          url:
            `https://api.sandbox.midtrans.com/v2/gopay/${transactionId}/qr-code`,
        },
        {
          name: "deeplink-redirect",
          method: "GET",
          url: "gojek://gopay/merchanttransfer?untrusted_for_native_ui=true",
        },
      ],
    },
    checkout.providerOrderId,
    checkout.grossAmount,
    "https://api.sandbox.midtrans.com",
    "gopay",
    null,
  );
  assertEquals(result, {
    transaction_id: transactionId,
    payment_qr_url:
      `https://api.sandbox.midtrans.com/v2/gopay/${transactionId}/qr-code`,
  });
});

Deno.test("GoPay Core QRIS response rejects mismatched type, rail, or acquirer", () => {
  const transactionId = "0d8178e1-c6c7-4ab4-81a6-893be9d924ab";
  const base = {
    status_code: "201",
    order_id: checkout.providerOrderId,
    gross_amount: "21000.00",
    currency: "IDR",
    payment_type: "gopay",
    transaction_status: "pending",
    transaction_id: transactionId,
  };
  const validAction = {
    name: "generate-qr-code",
    method: "GET",
    url: `https://api.sandbox.midtrans.com/v2/gopay/${transactionId}/qr-code`,
  };
  for (
    const body of [
      { ...base, payment_type: "qris", actions: [validAction] },
      {
        ...base,
        actions: [{
          ...validAction,
          url:
            `https://api.sandbox.midtrans.com/v2/qris/${transactionId}/qr-code`,
        }],
      },
      { ...base, acquirer: "airpay shopee", actions: [validAction] },
    ]
  ) {
    let rejected = false;
    try {
      parseQrisChargeResponse(
        body,
        checkout.providerOrderId,
        checkout.grossAmount,
        "https://api.sandbox.midtrans.com",
        "gopay",
        null,
      );
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});

Deno.test("native QRIS response rejects foreign or mismatched QR actions", () => {
  const transactionId = "0d8178e1-c6c7-4ab4-81a6-893be9d924ab";
  const base = {
    status_code: "201",
    order_id: checkout.providerOrderId,
    gross_amount: "21000.00",
    currency: "IDR",
    payment_type: "qris",
    transaction_status: "pending",
    transaction_id: transactionId,
    acquirer: "gopay",
  };
  for (
    const actions of [
      [{
        name: "generate-qr-code",
        method: "GET",
        url: `https://evil.example/v2/qris/${transactionId}/qr-code`,
      }],
      [{
        name: "generate-qr-code",
        method: "POST",
        url:
          `https://api.sandbox.midtrans.com/v2/qris/${transactionId}/qr-code`,
      }],
      [],
    ]
  ) {
    let rejected = false;
    try {
      parseQrisChargeResponse(
        { ...base, actions },
        checkout.providerOrderId,
        checkout.grossAmount,
        "https://api.sandbox.midtrans.com",
      );
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});

Deno.test("pending QRIS status derives only the canonical active-environment URL", () => {
  const previousKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  const previousEnvironment = Deno.env.get("MIDTRANS_ENVIRONMENT");
  Deno.env.set("MIDTRANS_SERVER_KEY", "sandbox-server-key");
  Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
  const transactionId = "0d8178e1-c6c7-4ab4-81a6-893be9d924ab";
  const status = {
    order_id: checkout.providerOrderId,
    transaction_status: "pending",
    fraud_status: null,
    status_code: "201",
    gross_amount: "21000.00",
    transaction_id: transactionId,
    payment_type: "qris",
    status_timestamp: null,
  };
  try {
    assertEquals(
      pendingQrisPaymentUrl(status),
      `https://api.sandbox.midtrans.com/v2/qris/${transactionId}/qr-code`,
    );
    assertEquals(
      pendingQrisPaymentUrl({ ...status, payment_type: "gopay" }),
      `https://api.sandbox.midtrans.com/v2/gopay/${transactionId}/qr-code`,
    );
    assertEquals(
      pendingQrisPaymentUrl({ ...status, transaction_status: "settlement" }),
      null,
    );
  } finally {
    if (previousKey == null) Deno.env.delete("MIDTRANS_SERVER_KEY");
    else Deno.env.set("MIDTRANS_SERVER_KEY", previousKey);
    if (previousEnvironment == null) Deno.env.delete("MIDTRANS_ENVIRONMENT");
    else Deno.env.set("MIDTRANS_ENVIRONMENT", previousEnvironment);
  }
});

Deno.test("simulator QR image is exposed only for explicit sandbox pending QRIS", () => {
  const previousEnvironment = Deno.env.get("MIDTRANS_ENVIRONMENT");
  const previousProduction = Deno.env.get("MIDTRANS_IS_PRODUCTION");
  const previousHelpers = Deno.env.get("MIDTRANS_ENABLE_SIMULATOR_HELPERS");
  const transactionId = "0d8178e1-c6c7-4ab4-81a6-893be9d924ab";
  const status = {
    order_id: checkout.providerOrderId,
    transaction_status: "pending",
    fraud_status: null,
    status_code: "201",
    gross_amount: "21000.00",
    transaction_id: transactionId,
    payment_type: "qris",
    status_timestamp: null,
  };
  try {
    Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
    Deno.env.delete("MIDTRANS_IS_PRODUCTION");
    Deno.env.delete("MIDTRANS_ENABLE_SIMULATOR_HELPERS");
    assertEquals(sandboxSimulatorQrisImageUrl(status), null);
    Deno.env.set("MIDTRANS_ENABLE_SIMULATOR_HELPERS", "false");
    assertEquals(sandboxSimulatorQrisImageUrl(status), null);
    Deno.env.set("MIDTRANS_ENABLE_SIMULATOR_HELPERS", "TRUE");
    assertEquals(sandboxSimulatorQrisImageUrl(status), null);
    Deno.env.set("MIDTRANS_ENABLE_SIMULATOR_HELPERS", "true");
    assertEquals(
      sandboxSimulatorQrisImageUrl(status),
      `https://api.sandbox.midtrans.com/v2/qris/${transactionId}/qr-code`,
    );
    assertEquals(
      sandboxSimulatorQrisImageUrl({ ...status, payment_type: "gopay" }),
      null,
    );
    assertEquals(
      sandboxSimulatorQrisImageUrl({
        ...status,
        transaction_status: "settlement",
      }),
      null,
    );
    assertEquals(
      sandboxSimulatorQrisImageUrl({
        ...status,
        transaction_id: "not-a-uuid",
      }),
      null,
    );

    Deno.env.set("MIDTRANS_ENVIRONMENT", "production");
    assertEquals(sandboxSimulatorQrisImageUrl(status), null);

    Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
    Deno.env.set("MIDTRANS_IS_PRODUCTION", "true");
    assertMidtransConfigurationRejected(() =>
      sandboxSimulatorQrisImageUrl(status)
    );
  } finally {
    if (previousEnvironment == null) Deno.env.delete("MIDTRANS_ENVIRONMENT");
    else Deno.env.set("MIDTRANS_ENVIRONMENT", previousEnvironment);
    if (previousProduction == null) {
      Deno.env.delete("MIDTRANS_IS_PRODUCTION");
    } else {
      Deno.env.set("MIDTRANS_IS_PRODUCTION", previousProduction);
    }
    if (previousHelpers == null) {
      Deno.env.delete("MIDTRANS_ENABLE_SIMULATOR_HELPERS");
    } else {
      Deno.env.set("MIDTRANS_ENABLE_SIMULATOR_HELPERS", previousHelpers);
    }
  }
});

Deno.test("provider event time uses official Midtrans fields", () => {
  const parsed = parseMidtransStatus({
    order_id: checkout.providerOrderId,
    transaction_status: "settlement",
    status_code: 200,
    gross_amount: "21000.00",
    transaction_time: "2030-01-01 00:01:00 +0000",
    settlement_time: "2030-01-01 00:02:00 +0000",
  }, checkout.providerOrderId);
  assertEquals(parsed.status_timestamp, "2030-01-01 00:02:00 +0000");
});

Deno.test("merchant cancellation selects cancel before settlement and refund after", () => {
  assertEquals(merchantCancellationAction("pending"), "cancel");
  assertEquals(merchantCancellationAction("authorize"), "cancel");
  assertEquals(merchantCancellationAction("capture"), "cancel");
  assertEquals(merchantCancellationAction("settlement"), "refund");
  assertEquals(merchantCancellationAction("cancel"), "complete");
  assertEquals(merchantCancellationAction("refund"), "complete");
  assertEquals(merchantCancellationAction("partial_refund"), "review");
  assertEquals(merchantCancellationAction("chargeback"), "review");
});

Deno.test("merchant full refund uses one deterministic provider-safe key", () => {
  assertEquals(
    merchantRefundKey(checkout.providerOrderId),
    "SB_CANCEL_0123456789ABCDEF0123456789ABCDEF",
  );
  let rejected = false;
  try {
    merchantRefundKey("not-a-provider-order");
  } catch {
    rejected = true;
  }
  assert(rejected);
});

Deno.test("QRIS item details must total the server gross amount exactly", () => {
  let threw = false;
  try {
    buildQrisChargePayload(
      { ...checkout, grossAmount: 20_999 },
      new Date("2030-01-01T00:00:00Z"),
    );
  } catch {
    threw = true;
  }
  assert(threw);
});

Deno.test("provider error code in an HTTP 2xx envelope stays a provider failure", async () => {
  const originalFetch = globalThis.fetch;
  const previousKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  const previousEnvironment = Deno.env.get("MIDTRANS_ENVIRONMENT");
  Deno.env.set("MIDTRANS_SERVER_KEY", "sandbox-server-key");
  Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
  try {
    for (const statusCode of ["402", 402]) {
      globalThis.fetch = () =>
        Promise.resolve(
          new Response(JSON.stringify({ status_code: statusCode }), {
            status: 200,
            headers: { "content-type": "application/json" },
          }),
        );
      let failure: unknown;
      try {
        await createQrisTransaction(
          buildQrisChargePayload(
            checkout,
            new Date("2030-01-01T00:00:00Z"),
          ),
          checkout.providerOrderId,
        );
      } catch (error) {
        failure = error;
      }
      assert(failure instanceof MidtransApiError);
      assertEquals(failure.safeCode, "midtrans_create_http_402");
    }
  } finally {
    globalThis.fetch = originalFetch;
    if (previousKey == null) Deno.env.delete("MIDTRANS_SERVER_KEY");
    else Deno.env.set("MIDTRANS_SERVER_KEY", previousKey);
    if (previousEnvironment == null) Deno.env.delete("MIDTRANS_ENVIRONMENT");
    else Deno.env.set("MIDTRANS_ENVIRONMENT", previousEnvironment);
  }
});

Deno.test("duplicate QRIS charge recovers canonical URL from authoritative status", async () => {
  const originalFetch = globalThis.fetch;
  const previousKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  const previousEnvironment = Deno.env.get("MIDTRANS_ENVIRONMENT");
  Deno.env.set("MIDTRANS_SERVER_KEY", "sandbox-server-key");
  Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
  const transactionId = "ce0a3584-5a0c-4049-ad88-5590a96be4fe";
  const requests: string[] = [];
  let chargeHeaders = new Headers();
  globalThis.fetch = (input: string | URL | Request, init?: RequestInit) => {
    const url = input instanceof Request ? input.url : String(input);
    requests.push(url);
    if (url.endsWith("/v2/charge")) {
      chargeHeaders = new Headers(init?.headers);
      return Promise.resolve(
        new Response(
          JSON.stringify({ status_code: "406" }),
          { status: 406, headers: { "content-type": "application/json" } },
        ),
      );
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({
          status_code: "201",
          order_id: checkout.providerOrderId,
          gross_amount: "21000.00",
          payment_type: "qris",
          transaction_status: "pending",
          transaction_id: transactionId,
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  };

  try {
    const payload = buildQrisChargePayload(
      checkout,
      new Date("2030-01-01T00:00:00Z"),
    );
    const result = await createQrisTransaction(
      payload,
      checkout.providerOrderId,
    );
    assertEquals(requests, [
      "https://api.sandbox.midtrans.com/v2/charge",
      `https://api.sandbox.midtrans.com/v2/${checkout.providerOrderId}/status`,
    ]);
    assertEquals(
      chargeHeaders.get("Idempotency-Key"),
      checkout.providerOrderId,
    );
    assertEquals(
      chargeHeaders.get("X-Override-Notification"),
      "https://test-project.supabase.co/functions/v1/midtrans-webhook",
    );
    assertEquals(result, {
      transaction_id: transactionId,
      payment_qr_url:
        `https://api.sandbox.midtrans.com/v2/qris/${transactionId}/qr-code`,
    });
  } finally {
    globalThis.fetch = originalFetch;
    if (previousKey == null) Deno.env.delete("MIDTRANS_SERVER_KEY");
    else Deno.env.set("MIDTRANS_SERVER_KEY", previousKey);
    if (previousEnvironment == null) Deno.env.delete("MIDTRANS_ENVIRONMENT");
    else Deno.env.set("MIDTRANS_ENVIRONMENT", previousEnvironment);
  }
});

Deno.test("ambiguous QRIS charge timeout recovers from authoritative status", async () => {
  const originalFetch = globalThis.fetch;
  const previousKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  const previousEnvironment = Deno.env.get("MIDTRANS_ENVIRONMENT");
  Deno.env.set("MIDTRANS_SERVER_KEY", "sandbox-server-key");
  Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
  const transactionId = "9f07920a-6145-4d1e-9fc2-66e6fd6bc6fc";
  const requests: string[] = [];
  globalThis.fetch = (input: string | URL | Request) => {
    const url = input instanceof Request ? input.url : String(input);
    requests.push(url);
    if (url.endsWith("/v2/charge")) {
      return Promise.reject(new TypeError("simulated connection loss"));
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({
          status_code: "201",
          order_id: checkout.providerOrderId,
          gross_amount: "21000.00",
          payment_type: "qris",
          transaction_status: "pending",
          transaction_id: transactionId,
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  };

  try {
    const result = await createQrisTransaction(
      buildQrisChargePayload(
        checkout,
        new Date("2030-01-01T00:00:00Z"),
      ),
      checkout.providerOrderId,
    );
    assertEquals(requests, [
      "https://api.sandbox.midtrans.com/v2/charge",
      `https://api.sandbox.midtrans.com/v2/${checkout.providerOrderId}/status`,
    ]);
    assertEquals(result, {
      transaction_id: transactionId,
      payment_qr_url:
        `https://api.sandbox.midtrans.com/v2/qris/${transactionId}/qr-code`,
    });
  } finally {
    globalThis.fetch = originalFetch;
    if (previousKey == null) Deno.env.delete("MIDTRANS_SERVER_KEY");
    else Deno.env.set("MIDTRANS_SERVER_KEY", previousKey);
    if (previousEnvironment == null) Deno.env.delete("MIDTRANS_ENVIRONMENT");
    else Deno.env.set("MIDTRANS_ENVIRONMENT", previousEnvironment);
  }
});

Deno.test("ambiguous GoPay QRIS charge recovers its canonical native QR", async () => {
  const originalFetch = globalThis.fetch;
  const previousKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  const previousEnvironment = Deno.env.get("MIDTRANS_ENVIRONMENT");
  Deno.env.set("MIDTRANS_SERVER_KEY", "sandbox-server-key");
  Deno.env.set("MIDTRANS_ENVIRONMENT", "sandbox");
  const transactionId = "8f07920a-6145-4d1e-9fc2-66e6fd6bc6fc";
  const requests: string[] = [];
  globalThis.fetch = (input: string | URL | Request) => {
    const url = input instanceof Request ? input.url : String(input);
    requests.push(url);
    if (url.endsWith("/v2/charge")) {
      return Promise.reject(new TypeError("simulated connection loss"));
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({
          status_code: "201",
          order_id: checkout.providerOrderId,
          gross_amount: "21000.00",
          payment_type: "gopay",
          transaction_status: "pending",
          transaction_id: transactionId,
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  };

  try {
    const result = await createQrisTransaction(
      buildQrisChargePayload(
        checkout,
        new Date("2030-01-01T00:00:00Z"),
        "gopay",
        "gopay",
      ),
      checkout.providerOrderId,
    );
    assertEquals(requests, [
      "https://api.sandbox.midtrans.com/v2/charge",
      `https://api.sandbox.midtrans.com/v2/${checkout.providerOrderId}/status`,
    ]);
    assertEquals(result, {
      transaction_id: transactionId,
      payment_qr_url:
        `https://api.sandbox.midtrans.com/v2/gopay/${transactionId}/qr-code`,
    });
  } finally {
    globalThis.fetch = originalFetch;
    if (previousKey == null) Deno.env.delete("MIDTRANS_SERVER_KEY");
    else Deno.env.set("MIDTRANS_SERVER_KEY", previousKey);
    if (previousEnvironment == null) Deno.env.delete("MIDTRANS_ENVIRONMENT");
    else Deno.env.set("MIDTRANS_ENVIRONMENT", previousEnvironment);
  }
});
