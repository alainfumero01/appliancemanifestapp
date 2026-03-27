import { createClient } from "jsr:@supabase/supabase-js@2";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function fallbackOrgName(email: string | null | undefined) {
  const localPart = (email ?? "").split("@")[0]?.trim();
  return localPart && localPart.length > 0 ? localPart : "LoadScan User";
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const { inviteCode } = await request.json().catch(() => ({ inviteCode: null }));

  const token = request.headers.get("X-User-Token")?.trim()
    ?? (request.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
  if (!token) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: authData } = await admin.auth.getUser(token);
  const user = authData.user;
  if (!user) {
    return json({ error: "Unauthorized" }, 401);
  }

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("org_id")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError) {
    return json({ error: profileError.message }, 400);
  }

  if (profile?.org_id) {
    return json({ org_id: profile.org_id, created: false });
  }

  let orgID: string | null = null;

  if (typeof inviteCode === "string" && inviteCode.trim().length > 0) {
    const normalizedCode = inviteCode.trim().toUpperCase().replace(/\s+/g, "");
    const { data: invite, error: inviteError } = await admin
      .from("invite_codes")
      .select("id, is_active, usage_limit, usage_count, org_id")
      .eq("code", normalizedCode)
      .maybeSingle();

    if (inviteError || !invite || !invite.is_active || !invite.org_id) {
      return json({ error: "Invite code is invalid or disabled." }, 403);
    }

    if (invite.usage_limit !== null && invite.usage_count >= invite.usage_limit) {
      return json({ error: "Invite code usage limit has been reached." }, 403);
    }

    const { error: membershipError } = await admin
      .from("org_members")
      .insert({ org_id: invite.org_id, user_id: user.id, role: "member" });

    if (membershipError) {
      return json({ error: membershipError.message }, 400);
    }

    const nextUsageCount = invite.usage_count + 1;
    const { error: inviteUpdateError } = await admin
      .from("invite_codes")
      .update({
        usage_count: nextUsageCount,
        is_active: invite.usage_limit === null ? true : nextUsageCount < invite.usage_limit,
      })
      .eq("id", invite.id);

    if (inviteUpdateError) {
      return json({ error: inviteUpdateError.message }, 400);
    }

    orgID = invite.org_id;
  }

  if (!orgID) {
    const { data: org, error: orgError } = await admin
      .from("organizations")
      .insert({
        name: fallbackOrgName(user.email),
        owner_id: user.id,
        subscription_type: "individual",
        seat_limit: 1,
      })
      .select("id")
      .single();

    if (orgError || !org) {
      return json({ error: orgError?.message ?? "Organization creation failed." }, 400);
    }

    const { error: membershipError } = await admin
      .from("org_members")
      .insert({ org_id: org.id, user_id: user.id, role: "owner" });

    if (membershipError) {
      return json({ error: membershipError.message }, 400);
    }

    orgID = org.id;
  }

  const { error: updateError } = await admin
    .from("profiles")
    .update({ org_id: orgID })
    .eq("id", user.id);

  if (updateError) {
    return json({ error: updateError.message }, 400);
  }

  return json({ org_id: orgID, created: true });
});
