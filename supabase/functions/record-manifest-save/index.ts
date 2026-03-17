import { createClient } from "jsr:@supabase/supabase-js@2";

function unauthorized() {
  return new Response(JSON.stringify({ error: "Unauthorized" }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const token = (request.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
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

  const { data: org } = await admin
    .from("organizations")
    .select("id,name,owner_id,subscription_type,billing_platform,subscription_status,app_store_product_id,subscription_expires_at,seat_limit,extra_seats,trial_manifest_limit,trial_manifests_used")
    .eq("id", profile.org_id)
    .single();

  if (org.subscription_status !== "active") {
    if ((org.trial_manifests_used ?? 0) >= (org.trial_manifest_limit ?? 3)) {
      return new Response(JSON.stringify({ error: "Free manifest limit reached." }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    await admin
      .from("organizations")
      .update({ trial_manifests_used: (org.trial_manifests_used ?? 0) + 1 })
      .eq("id", org.id);
  }

  const { count: memberCount } = await admin
    .from("org_members")
    .select("user_id", { count: "exact", head: true })
    .eq("org_id", org.id);

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
    trialManifestsUsed: Math.min((org.trial_manifests_used ?? 0) + (org.subscription_status === "active" ? 0 : 1), org.trial_manifest_limit ?? 3),
    memberCount: memberCount ?? 0,
    isOwner: org.owner_id === user.id,
  });
});
