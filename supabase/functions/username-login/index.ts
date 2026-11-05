// Supabase Edge Function: username-login
// JWT verification must be OFF: users call this before they have a session.
// Accepts either an email address or a username, then authenticates through Supabase Auth.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SITE = "https://pippulse.pages.dev";
const cors = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed." }, 405);

  try {
    const input = await req.json();
    const identifier = String(input?.username || input?.identifier || "").trim();
    const password = String(input?.password || "");

    if (!identifier || !password || password.length > 72 || identifier.length > 254) {
      return reply({ error: "Username/email or password is incorrect." }, 401);
    }

    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anon || !service) {
      console.error("username-login missing Supabase environment configuration");
      return reply({ error: "Login is temporarily unavailable. Please try again." }, 500);
    }

    let email = "";
    if (identifier.includes("@")) {
      // Email login: pass the supplied address directly to Supabase Auth.
      email = identifier.toLowerCase();
    } else {
      // Username login: resolve the account email privately on the server.
      if (!/^[A-Za-z0-9_]{3,20}$/.test(identifier)) {
        return reply({ error: "Username/email or password is incorrect." }, 401);
      }
      const admin = createClient(url, service, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data: profile, error: lookupError } = await admin
        .from("profiles")
        .select("email")
        .ilike("username", identifier)
        .maybeSingle();

      if (lookupError) {
        console.error("username-login lookup failed:", lookupError.message);
        return reply({ error: "Login is temporarily unavailable. Please try again." }, 500);
      }
      if (!profile?.email) {
        return reply({ error: "Username/email or password is incorrect." }, 401);
      }
      email = profile.email;
    }

    const auth = createClient(url, anon, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await auth.auth.signInWithPassword({ email, password });
    if (error || !data.session) {
      return reply({ error: "Username/email or password is incorrect." }, 401);
    }

    return reply({
      session: {
        access_token: data.session.access_token,
        refresh_token: data.session.refresh_token,
      },
    });
  } catch (e) {
    console.error("username-login request failed:", e instanceof Error ? e.message : "Unknown error");
    return reply({ error: "Invalid login request." }, 400);
  }
});
