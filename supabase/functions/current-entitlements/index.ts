import { createClient } from "jsr:@supabase/supabase-js@2";

function unauthorized() {
  return new Response(JSON.stringify({ error: "Unauthorized" }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  const token = request.headers.get("X-User-Token")?.trim()
    ?? (request.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
  if (!token) return unauthorized();

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
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  const [{ data: membership }, { data: org }, { count: memberCount }] = await Promise.all([
    admin
      .from("org_members")
      .select("role")
      .eq("org_id", profile.org_id)
      .eq("user_id", user.id)
      .maybeSingle(),
    admin
      .from("organizations")
      .select("id,name,owner_id,subscription_type,billing_platform,subscription_status,app_store_product_id,subscription_expires_at,seat_limit,extra_seats,trial_manifest_limit,trial_manifests_used")
      .eq("id", profile.org_id)
      .single(),
    admin
      .from("org_members")
      .select("user_id", { count: "exact", head: true })
      .eq("org_id", profile.org_id),
  ]);

  if (!membership) {
    return new Response(JSON.stringify({ error: "Organization access not found." }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!org) {
    return new Response(JSON.stringify({ error: "Organization not found." }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

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
