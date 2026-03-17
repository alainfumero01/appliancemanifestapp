import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const { email, password } = await request.json();
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });

  const app = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });

  // Sign in
  const { data: sessionData, error: signInError } = await app.auth.signInWithPassword({
    email,
    password
  });

  if (signInError || !sessionData.session || !sessionData.user) {
    return new Response(
      JSON.stringify({ error: signInError?.message ?? "Sign in failed." }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Generate a new session nonce — any concurrent session that holds the old
  // nonce will be kicked out on its next app launch / token refresh.
  const sessionNonce = crypto.randomUUID();

  // Persist the nonce so the iOS app can verify it hasn't been displaced
  await admin
    .from("profiles")
    .update({ session_nonce: sessionNonce })
    .eq("id", sessionData.user.id);

  // Revoke all other active refresh tokens for this account so only one
  // device can stay logged in at a time.
  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${sessionData.session.access_token}` } }
  });
  await userClient.auth.signOut({ scope: "others" });

  // Fetch the user's org
  const { data: profile } = await admin
    .from("profiles")
    .select("org_id")
    .eq("id", sessionData.user.id)
    .maybeSingle();

  return Response.json({
    access_token: sessionData.session.access_token,
    refresh_token: sessionData.session.refresh_token,
    session_nonce: sessionNonce,
    user: {
      id: sessionData.user.id,
      email: sessionData.user.email,
      org_id: profile?.org_id ?? null
    }
  });
});
