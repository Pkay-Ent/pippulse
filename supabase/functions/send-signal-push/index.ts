import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SITE = "https://pippulse.pages.dev";
const cors = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-push-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json"
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !serviceKey || !anonKey) return reply({ error: "Server configuration is incomplete" }, 500);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  try {
    const payload = await req.json();

    // Authenticated users may register or remove only their own device subscription.
    if (payload?.action === "subscribe" || payload?.action === "unsubscribe") {
      const bearer = req.headers.get("authorization") || "";
      const token = bearer.startsWith("Bearer ") ? bearer.slice(7) : "";
      if (!token) return reply({ error: "Sign in first" }, 401);
      const auth = createClient(url, anonKey, { auth: { persistSession: false } });
      const { data: userData, error: userError } = await auth.auth.getUser(token);
      if (userError || !userData.user) return reply({ error: "Session expired. Sign in again." }, 401);
      const userId = userData.user.id;

      if (payload.action === "subscribe") {
        const sub = payload.subscription;
        if (!sub?.endpoint || !sub?.keys?.p256dh || !sub?.keys?.auth) {
          return reply({ error: "Invalid push subscription" }, 400);
        }
        const { error } = await admin.from("push_subscriptions").upsert({
          user_id: userId, endpoint: sub.endpoint, subscription: sub, updated_at: new Date().toISOString()
        }, { onConflict: "endpoint" });
        if (error) throw error;
        return reply({ ok: true });
      }

      const endpoint = String(payload.endpoint || "");
      if (!endpoint) return reply({ error: "Missing subscription endpoint" }, 400);
      const { error } = await admin.from("push_subscriptions").delete()
        .eq("user_id", userId).eq("endpoint", endpoint);
      if (error) throw error;
      return reply({ ok: true });
    }

    // Database triggers call this branch with a private Vault-held secret.
    const expected = Deno.env.get("PUSH_FUNCTION_SECRET");
    if (!expected || req.headers.get("x-push-secret") !== expected) {
      return reply({ error: "Unauthorized" }, 401);
    }
    const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
    const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    const subject = Deno.env.get("VAPID_SUBJECT") || "mailto:support.pkayenterprise@gmail.com";
    if (!publicKey || !privateKey) return reply({ error: "Push is not configured" }, 500);

    // A supplied user_id means targeted delivery. Reject malformed targets rather
    // than accidentally turning a private notification into a broadcast.
    const hasTarget = Object.prototype.hasOwnProperty.call(payload ?? {}, "user_id");
    if (hasTarget && (typeof payload.user_id !== "string" || !payload.user_id.trim())) {
      return reply({ error: "Invalid push target" }, 400);
    }
    const targetUserId = hasTarget ? payload.user_id.trim() : null;

    const title = String(payload?.title || "PipPulse Gold Signals").slice(0, 80);
    const body = String(payload?.body || "A new trading signal is available. Open PipPulse to view it.").slice(0, 180);
    const targetUrl = String(payload?.url || "/").startsWith("/") ? String(payload.url || "/") : "/";
    const notificationTag = targetUserId
      ? String(payload?.notification_id || payload?.type || "pippulse-targeted").slice(0, 100)
      : "pippulse-signal";
    webpush.setVapidDetails(subject, publicKey, privateKey);

    let subscriptionsQuery = admin.from("push_subscriptions").select("id,subscription");
    if (targetUserId) subscriptionsQuery = subscriptionsQuery.eq("user_id", targetUserId);
    const { data: rows, error } = await subscriptionsQuery;
    if (error) throw error;

    let sent = 0, removed = 0;
    for (const row of rows || []) {
      try {
        await webpush.sendNotification(row.subscription, JSON.stringify({
          title, body, url: targetUrl, tag: notificationTag
        }));
        sent++;
      } catch (err) {
        const status = (err as { statusCode?: number })?.statusCode;
        if (status === 404 || status === 410) {
          await admin.from("push_subscriptions").delete().eq("id", row.id);
          removed++;
        } else console.error("Push delivery failed:", status || "unknown");
      }
    }
    return reply({ ok: true, sent, removed, targeted: Boolean(targetUserId) });
  } catch (err) {
    console.error("Push function failed:", err instanceof Error ? err.message : "unknown");
    return reply({ error: "Push request failed" }, 500);
  }
});