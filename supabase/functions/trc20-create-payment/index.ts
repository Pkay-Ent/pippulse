import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { HDKey } from "npm:@scure/bip32@2.4.0";
import { secp256k1 } from "npm:@noble/curves@2.4.0/secp256k1.js";
import { sha256 } from "npm:@noble/hashes@2.4.0/sha2.js";
import { keccak_256 } from "npm:@noble/hashes@2.4.0/sha3.js";

const SITE = "https://pippulse.pages.dev";
const EXPECTED_INDEX_0 = "TQT5WzNBJjpSQEMgvjkCfBHhwftKZPPW4K";
const EXPECTED_INDEX_1 = "TNDc7gHf21hqS8Xp7KBRBPRa5JE6YvQzSb";
const TRON_BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const PLAN_IDS = new Set(["monthly", "five_month", "lifetime"]);

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function base58Encode(bytes: Uint8Array): string {
  let value = 0n;
  for (const byte of bytes) value = (value << 8n) | BigInt(byte);

  let encoded = "";
  while (value > 0n) {
    const remainder = Number(value % 58n);
    encoded = TRON_BASE58[remainder] + encoded;
    value /= 58n;
  }

  let leadingZeroes = 0;
  while (leadingZeroes < bytes.length && bytes[leadingZeroes] === 0) {
    leadingZeroes++;
  }

  return "1".repeat(leadingZeroes) + encoded;
}

function tronAddressFromPublicKey(compressedPublicKey: Uint8Array): string {
  if (compressedPublicKey.length !== 33) {
    throw new Error("Invalid derived public key");
  }

  const point = secp256k1.Point.fromBytes(compressedPublicKey);
  const uncompressed = point.toBytes(false);
  if (uncompressed.length !== 65 || uncompressed[0] !== 4) {
    throw new Error("Could not serialize derived public key");
  }

  // TRON uses the last 20 bytes of Keccak-256(X || Y), prefixed with 0x41.
  const accountHash = keccak_256(uncompressed.slice(1)).slice(-20);
  const payload = new Uint8Array(21);
  payload[0] = 0x41;
  payload.set(accountHash, 1);

  const firstHash = sha256(payload);
  const checksum = sha256(firstHash).slice(0, 4);
  const checked = new Uint8Array(25);
  checked.set(payload);
  checked.set(checksum, 21);

  return base58Encode(checked);
}

