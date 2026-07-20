import { keyFromJsonBundle } from "./supabase.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (actual !== expected) {
    throw new Error(`expected ${String(expected)}, received ${String(actual)}`);
  }
}

Deno.test("selects publishable key from auto-provisioned JSON bundle", () => {
  assertEquals(
    keyFromJsonBundle(
      JSON.stringify({ legacy: "ignored", current: "sb_publishable_public" }),
      "sb_publishable_",
    ),
    "sb_publishable_public",
  );
});

Deno.test("selects secret key from nested auto-provisioned JSON bundle", () => {
  assertEquals(
    keyFromJsonBundle(
      JSON.stringify({ keys: [{ value: "sb_secret_server" }] }),
      "sb_secret_",
    ),
    "sb_secret_server",
  );
  assertEquals(keyFromJsonBundle("not-json", "sb_secret_"), undefined);
});
