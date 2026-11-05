// Supabase Edge Function: username-login
// JWT verification must be OFF: users call this before they have a session.
// Uses service role only to resolve the username, then signs in with the anon key.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const SITE = "https://pippulse.pages.dev";
const cors = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed." }, 405);
  try {
    const input = await req.json();
    const username = String(input?.username || "").trim();
    const password = String(input?.password || "");
    if (!/^[A-Za-z0-9_]{3,20}$/.test(username) || !password || password.length > 72)
      return reply({ error: "Username or password is incorrect." }, 401);
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anon || !service) {
      console.error("username-login missing Supabase environment configuration");
      return reply({ error: "Login is temporarily unavailable. Please try again." }, 500);
    }
    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile, error: lookupError } = await admin.from("profiles")
      .select("email").ilike("username", username).maybeSingle();
    if (lookupError) {
      console.error("username-login lookup failed:", lookupError.message);
      return reply({ error: "Login is temporarily unavailable. Please try again." }, 500);
    }
    if (!profile?.email) return reply({ error: "Username or password is incorrect." }, 401);
    const auth = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await auth.auth.signInWithPassword({ email: profile.email, password });
    if (error || !data.session) return reply({ error: "Username or password is incorrect." }, 401);
    return reply({ session: { access_token: data.session.access_token, refresh_token: data.session.refresh_token } });
  } catch (e) {
    console.error("username-login request failed:", e instanceof Error ? e.message : "Unknown error");
    return reply({ error: "Invalid login request." }, 400);
  }
});
