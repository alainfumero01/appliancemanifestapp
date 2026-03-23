import { createClient } from "jsr:@supabase/supabase-js@2";

const DEFAULT_ORIGIN = "https://load-scan.com";
const ALLOWED_ORIGINS = new Set([
  "https://load-scan.com",
  "https://www.load-scan.com",
  "https://loadscan.app",
]);

function corsHeaders(request: Request) {
  const requestOrigin = request.headers.get("Origin")?.trim();
  const allowOrigin = requestOrigin && ALLOWED_ORIGINS.has(requestOrigin)
    ? requestOrigin
    : DEFAULT_ORIGIN;

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Vary": "Origin",
  };
}

Deno.serve(async (request) => {
  const headers = corsHeaders(request);

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers });
  }

  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers });
  }

  let accessToken: string;
  let password: string;

  try {
    const body = await request.json();
    accessToken = body.access_token;
    password = body.password;
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid request body." }),
      { status: 400, headers: { "Content-Type": "application/json", ...headers } }
    );
  }

  if (!accessToken || typeof accessToken !== "string") {
    return new Response(
      JSON.stringify({ error: "Missing access_token." }),
      { status: 400, headers: { "Content-Type": "application/json", ...headers } }
    );
  }

  if (!password || typeof password !== "string" || password.length < 8) {
    return new Response(
      JSON.stringify({ error: "Password must be at least 8 characters." }),
      { status: 400, headers: { "Content-Type": "application/json", ...headers } }
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  // Verify the access token is valid by fetching the user it belongs to
  const userClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser(accessToken);

  if (userError || !user) {
    return new Response(
      JSON.stringify({ error: "This link is invalid or has expired." }),
      { status: 401, headers: { "Content-Type": "application/json", ...headers } }
    );
  }

  // Update the password using the service role key (admin)
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { error: updateError } = await admin.auth.admin.updateUserById(user.id, { password });

  if (updateError) {
    return new Response(
      JSON.stringify({ error: "Failed to update password. Please request a new reset link." }),
      { status: 500, headers: { "Content-Type": "application/json", ...headers } }
    );
  }

  return new Response(
    JSON.stringify({ success: true }),
    { status: 200, headers: { "Content-Type": "application/json", ...headers } }
  );
});
