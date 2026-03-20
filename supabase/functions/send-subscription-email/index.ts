import { createClient } from "jsr:@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM_EMAIL = "LoadScan <noreply@load-scan.com>";
const SUPPORT_EMAIL = "alainfumero2000@gmail.com";

const PLAN_NAMES: Record<string, string> = {
  "com.alainfumero.loadscan.individual.monthly": "Individual",
  "com.alainfumero.loadscan.enterprise5.monthly": "Enterprise 5",
  "com.alainfumero.loadscan.enterprise10.monthly": "Enterprise 10",
  "com.alainfumero.loadscan.enterprise15.monthly": "Enterprise 15",
};

function displayPlanName(planKey: string): string {
  const normalized = planKey.trim().toLowerCase();
  if (normalized && PLAN_NAMES[normalized]) {
    return PLAN_NAMES[normalized];
  }

  const cleaned = planKey
    .replace(/^com\.alainfumero\.loadscan\./i, "")
    .replace(/\.monthly$/i, "")
    .replace(/\.annual$/i, "")
    .replace(/[._-]+/g, " ")
    .trim();

  if (!cleaned) return "Membership";

  return cleaned
    .split(" ")
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function buildEmail(email: string, planKey: string): string {
  const planName = displayPlanName(planKey);

  return `<!DOCTYPE html><html><head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#F0F2F8;font-family:-apple-system,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#F0F2F8;padding:40px 16px;">
<tr><td align="center">
<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">
  <tr><td align="center" style="padding-bottom:24px;">
    <table cellpadding="0" cellspacing="0"><tr>
      <td style="background:#0C1340;border-radius:10px;width:38px;height:38px;text-align:center;vertical-align:middle;">
        <span style="color:#fff;font-size:20px;font-weight:800;line-height:38px;display:block;">L</span>
      </td>
      <td style="padding-left:10px;font-size:19px;font-weight:700;color:#111520;">LoadScan</td>
    </tr></table>
  </td></tr>
  <tr><td style="background:#fff;border-radius:16px;border:1px solid #DDE3F0;padding:44px 40px 36px;">
    <p style="margin:0 0 10px;font-size:11px;font-weight:600;letter-spacing:0.1em;text-transform:uppercase;color:#2550DB;">Subscription Confirmed</p>
    <h1 style="margin:0 0 18px;font-size:26px;font-weight:800;color:#111520;line-height:1.15;">You're all set, ${planName}.</h1>
    <p style="margin:0 0 20px;font-size:15px;color:#4B5563;line-height:1.7;">Thanks for subscribing to <strong>LoadScan ${planName}</strong>. Your account has been upgraded and all premium features are now active.</p>
    <table cellpadding="0" cellspacing="0" style="width:100%;margin-bottom:24px;">
      <tr>
        <td style="background:#F8F9FC;border:1px solid #E5E9F4;border-radius:12px;padding:16px 20px;">
          <p style="margin:0 0 4px;font-size:11px;font-weight:600;letter-spacing:0.06em;text-transform:uppercase;color:#9CA3AF;">Plan</p>
          <p style="margin:0;font-size:16px;font-weight:700;color:#111520;">LoadScan ${planName}</p>
        </td>
      </tr>
    </table>
    <p style="margin:0 0 20px;font-size:14px;color:#6B7280;line-height:1.65;">Your subscription is managed through the Apple App Store. To manage or cancel, go to <strong>Settings &rarr; Apple ID &rarr; Subscriptions</strong> on your iPhone.</p>
    <hr style="border:none;border-top:1px solid #E5E9F4;margin:28px 0;"/>
    <p style="margin:0;font-size:12px;color:#9CA3AF;line-height:1.7;">Questions? Reply to this email or reach us at <a href="mailto:${SUPPORT_EMAIL}" style="color:#2550DB;">${SUPPORT_EMAIL}</a></p>
  </td></tr>
  <tr><td align="center" style="padding-top:20px;">
    <p style="margin:0;font-size:12px;color:#9CA3AF;">2026 LoadScan &nbsp;&middot;&nbsp; <a href="https://load-scan.com/privacy" style="color:#9CA3AF;text-decoration:none;">Privacy Policy</a></p>
  </td></tr>
</table>
</td></tr></table>
</body></html>`;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Verify the caller is an authenticated Supabase user
  const authorization = request.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } }
  );

  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let plan = "Pro";
  try {
    const body = await request.json();
    plan = body.plan ?? "Membership";
  } catch (_) {
    // plan stays as default
  }

  const email = user.email ?? "";
  if (!email) {
    return new Response(JSON.stringify({ error: "No email on account" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [email],
      reply_to: [SUPPORT_EMAIL],
      subject: `Your LoadScan ${displayPlanName(plan)} subscription is active`,
      html: buildEmail(email, plan),
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    console.error("Resend error:", err);
    return new Response(JSON.stringify({ error: "Failed to send email" }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
