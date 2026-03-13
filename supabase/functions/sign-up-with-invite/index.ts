import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const { email, password, inviteCode } = await request.json();
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });

  const app = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });

  const { data: invite, error: inviteError } = await admin
    .from("invite_codes")
    .select("id, is_active, usage_limit, usage_count")
    .eq("code", inviteCode)
    .maybeSingle();

  if (inviteError || !invite || !invite.is_active) {
    return new Response(JSON.stringify({ error: "Invite code is invalid or disabled." }), {
      status: 403,
      headers: { "Content-Type": "application/json" }
    });
  }

  if (invite.usage_limit !== null && invite.usage_count >= invite.usage_limit) {
    return new Response(JSON.stringify({ error: "Invite code usage limit has been reached." }), {
      status: 403,
      headers: { "Content-Type": "application/json" }
    });
  }

  const { error: signUpError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true
  });

  if (signUpError) {
    return new Response(JSON.stringify({ error: signUpError.message }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }

  await admin
    .from("invite_codes")
    .update({ usage_count: invite.usage_count + 1 })
    .eq("id", invite.id);

  const { data: sessionData, error: signInError } = await app.auth.signInWithPassword({
    email,
    password
  });

  if (signInError || !sessionData.session || !sessionData.user) {
    return new Response(JSON.stringify({ error: signInError?.message ?? "Sign in failed after signup." }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }

  return Response.json({
    access_token: sessionData.session.access_token,
    refresh_token: sessionData.session.refresh_token,
    user: {
      id: sessionData.user.id,
      email: sessionData.user.email
    }
  });
});