function deriveAddress(branch: HDKey, index: number): string {
  const child = branch.deriveChild(index);
  if (child.privateKey !== null) {
    throw new Error("The configured derivation key must be public-only");
  }
  const publicKey = child.publicKey;
  if (!publicKey) throw new Error("Could not derive a public key");
  return tronAddressFromPublicKey(publicKey);
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function publicFailure(reason: string) {
  const messages: Record<string, string> = {
    INVALID_PLAN: "Please select a valid subscription plan.",
    INVALID_CHECKOUT: "The checkout details are invalid. Please try again.",
    PENDING_SUBSCRIPTION: "You already have a subscription waiting to start.",
    LIFETIME_ACTIVE: "Your Lifetime subscription is already active.",
    LOWER_PLAN_NOT_ALLOWED: "You cannot switch to a lower plan while your current plan is active.",
    TOO_MANY_PENDING: "You have reached the limit of pending payments. Please finish or wait for an existing checkout.",
    CHECKOUT_CONFLICT: "This checkout could not be completed. Please start a new checkout.",
  };
  return messages[reason] || "We could not create your checkout. Please try again.";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "Method not allowed." }, 405);

  const origin = req.headers.get("origin");
  if (origin && origin !== SITE) return reply({ error: "Origin not allowed." }, 403);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    console.error("trc20-create-payment: Supabase environment is incomplete");
    return reply({ error: "Checkout is temporarily unavailable." }, 500);
  }

  const authorization = req.headers.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return reply({ error: "Please sign in before starting checkout." }, 401);

  try {
    const authClient = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: authError } = await authClient.auth.getUser(match[1]);
    if (authError || !userData.user) {
      return reply({ error: "Your session has expired. Please sign in again." }, 401);
    }
    const userId = userData.user.id;

    let input: Record<string, unknown>;
    try {
      input = await req.json();
    } catch {
      return reply({ error: "Invalid checkout request." }, 400);
    }

    const plan = typeof input.plan === "string" ? input.plan : "";
    const checkoutId = input.checkout_id;
    if (!PLAN_IDS.has(plan) || !isUuid(checkoutId)) {
      return reply({ error: "Please select a valid plan and start checkout again." }, 400);
    }

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Idempotency fast path: a retry reuses the original payment and address
    // without consuming another derivation index.
    const { data: existingPayment, error: existingError } = await admin
      .from("payments")
      .select("id,user_id,plan,amount,currency,crypto_expires_at")
      .eq("crypto_checkout_id", checkoutId)
      .maybeSingle();

    if (existingError) throw new Error("Could not check checkout status");
    if (existingPayment) {
      if (existingPayment.user_id !== userId) {
        return reply({ error: "This checkout ID is already in use. Start a new checkout." }, 409);
      }
      const { data: existingAddress, error: addressError } = await admin
        .from("crypto_deposit_addresses")
        .select("address")
        .eq("payment_id", existingPayment.id)
        .maybeSingle();
      if (addressError || !existingAddress?.address) {
        throw new Error("The existing checkout address could not be loaded");
      }
      return reply({
        success: true,
        duplicate: true,
        payment_id: existingPayment.id,
        plan: existingPayment.plan,
        amount: existingPayment.amount,
        currency: existingPayment.currency,
        network: "trc20",
        deposit_address: existingAddress.address,
        expires_at: existingPayment.crypto_expires_at,
      });
    }

    // The extended public key is read only by this trusted server function.
    const { data: xpub, error: xpubError } = await admin.rpc("get_pippulse_trc20_xpub");
    if (xpubError || typeof xpub !== "string" || !xpub.trim()) {
      console.error("trc20-create-payment: public derivation key is unavailable");
      return reply({ error: "TRC20 checkout is temporarily unavailable." }, 503);
    }

    let branch: HDKey;
    try {
      branch = HDKey.fromExtendedKey(xpub.trim());
    } catch {
      console.error("trc20-create-payment: configured derivation key is invalid");
      return reply({ error: "TRC20 checkout is temporarily unavailable." }, 503);
    }

    // Fail closed unless this is the verified public branch xpub at m/44'/195'/0'/0.
    if (branch.privateKey !== null || branch.depth !== 4 || branch.index !== 0) {
      console.error("trc20-create-payment: derivation key is not the expected public branch");
      return reply({ error: "TRC20 checkout is temporarily unavailable." }, 503);
    }

    // Verify the xpub against the already-tested business wallet and first customer address.
    if (
      deriveAddress(branch, 0) !== EXPECTED_INDEX_0 ||
      deriveAddress(branch, 1) !== EXPECTED_INDEX_1
    ) {
      console.error("trc20-create-payment: derivation key verification failed");
      return reply({ error: "TRC20 checkout is temporarily unavailable." }, 503);
    }

    // The sequence is service-role-only. Failed attempts may consume an index;
    // an index is never reused.
    const { data: reservedIndex, error: reserveError } = await admin.rpc(
      "reserve_trc20_derivation_index",
    );
    if (reserveError) throw new Error("Could not reserve a deposit address index");

    const index = Number(reservedIndex);
    if (!Number.isSafeInteger(index) || index < 1 || index > 0x7fffffff) {
      console.error("trc20-create-payment: reserved derivation index is out of range");
      return reply({ error: "TRC20 checkout is temporarily unavailable." }, 503);
    }

    const depositAddress = deriveAddress(branch, index);
    if (!/^T[1-9A-HJ-NP-Za-km-z]{33}$/.test(depositAddress)) {
      throw new Error("Derived deposit address failed validation");
    }

    const { data: result, error: createError } = await admin.rpc("create_trc20_payment", {
      p_user_id: userId,
      p_plan: plan,
      p_derivation_index: index,
      p_address: depositAddress,
      p_checkout_id: checkoutId,
    });

    if (createError) throw new Error("Could not create the TRC20 payment");

    if (!result || result.success !== true) {
      const reason = typeof result?.reason === "string" ? result.reason : "UNKNOWN";
      const status = reason === "TOO_MANY_PENDING" || reason === "PENDING_SUBSCRIPTION" ? 409 : 400;
      return reply({ error: publicFailure(reason), reason }, status);
    }

    if (typeof result.payment_id !== "string" || typeof result.deposit_address !== "string") {
      throw new Error("Payment creation returned incomplete checkout details");
    }

    // Always return the persisted expiry, not a newly calculated approximation.
    // This also covers concurrent retries where the SQL RPC returns an existing checkout.
    const { data: payment, error: paymentReadError } = await admin
      .from("payments")
      .select("plan,amount,currency,crypto_expires_at")
      .eq("id", result.payment_id)
      .eq("user_id", userId)
      .maybeSingle();

    if (paymentReadError || !payment?.crypto_expires_at) {
      throw new Error("Could not load the persisted checkout expiry");
    }

    return reply({
      success: true,
      duplicate: result.duplicate === true,
      payment_id: result.payment_id,
      plan: payment.plan,
      amount: payment.amount,
      currency: payment.currency,
      network: "trc20",
      deposit_address: result.deposit_address,
      expires_at: payment.crypto_expires_at,
    });
  } catch (error) {
    console.error(
      "trc20-create-payment failed:",
      error instanceof Error ? error.message : "unknown error",
    );
    return reply({ error: "We could not create your TRC20 checkout. Please try again." }, 500);
  }
});
