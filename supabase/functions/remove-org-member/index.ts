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

  await admin
    .from("org_members")
    .delete()
    .eq("org_id", org.id)
    .eq("user_id", memberID);

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
