import { applySubscriptionUpdate, createAdminClient, deriveSubscriptionStatus, verifyNotificationSignedPayload, verifyTransactionJWS } from "../_shared/appStore.ts";

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const signedPayload = typeof body.signedPayload === "string" ? body.signedPayload : "";
  if (!signedPayload) {
    return json({ error: "Missing signedPayload" }, 400);
  }

  let verifiedNotification;
  try {
    verifiedNotification = await verifyNotificationSignedPayload(signedPayload);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Invalid signedPayload" }, 400);
  }

  const notification = verifiedNotification.notification;
  const notificationType = typeof notification.notificationType === "string" ? notification.notificationType : null;
  const subtype = typeof notification.subtype === "string" ? notification.subtype : null;
  const signedTransactionInfo = typeof notification.data?.signedTransactionInfo === "string"
    ? notification.data.signedTransactionInfo
    : null;

  if (notificationType === "TEST") {
    return json({ ok: true, notificationType });
  }

  if (!signedTransactionInfo) {
    return json({ ok: true, notificationType, skipped: "No signedTransactionInfo present" });
  }

  let verifiedTransaction;
  try {
    verifiedTransaction = await verifyTransactionJWS(
      signedTransactionInfo,
      typeof notification.data?.environment === "string" ? notification.data.environment : null,
    );
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Invalid signedTransactionInfo" }, 400);
  }

  const transaction = verifiedTransaction.transaction;

  if (!transaction.productID) {
    return json({ ok: true, notificationType, skipped: "No productId in transaction payload" });
  }

  if (!transaction.appAccountToken) {
    return json({
      ok: true,
      notificationType,
      skipped: "No appAccountToken in transaction payload",
      productID: transaction.productID,
      originalTransactionID: transaction.originalTransactionID,
    });
  }

  const admin = createAdminClient();
  const generatedCodes = await applySubscriptionUpdate(admin, {
    emailInviteCodes: false,
    expiresAtISO: transaction.expiresAtISO,
    orgID: transaction.appAccountToken,
    productID: transaction.productID,
    status: deriveSubscriptionStatus({
      notificationType,
      subtype,
      expiresAtISO: transaction.expiresAtISO,
      revocationDateISO: transaction.revocationDateISO,
    }),
  });

  return json({
    ok: true,
    generatedInviteCodes: generatedCodes.length,
    notificationType,
    orgID: transaction.appAccountToken,
    originalTransactionID: transaction.originalTransactionID,
    productID: transaction.productID,
    subtype,
  });
});
