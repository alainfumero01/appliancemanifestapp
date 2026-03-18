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

  const { data: existingCodes } = await admin
    .from("invite_codes")
    .select("id, code, is_active, usage_count, usage_limit, created_at")
    .eq("org_id", org.id)
    .order("created_at", { ascending: true });

  const activeAvailable = (existingCodes ?? []).filter((code) =>
    code.is_active && (code.usage_limit === null || code.usage_count < code.usage_limit)
  );

  let generatedCodes: string[] = [];
  const missingCount = Math.max(remainingSeats - activeAvailable.length, 0);
  if (missingCount > 0) {
    generatedCodes = Array.from({ length: missingCount }, () => randomCode());
    await admin.from("invite_codes").insert(
      generatedCodes.map((code) => ({
        code,
        is_active: true,
        usage_limit: 1,
        usage_count: 0,
        created_by: user.id,
        org_id: org.id,
      }))
    );
  }

  const code = activeAvailable[0]?.code ?? generatedCodes[0];
  if (!code) {
    return new Response(JSON.stringify({ error: "Your current invite codes are already available below." }), {
      status: 409,
      headers: { "Content-Type": "application/json" },
    });
  }

  return Response.json({
    code,
    inviteURL: `loadscan://signup?invite=${encodeURIComponent(code)}`,
    seatLimit: org.seat_limit,
    currentMemberCount: memberCount ?? 0,
  });
});
