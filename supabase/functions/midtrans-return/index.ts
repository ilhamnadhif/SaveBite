const mobileCallback = "com.savebite://payment-callback/";

function webCallback(): string {
  const raw = Deno.env.get("MIDTRANS_WEB_RETURN_URL")?.trim();
  if (!raw) return mobileCallback;
  try {
    const url = new URL(raw);
    const isLocal = ["localhost", "127.0.0.1"].includes(url.hostname);
    // A sandbox web deployment can still run on plain HTTP (no domain yet);
    // production always returns over HTTPS.
    const sandbox = Deno.env.get("MIDTRANS_ENVIRONMENT")?.trim() === "sandbox";
    if (
      url.protocol !== "https:" &&
      !((isLocal || sandbox) && url.protocol === "http:")
    ) {
      return mobileCallback;
    }
    url.searchParams.set("savebite_payment_return", "1");
    url.hash = "";
    return url.toString();
  } catch {
    return mobileCallback;
  }
}

function securityHeaders(location: string): Record<string, string> {
  return {
    "cache-control": "no-store, max-age=0",
    "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
    location,
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
    "x-frame-options": "DENY",
  };
}

Deno.serve((request) => {
  const target = new URL(request.url).searchParams.get("target");
  const location = target === "web" ? webCallback() : mobileCallback;
  const headers = securityHeaders(location);
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: {
        ...headers,
        allow: "GET, HEAD",
        "content-type": "text/plain; charset=utf-8",
      },
    });
  }

  // Midtrans receives an HTTPS finish URL as documented, while the browser is
  // immediately handed back to the app. Query parameters from the provider are
  // deliberately ignored: the app always asks the trusted status endpoint.
  return new Response(null, { status: 302, headers });
});
