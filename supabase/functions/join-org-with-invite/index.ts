import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Accept token from X-User-Token (preferred) or Authorization header.
  // Using X-User-Token lets the gateway use the anon key in Authorization
  // so the gateway never rejects the request due to an expired user JWT.
  const token = request.headers.get("X-User-Token")?.trim()
    ?? (request.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
  if (!token) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401, headers: { "Content-Type": "application/json" },
    });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const { data: authData } = await admin.auth.getUser(token);
  const user = authData.user;
  if (!user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401, headers: { "Content-Type": "application/json" },
    });
  }

  const { inviteCode } = await request.json();
  if (!inviteCode || typeof inviteCode !== "string") {
    return new Response(JSON.stringify({ error: "Invite code is required." }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  // Validate invite code
  const { data: invite, error: inviteError } = await admin
    .from("invite_codes")
    .select("id, is_active, usage_limit, usage_count, org_id")
    .eq("code", inviteCode.trim().toUpperCase().replace(/\s+/g, ""))
    .maybeSingle();

  if (inviteError || !invite || !invite.is_active) {
    return new Response(JSON.stringify({ error: "Invite code is invalid or disabled." }), {
      status: 403, headers: { "Content-Type": "application/json" },
    });
  }

  if (invite.usage_limit !== null && invite.usage_count >= invite.usage_limit) {
    return new Response(JSON.stringify({ error: "Invite code usage limit has been reached." }), {
      status: 403, headers: { "Content-Type": "application/json" },
    });
  }

  if (!invite.org_id) {
    return new Response(JSON.stringify({ error: "This invite code is not linked to an organization." }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  // Check user isn't already in this org
  const { data: existing } = await admin
    .from("org_members")
    .select("org_id")
    .eq("org_id", invite.org_id)
    .eq("user_id", user.id)
    .maybeSingle();

  if (existing) {
    return new Response(JSON.stringify({ error: "You are already a member of this organization." }), {
      status: 409, headers: { "Content-Type": "application/json" },
    });
  }

  // Enforce seat limit
  const { data: orgForSeatCheck } = await admin
    .from("organizations")
    .select("seat_limit")
    .eq("id", invite.org_id)
    .single();

  const { count: currentMemberCount } = await admin
    .from("org_members")
    .select("user_id", { count: "exact", head: true })
    .eq("org_id", invite.org_id);

  if (orgForSeatCheck && orgForSeatCheck.seat_limit !== null && (currentMemberCount ?? 0) >= orgForSeatCheck.seat_limit) {
    return new Response(JSON.stringify({ error: "This organization has reached its seat limit." }), {
      status: 403, headers: { "Content-Type": "application/json" },
    });
  }

  // Remove user from their current personal org (if it only has them)
  const { data: currentProfile } = await admin
    .from("profiles")
    .select("org_id")
    .eq("id", user.id)
    .maybeSingle();

  if (currentProfile?.org_id) {
    const { count } = await admin
      .from("org_members")
      .select("user_id", { count: "exact", head: true })
      .eq("org_id", currentProfile.org_id);

    if (count === 1) {
      // They were the only member — delete the personal org
      await admin.from("organizations").delete().eq("id", currentProfile.org_id);
    } else {
      // Just remove them from the org
      await admin.from("org_members").delete()
        .eq("org_id", currentProfile.org_id)
        .eq("user_id", user.id);
    }
  }

  // Add to the enterprise org
  await admin.from("org_members").insert({
    org_id: invite.org_id,
    user_id: user.id,
    role: "member",
  });

  // Update profile to point to new org
  await admin.from("profiles")
    .update({ org_id: invite.org_id })
    .eq("id", user.id);

  // Increment invite code usage
  const nextUsageCount = invite.usage_count + 1;
  await admin.from("invite_codes")
    .update({
      usage_count: nextUsageCount,
      is_active: invite.usage_limit === null ? true : nextUsageCount < invite.usage_limit,
    })
    .eq("id", invite.id);

  // Return updated entitlement
  const { data: org } = await admin
    .from("organizations")
    .select("id,name,owner_id,subscription_type,billing_platform,subscription_status,app_store_product_id,subscription_expires_at,seat_limit,extra_seats,trial_manifest_limit,trial_manifests_used")
    .eq("id", invite.org_id)
    .single();

  const { count: memberCount } = await admin
    .from("org_members")
    .select("user_id", { count: "exact", head: true })
    .eq("org_id", invite.org_id);

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
  });
});
