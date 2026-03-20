import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const JSON_HEADERS = {
  "Content-Type": "application/json",
  ...CORS_HEADERS,
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function normalizeEmail(value: string) {
  return value.trim().toLowerCase();
}

function isValidEmail(value: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: CORS_HEADERS });
  }

  let body: Record<string, unknown>;

  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const honeypot = typeof body.website === "string" ? body.website.trim() : "";
  if (honeypot) {
    return json({ ok: true, alreadyJoined: false });
  }

  const rawEmail = typeof body.email === "string" ? body.email : "";
  const email = normalizeEmail(rawEmail);

  if (!email) {
    return json({ error: "Email is required." }, 400);
  }

  if (!isValidEmail(email)) {
    return json({ error: "Enter a valid email address." }, 400);
  }

  const source = typeof body.source === "string" && body.source.trim()
    ? body.source.trim().slice(0, 120)
    : "website_waitlist";
  const referrer = typeof body.referrer === "string" && body.referrer.trim()
    ? body.referrer.trim().slice(0, 500)
    : request.headers.get("Referer")?.slice(0, 500) ?? null;
  const userAgent = request.headers.get("User-Agent")?.slice(0, 500) ?? null;

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const { error } = await admin
    .from("waitlist_signups")
    .insert({
      email,
      source,
      referrer,
      user_agent: userAgent,
    });

  if (error?.code === "23505") {
    return json({ ok: true, alreadyJoined: true });
  }

  if (error) {
    console.error("join-waitlist insert failed", error);
    return json({ error: "We couldn't save your email right now. Please try again." }, 500);
  }

  return json({ ok: true, alreadyJoined: false });
});
