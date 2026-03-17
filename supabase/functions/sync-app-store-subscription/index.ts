import { applySubscriptionUpdate, createAdminClient, deriveSubscriptionStatus, PLAN_CONFIG, verifyTransactionJWS } from "../_shared/appStore.ts";

function unauthorized() {
  return new Response(JSON.stringify({ error: "Unauthorized" }), {
    status: 401, headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const token = (request.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
  if (!token) return unauthorized();

  const body = await request.json();
  const productID = typeof body?.productID === "string" ? body.productID : "";
  const plan = PLAN_CONFIG[String(productID ?? "")];
  if (!plan) {
    return new Response(JSON.stringify({ error: "Unknown App Store product." }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  const admin = createAdminClient();

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

  const transactionJWS = typeof body?.transactionJWS === "string" ? body.transactionJWS : null;
  const transaction = transactionJWS ? (await verifyTransactionJWS(transactionJWS)).transaction : null;

  if (transaction?.productID && transaction.productID !== productID) {
    return new Response(JSON.stringify({ error: "Transaction product does not match request." }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  if (transaction?.appAccountToken && transaction.appAccountToken !== profile.org_id) {
    return new Response(JSON.stringify({ error: "Transaction appAccountToken does not match organization." }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  const expiresAt = transaction?.expiresAtISO ?? (() => {
    const fallback = new Date();
    fallback.setMonth(fallback.getMonth() + 1);
    return fallback.toISOString();
  })();

  const generatedCodes = await applySubscriptionUpdate(admin, {
    emailInviteCodes: true,
    expiresAtISO: expiresAt,
    orgID: profile.org_id,
    productID,
    status: deriveSubscriptionStatus({
      expiresAtISO: expiresAt,
      revocationDateISO: transaction?.revocationDateISO,
    }),
  });

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
