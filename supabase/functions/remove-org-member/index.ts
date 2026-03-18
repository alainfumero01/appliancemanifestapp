import { createClient } from "jsr:@supabase/supabase-js@2";
import { PLAN_CONFIG, reconcileInviteCodes } from "../_shared/appStore.ts";

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

  const token = request.headers.get("X-User-Token")?.trim()
    ?? (request.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
  if (!token) return unauthorized();

  const { memberID } = await request.json();

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const { data: authData } = await admin.auth.getUser(token);
  const user = authData.user;
  if (!user) return unauthorized();

  const { data: org } = await admin
    .from("organizations")
    .select("id, owner_id, app_store_product_id, seat_limit, subscription_status")
    .eq("owner_id", user.id)
    .maybeSingle();

  if (!org) {
    return new Response(JSON.stringify({ error: "Only organization owners can remove members." }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (memberID === user.id) {
    return new Response(JSON.stringify({ error: "Owner cannot remove themselves." }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: removedProfile } = await admin
    .from("profiles")
    .select("email, org_id")
    .eq("id", memberID)
    .maybeSingle();

  await admin
    .from("org_members")
    .delete()
    .eq("org_id", org.id)
    .eq("user_id", memberID);

  const fallbackOrgName = (typeof removedProfile?.email === "string" && removedProfile.email.includes("@"))
    ? removedProfile.email.split("@")[0]
    : "LoadScan Member";

  const { data: existingPersonalOrg } = await admin
    .from("organizations")
    .select("id")
    .eq("owner_id", memberID)
    .neq("id", org.id)
    .maybeSingle();

  const personalOrg = existingPersonalOrg
    ? existingPersonalOrg
    : (await admin
      .from("organizations")
      .insert({
        name: fallbackOrgName,
        owner_id: memberID,
        subscription_type: "individual",
        seat_limit: 1,
        extra_seats: 0,
        billing_platform: "none",
        subscription_status: "free",
        app_store_product_id: null,
        subscription_expires_at: null,
        trial_manifests_used: 0,
        trial_manifest_limit: 3,
      })
      .select("id")
      .single()).data;

  await admin
    .from("org_members")
    .upsert({
      org_id: personalOrg.id,
      user_id: memberID,
      role: "owner",
    }, { onConflict: "org_id,user_id" });

  await admin
    .from("profiles")
    .update({
      org_id: personalOrg.id,
      session_nonce: crypto.randomUUID(),
    })
    .eq("id", memberID);

  const { count: memberCount } = await admin
    .from("org_members")
    .select("user_id", { count: "exact", head: true })
    .eq("org_id", org.id);

  const productID = typeof org.app_store_product_id === "string" ? org.app_store_product_id : null;
  const plan = productID ? PLAN_CONFIG[productID] : null;
  const isActive = org.subscription_status === "active";

  if (plan && isActive && plan.extra_seats > 0) {
    await reconcileInviteCodes(admin, {
      orgID: org.id,
      ownerID: org.owner_id,
      resetPool: false,
      targetAvailableCodes: Math.max(plan.seat_limit - (memberCount ?? 0), 0),
    });
  }

  return Response.json({ ok: true });
});
