import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "https://pippulse.pages.dev",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-push-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json"
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  const expected = Deno.env.get("PUSH_FUNCTION_SECRET");
  if (!expected || req.headers.get("x-push-secret") !== expected) {
    return reply({ error: "Unauthorized" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const subject = Deno.env.get("VAPID_SUBJECT") || "mailto:support.pkayenterprise@gmail.com";
  if (!url || !serviceKey || !publicKey || !privateKey) {
    console.error("Push function is missing required secrets.");
    return reply({ error: "Push is not configured" }, 500);
  }

  try {
    const payload = await req.json();
    const title = String(payload?.title || "PipPulse Gold Signals").slice(0, 80);
    const body = String(payload?.body || "A new trading signal is available. Open PipPulse to view it.").slice(0, 180);
    const targetUrl = String(payload?.url || "/").startsWith("/") ? String(payload.url || "/") : "/";
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    webpush.setVapidDetails(subject, publicKey, privateKey);

    const { data: rows, error } = await admin.from("push_subscriptions").select("id,subscription");
    if (error) throw error;

    let sent = 0, removed = 0;
    for (const row of rows || []) {
      try {
        await webpush.sendNotification(row.subscription, JSON.stringify({
          title, body, url: targetUrl, tag: "pippulse-signal"
        }));
        sent++;
      } catch (err) {
        const status = (err as { statusCode?: number })?.statusCode;
        if (status === 404 || status === 410) {
          await admin.from("push_subscriptions").delete().eq("id", row.id);
          removed++;
        } else {
          console.error("Push delivery failed:", status || "unknown");
        }
      }
    }
    return reply({ ok: true, sent, removed });
  } catch (err) {
    console.error("Push dispatch failed:", err instanceof Error ? err.message : "unknown");
    return reply({ error: "Push dispatch failed" }, 500);
  }
});