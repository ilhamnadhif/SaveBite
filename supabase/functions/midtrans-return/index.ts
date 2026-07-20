const appCallback = "com.savebite://payment-callback/";

const securityHeaders = {
  "cache-control": "no-store, max-age=0",
  "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
  "location": appCallback,
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
};

Deno.serve((request) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: {
        ...securityHeaders,
        allow: "GET, HEAD",
        "content-type": "text/plain; charset=utf-8",
      },
    });
  }

  // Midtrans receives an HTTPS finish URL as documented, while the browser is
  // immediately handed back to the app. Query parameters from the provider are
  // deliberately ignored: the app always asks the trusted status endpoint.
  return new Response(null, { status: 302, headers: securityHeaders });
});
