import { createClient } from "jsr:@supabase/supabase-js@2";

async function sendWelcomeEmail(email: string) {
  const firstName = email.split("@")[0];

  const html = `<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#F0F2F8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#F0F2F8;padding:40px 16px;">
<tr><td align="center">
<table width="520" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;">

  <!-- Logo -->
  <tr><td align="center" style="padding-bottom:28px;">
    <table cellpadding="0" cellspacing="0"><tr>
      <td style="background:#0C1340;border-radius:10px;width:36px;height:36px;text-align:center;vertical-align:middle;">
        <span style="color:#fff;font-size:18px;font-weight:800;line-height:36px;display:block;">L</span>
      </td>
      <td style="padding-left:9px;font-size:17px;font-weight:700;color:#111520;letter-spacing:-0.3px;">LoadScan</td>
    </tr></table>
  </td></tr>

  <!-- Card -->
  <tr><td style="background:#ffffff;border-radius:16px;border:1px solid #DDE3F0;padding:44px 40px 40px;">
    <p style="margin:0 0 6px;font-size:13px;font-weight:600;letter-spacing:0.08em;text-transform:uppercase;color:#2550DB;">Welcome aboard</p>
    <h1 style="margin:0 0 20px;font-size:26px;font-weight:800;color:#111520;line-height:1.2;">You're in, ${firstName}.</h1>
    <p style="margin:0 0 32px;font-size:15px;color:#4B5563;line-height:1.75;">LoadScan is ready to go. Scan appliance stickers, build manifests, and price your loads — all from your phone.</p>

    <!-- Divider -->
    <hr style="border:none;border-top:1px solid #EEF1F8;margin:0 0 28px;"/>

    <p style="margin:0;font-size:13px;color:#9CA3AF;line-height:1.7;">
      Questions? Reply to this email or reach us at
      <a href="mailto:support@load-scan.com" style="color:#2550DB;text-decoration:none;">support@load-scan.com</a>
    </p>
  </td></tr>

  <!-- Footer -->
  <tr><td align="center" style="padding-top:20px;">
    <p style="margin:0;font-size:11px;color:#9CA3AF;">
      &copy; 2026 LoadScan &nbsp;&middot;&nbsp;
      <a href="https://load-scan.com/privacy" style="color:#9CA3AF;text-decoration:none;">Privacy</a>
    </p>
  </td></tr>

</table>
</td></tr></table>
</body></html>`;

  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY") ?? ""}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "LoadScan <noreply@load-scan.com>",
      to: [email],
      subject: "Welcome to LoadScan",
      html,
      text: `Welcome to LoadScan\n\nYou're in, ${firstName}. LoadScan is ready to go — scan appliance stickers, build manifests, and price your loads from your phone.\n\nQuestions? support@load-scan.com\n\nLoadScan · https://load-scan.com`,
    }),
  });
}

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

  // If an invite code is provided, validate it; otherwise sign up as individual.
  let invite: { id: string; org_id: string | null; usage_count: number; usage_limit: number | null } | null = null;

  if (inviteCode) {
    const { data, error: inviteError } = await admin
      .from("invite_codes")
      .select("id, is_active, usage_limit, usage_count, org_id")
      .eq("code", inviteCode)
      .maybeSingle();

    if (inviteError || !data || !data.is_active) {
      return new Response(JSON.stringify({ error: "Invite code is invalid or disabled." }), {
        status: 403,
        headers: { "Content-Type": "application/json" }
      });
    }

    if (data.usage_limit !== null && data.usage_count >= data.usage_limit) {
      return new Response(JSON.stringify({ error: "Invite code usage limit has been reached." }), {
        status: 403,
        headers: { "Content-Type": "application/json" }
      });
    }

    invite = data;
  }

  // Create the user (auto-confirmed — no verification email)
  const { data: createdUserData, error: signUpError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true
  });

  if (signUpError || !createdUserData.user) {
    return new Response(JSON.stringify({ error: signUpError?.message ?? "User creation failed." }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }

  const userID = createdUserData.user.id;
  const sessionNonce = crypto.randomUUID();

  // Determine org membership
  let orgID: string;

  if (invite?.org_id) {
    orgID = invite.org_id;
    await admin.from("org_members").insert({ org_id: orgID, user_id: userID, role: "member" });
  } else {
    const { data: newOrg } = await admin
      .from("organizations")
      .insert({
        name: email.split("@")[0],
        owner_id: userID,
        subscription_type: "individual",
        seat_limit: 1
      })
      .select("id")
      .single();

    orgID = newOrg!.id;
    await admin.from("org_members").insert({ org_id: orgID, user_id: userID, role: "owner" });
  }

  // Attach org + session nonce to the profile
  await admin
    .from("profiles")
    .update({ org_id: orgID, session_nonce: sessionNonce })
    .eq("id", userID);

  // Increment invite code usage if one was used
  if (invite) {
    await admin
      .from("invite_codes")
      .update({ usage_count: invite.usage_count + 1 })
      .eq("id", invite.id);
  }

  // Sign in to get a session
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

  // Fire-and-forget welcome email (don't block the response)
  sendWelcomeEmail(email).catch(() => {});

  return Response.json({
    access_token: sessionData.session.access_token,
    refresh_token: sessionData.session.refresh_token,
    session_nonce: sessionNonce,
    user: {
      id: sessionData.user.id,
      email: sessionData.user.email,
      org_id: orgID
    }
  });
});
