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

  if (!profile?.org_id) return Response.json([]);

  const { data: members, error: membersError } = await admin
    .from("org_members")
    .select("user_id, role")
    .eq("org_id", profile.org_id);

  if (membersError) {
    return new Response(JSON.stringify({ error: membersError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const memberIDs = (members ?? []).map((member) => member.user_id);
  const { data: profiles, error: profilesError } = await admin
    .from("profiles")
    .select("id, email")
    .in("id", memberIDs);

  if (profilesError) {
    return new Response(JSON.stringify({ error: profilesError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const emailByID = new Map((profiles ?? []).map((profile) => [profile.id, profile.email]));

  return Response.json(
    (members ?? []).map((member) => ({
      id: member.user_id,
      email: emailByID.get(member.user_id) ?? "member",
      role: member.role,
      joinedAt: null,
    })),
  );
});
