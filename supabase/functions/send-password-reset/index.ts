import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPPORT_EMAIL = "alainfumero2000@gmail.com";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const { email } = await request.json();
  if (!email || typeof email !== "string") {
    return new Response(JSON.stringify({ error: "Email is required." }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  // Generate a Supabase recovery link, redirecting to the reset page
  const { data, error } = await admin.auth.admin.generateLink({
    type: "recovery",
    email: email.trim().toLowerCase(),
    options: { redirectTo: "https://load-scan.com/reset-password" },
  });

  // Always return 200 — never reveal whether an email exists
  if (error || !data?.properties?.action_link) {
    return Response.json({ ok: true });
  }

  const resetURL = data.properties.action_link;

  const html = `<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#F0F2F8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#F0F2F8;padding:40px 16px;">
<tr><td align="center">
<table width="520" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;">

  <tr><td align="center" style="padding-bottom:28px;">
    <table cellpadding="0" cellspacing="0"><tr>
      <td style="background:#0C1340;border-radius:10px;width:36px;height:36px;text-align:center;vertical-align:middle;">
        <span style="color:#fff;font-size:18px;font-weight:800;line-height:36px;display:block;">L</span>
      </td>
      <td style="padding-left:9px;font-size:17px;font-weight:700;color:#111520;letter-spacing:-0.3px;">LoadScan</td>
    </tr></table>
  </td></tr>

  <tr><td style="background:#ffffff;border-radius:16px;border:1px solid #DDE3F0;padding:44px 40px 40px;">
    <p style="margin:0 0 6px;font-size:13px;font-weight:600;letter-spacing:0.08em;text-transform:uppercase;color:#2550DB;">Password Reset</p>
    <h1 style="margin:0 0 16px;font-size:24px;font-weight:800;color:#111520;line-height:1.2;">Reset your password</h1>
    <p style="margin:0 0 28px;font-size:15px;color:#4B5563;line-height:1.75;">Tap the button below to set a new password for your LoadScan account. This link expires in 1 hour.</p>

    <table cellpadding="0" cellspacing="0" style="margin-bottom:28px;">
      <tr><td style="background:#0C1340;border-radius:10px;padding:0;">
        <a href="${resetURL}" style="display:inline-block;padding:14px 32px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;letter-spacing:-0.2px;">Reset Password</a>
      </td></tr>
    </table>

    <p style="margin:0 0 20px;font-size:13px;color:#6B7280;line-height:1.65;">If the button doesn't work, copy and paste this link into your browser:<br/>
      <a href="${resetURL}" style="color:#2550DB;word-break:break-all;font-size:12px;">${resetURL}</a>
    </p>

    <hr style="border:none;border-top:1px solid #EEF1F8;margin:0 0 20px;"/>
    <p style="margin:0;font-size:13px;color:#9CA3AF;line-height:1.65;">If you didn't request this, you can safely ignore this email. Your password won't change.</p>
    <p style="margin:16px 0 0;font-size:12px;color:#9CA3AF;line-height:1.65;">Need help? Reply to this email or contact <a href="mailto:${SUPPORT_EMAIL}" style="color:#2550DB;text-decoration:none;">${SUPPORT_EMAIL}</a>.</p>
  </td></tr>

  <tr><td align="center" style="padding-top:20px;">
    <p style="margin:0;font-size:11px;color:#9CA3AF;">
      &copy; 2026 LoadScan &nbsp;&middot;&nbsp;
      <a href="https://load-scan.com/privacy" style="color:#9CA3AF;text-decoration:none;">Privacy</a>
    </p>
  </td></tr>

</table>
</td></tr></table>
</body></html>`;

  const text = `Reset your LoadScan password

Tap the link below to set a new password. This link expires in 1 hour.

${resetURL}

If you didn't request this, ignore this email — your password won't change.

Need help? ${SUPPORT_EMAIL}

LoadScan · https://load-scan.com`;

  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY") ?? ""}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "LoadScan <noreply@load-scan.com>",
      to: [email.trim().toLowerCase()],
      reply_to: [SUPPORT_EMAIL],
      subject: "Reset your LoadScan password",
      html,
      text,
    }),
  });

  return Response.json({ ok: true });
});
