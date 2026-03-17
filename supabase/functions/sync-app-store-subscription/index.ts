import { createClient } from "jsr:@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";

const PLAN_CONFIG: Record<string, { subscription_type: "individual" | "enterprise"; seat_limit: number; extra_seats: number }> = {
  "com.alainfumero.loadscan.individual.monthly":  { subscription_type: "individual",  seat_limit: 1,  extra_seats: 0  },
  "com.alainfumero.loadscan.enterprise5.monthly": { subscription_type: "enterprise",  seat_limit: 6,  extra_seats: 5  },
  "com.alainfumero.loadscan.enterprise10.monthly":{ subscription_type: "enterprise",  seat_limit: 11, extra_seats: 10 },
  "com.alainfumero.loadscan.enterprise15.monthly":{ subscription_type: "enterprise",  seat_limit: 16, extra_seats: 15 },
};

function unauthorized() {
  return new Response(JSON.stringify({ error: "Unauthorized" }), {
    status: 401, headers: { "Content-Type": "application/json" },
  });
}

function randomCode() {
  return `TEAM-${crypto.randomUUID().split("-")[0].toUpperCase()}`;
}

async function sendInviteEmail(email: string, codes: string[], seats: number) {
  const codeRows = codes.map(c =>
    `<tr><td style="padding:8px 12px;font-family:monospace;font-size:15px;font-weight:700;color:#111520;background:#F0F4FF;border-radius:6px;letter-spacing:0.05em;">${c}</td></tr>`
  ).join("<tr><td style='height:6px'></td></tr>");

  const html = `<!DOCTYPE html><html><head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#F0F2F8;font-family:-apple-system,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#F0F2F8;padding:40px 16px;">
<tr><td align="center"><table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">
  <tr><td align="center" style="padding-bottom:24px;">
    <table cellpadding="0" cellspacing="0"><tr>
      <td style="background:#0C1340;border-radius:10px;width:38px;height:38px;text-align:center;vertical-align:middle;"><span style="color:#fff;font-size:20px;font-weight:800;line-height:38px;display:block;">L</span></td>
      <td style="padding-left:10px;font-size:19px;font-weight:700;color:#111520;">LoadScan</td>
    </tr></table>
  </td></tr>
  <tr><td style="background:#fff;border-radius:16px;border:1px solid #DDE3F0;padding:44px 40px 36px;">
    <p style="margin:0 0 10px;font-size:11px;font-weight:600;letter-spacing:0.1em;text-transform:uppercase;color:#2550DB;">Enterprise Plan Active</p>
    <h1 style="margin:0 0 18px;font-size:26px;font-weight:800;color:#111520;line-height:1.15;">Your team invite codes are ready</h1>
    <p style="margin:0 0 24px;font-size:15px;color:#4B5563;line-height:1.7;">Your LoadScan Enterprise plan includes <strong>${seats} team seat${seats !== 1 ? "s" : ""}</strong>. Share the codes below with your teammates — each code can be used once during signup.</p>
    <table cellpadding="0" cellspacing="0" style="width:100%;margin-bottom:24px;">
      ${codeRows}
    </table>
    <p style="margin:0 0 16px;font-size:14px;color:#6B7280;line-height:1.65;">Teammates enter their code on the signup screen in the LoadScan app. Each code is single-use and ties their account to your team.</p>
    <hr style="border:none;border-top:1px solid #E5E9F4;margin:28px 0;"/>
    <p style="margin:0;font-size:12px;color:#9CA3AF;line-height:1.7;">You can also generate new invite links anytime from <strong>Settings → Membership</strong> in the app.<br/>Questions? <a href="mailto:support@load-scan.com" style="color:#2550DB;">support@load-scan.com</a></p>
  </td></tr>
  <tr><td align="center" style="padding-top:20px;">
    <p style="margin:0;font-size:12px;color:#9CA3AF;">2026 LoadScan &nbsp;&middot;&nbsp; <a href="https://load-scan.com/privacy" style="color:#9CA3AF;text-decoration:none;">Privacy Policy</a></p>
  </td></tr>
</table></td></tr></table>
</body></html>`;

  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "LoadScan <noreply@load-scan.com>",
      to: [email],
      subject: `Your LoadScan team invite codes (${seats} seat${seats !== 1 ? "s" : ""})`,
      html,
    }),
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const token = (request.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
  if (!token) return unauthorized();

  const { productID } = await request.json();
  const plan = PLAN_CONFIG[String(productID ?? "")];
  if (!plan) {
    return new Response(JSON.stringify({ error: "Unknown App Store product." }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const { data: authData } = await admin.auth.getUser(token);
  const user = authData.user;
  if (!user) return unauthorized();

  const { data: profile } = await admin
    .from("profiles")
    .select("org_id")
    .eq("id", user.id)
    .maybeSingle();

  if (!profile?.org_id) {
    return new Response(JSON.stringify({ error: "No organization found for user." }), {
      status: 404, headers: { "Content-Type": "application/json" },
    });
  }

  const expiresAt = new Date();
  expiresAt.setMonth(expiresAt.getMonth() + 1);

  await admin
    .from("organizations")
    .update({
      app_store_product_id: productID,
      subscription_type: plan.subscription_type,
      subscription_status: "active",
      billing_platform: "app_store",
      subscription_expires_at: expiresAt.toISOString(),
      seat_limit: plan.seat_limit,
      extra_seats: plan.extra_seats,
    })
    .eq("id", profile.org_id);

  // For enterprise plans, auto-generate one invite code per team seat and email them
  const generatedCodes: string[] = [];
  if (plan.extra_seats > 0 && user.email) {
    // Deactivate any old invite codes for this org first
    await admin
      .from("invite_codes")
      .update({ is_active: false })
      .eq("org_id", profile.org_id);

    // Generate one code per seat (each single-use)
    for (let i = 0; i < plan.extra_seats; i++) {
      const code = randomCode();
      await admin.from("invite_codes").insert({
        code,
        is_active: true,
        usage_limit: 1,
        usage_count: 0,
        created_by: user.id,
        org_id: profile.org_id,
      });
      generatedCodes.push(code);
    }

    // Email all codes to the owner
    await sendInviteEmail(user.email, generatedCodes, plan.extra_seats);
  }

  const { data: org } = await admin
    .from("organizations")
    .select("id,name,owner_id,subscription_type,billing_platform,subscription_status,app_store_product_id,subscription_expires_at,seat_limit,extra_seats,trial_manifest_limit,trial_manifests_used")
    .eq("id", profile.org_id)
    .single();

  const { count: memberCount } = await admin
    .from("org_members")
    .select("user_id", { count: "exact", head: true })
    .eq("org_id", profile.org_id);

  return Response.json({
    orgID: org.id,
    organizationName: org.name,
    ownerID: org.owner_id,
    subscriptionType: org.subscription_type,
    billingPlatform: org.billing_platform,
    subscriptionStatus: org.subscription_status,
    appStoreProductID: org.app_store_product_id,
    subscriptionExpiresAt: org.subscription_expires_at,
    seatLimit: org.seat_limit,
    extraSeats: org.extra_seats,
    trialManifestLimit: org.trial_manifest_limit,
    trialManifestsUsed: org.trial_manifests_used,
    memberCount: memberCount ?? 0,
    isOwner: org.owner_id === user.id,
    inviteCodes: generatedCodes,
  });
});
