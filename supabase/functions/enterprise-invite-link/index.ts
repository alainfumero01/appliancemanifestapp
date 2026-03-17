import { createClient } from "jsr:@supabase/supabase-js@2";

function unauthorized() {
  return new Response(JSON.stringify({ error: "Unauthorized" }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });
}

function randomCode() {
  return `TEAM-${crypto.randomUUID().split("-")[0].toUpperCase()}`;
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

  const { data: org } = await admin
    .from("organizations")
    .select("id, owner_id, seat_limit, subscription_type")
    .eq("owner_id", user.id)
    .maybeSingle();

  if (!org) {
    return new Response(JSON.stringify({ error: "Only organization owners can create invite links." }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { count: memberCount } = await admin
    .from("org_members")
    .select("user_id", { count: "exact", head: true })
    .eq("org_id", org.id);

  const remainingSeats = Math.max((org.seat_limit ?? 1) - (memberCount ?? 0), 0);
  if (remainingSeats <= 0) {
    return new Response(JSON.stringify({ error: "Your plan has no remaining team seats." }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  const code = randomCode();
  await admin.from("invite_codes").insert({
    code,
    is_active: true,
    usage_limit: remainingSeats,
    usage_count: 0,
    created_by: user.id,
    org_id: org.id,
  });

  return Response.json({
    code,
    inviteURL: `loadscan://signup?invite=${encodeURIComponent(code)}`,
    seatLimit: org.seat_limit,
    currentMemberCount: memberCount ?? 0,
  });
});
