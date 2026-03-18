import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from "npm:@apple/app-store-server-library@3";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const APP_BUNDLE_ID = "com.alainfumero.loadscan";
const APPLE_APP_ID = (() => {
  const raw = Deno.env.get("APPLE_APP_ID");
  if (!raw) return undefined;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : undefined;
})();
const ENABLE_ONLINE_CHECKS = (Deno.env.get("APPLE_ENABLE_ONLINE_CHECKS") ?? "true").toLowerCase() !== "false";
const APPLE_ROOT_CA_BASE64 = [
  "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",
];
const APPLE_ROOT_CAS = APPLE_ROOT_CA_BASE64.map((certificate) => Buffer.from(certificate, "base64"));

export const PLAN_CONFIG: Record<string, { subscription_type: "individual" | "enterprise"; seat_limit: number; extra_seats: number }> = {
  "com.alainfumero.loadscan.individual.monthly": { subscription_type: "individual", seat_limit: 1, extra_seats: 0 },
  "com.alainfumero.loadscan.enterprise5.monthly": { subscription_type: "enterprise", seat_limit: 6, extra_seats: 5 },
  "com.alainfumero.loadscan.enterprise10.monthly": { subscription_type: "enterprise", seat_limit: 11, extra_seats: 10 },
  "com.alainfumero.loadscan.enterprise15.monthly": { subscription_type: "enterprise", seat_limit: 16, extra_seats: 15 },
};

type SubscriptionStatus = "free" | "active" | "expired" | "past_due" | "canceled";
type VerifiedTransaction = JWSTransactionDecodedPayload;
type VerifiedNotification = ResponseBodyV2DecodedPayload;

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function decodeBase64Url(input: string): string {
  const normalized = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  return atob(padded);
}

export function decodeJWSPayload(token: string): Record<string, unknown> {
  const parts = token.split(".");
  if (parts.length < 2) throw new Error("Malformed JWS");
  return JSON.parse(decodeBase64Url(parts[1]));
}

function toISOStringFromMillis(value: unknown): string | null {
  const millis = asNumber(value);
  return millis === null ? null : new Date(millis).toISOString();
}

export type DecodedTransaction = {
  appAccountToken: string | null;
  bundleID: string | null;
  environment: string | null;
  expiresAtISO: string | null;
  originalTransactionID: string | null;
  productID: string | null;
  revocationDateISO: string | null;
  transactionID: string | null;
};

export function decodeTransactionJWS(token: string): DecodedTransaction {
  const payload = decodeJWSPayload(token);
  return {
    appAccountToken: asString(payload.appAccountToken),
    bundleID: asString(payload.bundleId),
    environment: asString(payload.environment),
    expiresAtISO: toISOStringFromMillis(payload.expiresDate),
    originalTransactionID: asString(payload.originalTransactionId),
    productID: asString(payload.productId),
    revocationDateISO: toISOStringFromMillis(payload.revocationDate),
    transactionID: asString(payload.transactionId),
  };
}

function createVerifier(environment: Environment): SignedDataVerifier {
  if (environment === Environment.PRODUCTION && APPLE_APP_ID === undefined) {
    throw new Error("Missing APPLE_APP_ID secret required for production App Store verification.");
  }

  return new SignedDataVerifier(
    APPLE_ROOT_CAS,
    ENABLE_ONLINE_CHECKS,
    environment,
    APP_BUNDLE_ID,
    environment === Environment.PRODUCTION ? APPLE_APP_ID : undefined,
  );
}

async function verifyWithCandidates<T>(
  candidates: Environment[],
  verify: (verifier: SignedDataVerifier) => Promise<T>,
): Promise<{ environment: Environment; payload: T }> {
  const errors: string[] = [];

  for (const environment of candidates) {
    try {
      const verifier = createVerifier(environment);
      const payload = await verify(verifier);
      return { environment, payload };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      errors.push(`${environment}: ${message}`);
    }
  }

  throw new Error(errors.join(" | "));
}

export async function verifyTransactionJWS(
  token: string,
  preferredEnvironment?: string | null,
): Promise<{ environment: Environment; transaction: VerifiedTransaction }> {
  const preferred = preferredEnvironment?.toLowerCase() === "production"
    ? Environment.PRODUCTION
    : preferredEnvironment?.toLowerCase() === "sandbox"
      ? Environment.SANDBOX
      : null;

  const candidates = preferred
    ? [preferred, ...(preferred === Environment.SANDBOX ? [Environment.PRODUCTION] : [Environment.SANDBOX])]
    : [Environment.SANDBOX, Environment.PRODUCTION];

  const verified = await verifyWithCandidates(candidates, (verifier) => verifier.verifyAndDecodeTransaction(token));
  return { environment: verified.environment, transaction: verified.payload };
}

export async function verifyNotificationSignedPayload(
  signedPayload: string,
): Promise<{ environment: Environment; notification: VerifiedNotification }> {
  const verified = await verifyWithCandidates(
    [Environment.SANDBOX, Environment.PRODUCTION],
    (verifier) => verifier.verifyAndDecodeNotification(signedPayload),
  );
  return { environment: verified.environment, notification: verified.payload };
}

export function deriveSubscriptionStatus(args: {
  notificationType?: string | null;
  subtype?: string | null;
  expiresAtISO?: string | null;
  revocationDateISO?: string | null;
}): SubscriptionStatus {
  if (args.revocationDateISO) return "canceled";

  const notificationType = (args.notificationType ?? "").toUpperCase();
  const subtype = (args.subtype ?? "").toUpperCase();
  const expiresAt = args.expiresAtISO ? new Date(args.expiresAtISO) : null;
  const isExpired = expiresAt ? expiresAt.getTime() <= Date.now() : false;

  if (notificationType === "EXPIRED") return "expired";
  if (notificationType === "REFUND" || notificationType === "REVOKE") return "canceled";
  if (notificationType === "DID_FAIL_TO_RENEW" || notificationType === "GRACE_PERIOD_EXPIRED") {
    return isExpired || subtype === "BILLING_RETRY" ? "past_due" : "active";
  }
  if (isExpired) return "expired";
  return "active";
}

function randomCode() {
  return `TEAM-${crypto.randomUUID().split("-")[0].toUpperCase()}`;
}

type InviteCodeRow = {
  id: string;
  code: string;
  created_at?: string | null;
  is_active: boolean;
  usage_count: number;
  usage_limit: number | null;
};

function isInviteCodeAvailable(code: InviteCodeRow): boolean {
  return code.is_active && (code.usage_limit === null || code.usage_count < code.usage_limit);
}

export async function reconcileInviteCodes(
  admin: SupabaseClient,
  args: {
    orgID: string;
    ownerID: string | null;
    targetAvailableCodes: number;
    resetPool: boolean;
  },
): Promise<string[]> {
  const { data: rawCodes } = await admin
    .from("invite_codes")
    .select("id,code,created_at,is_active,usage_count,usage_limit")
    .eq("org_id", args.orgID)
    .order("created_at", { ascending: true });

  const codes = (rawCodes ?? []) as InviteCodeRow[];
  const exhaustedIDs = codes
    .filter((code) => code.is_active && code.usage_limit !== null && code.usage_count >= code.usage_limit)
    .map((code) => code.id);

  if (exhaustedIDs.length > 0) {
    await admin
      .from("invite_codes")
      .update({ is_active: false })
      .in("id", exhaustedIDs);
  }

  let availableCodes = codes.filter((code) => !exhaustedIDs.includes(code.id) && isInviteCodeAvailable(code));

  if (args.resetPool && availableCodes.length > 0) {
    await admin
      .from("invite_codes")
      .update({ is_active: false })
      .in("id", availableCodes.map((code) => code.id));
    availableCodes = [];
  }

  if (availableCodes.length > args.targetAvailableCodes) {
    const extraCodes = availableCodes.slice(args.targetAvailableCodes);
    await admin
      .from("invite_codes")
      .update({ is_active: false })
      .in("id", extraCodes.map((code) => code.id));
    availableCodes = availableCodes.slice(0, args.targetAvailableCodes);
  }

  const missingCount = Math.max(args.targetAvailableCodes - availableCodes.length, 0);
  if (missingCount === 0) {
    return [];
  }

  const generatedCodes = Array.from({ length: missingCount }, () => randomCode());
  await admin
    .from("invite_codes")
    .insert(generatedCodes.map((code) => ({
      code,
      is_active: true,
      usage_limit: 1,
      usage_count: 0,
      created_by: args.ownerID,
      org_id: args.orgID,
    })));

  return generatedCodes;
}

async function sendInviteEmail(email: string, codes: string[], seats: number) {
  const codeRows = codes.map((code) =>
    `<tr><td style="padding:8px 12px;font-family:monospace;font-size:15px;font-weight:700;color:#111520;background:#F0F4FF;border-radius:6px;letter-spacing:0.05em;">${code}</td></tr>`
  ).join("<tr><td style='height:6px'></td></tr>");

  const html = `<!DOCTYPE html><html><head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#F0F2F8;font-family:-apple-system,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#F0F2F8;padding:40px 16px;">
<tr><td align="center"><table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">
  <tr><td align="center" style="padding-bottom:24px;">
    <table cellpadding="0" cellspacing="0"><tr>
      <td style="background:#0C1340;border-radius:10px;width:38px;height:38px;text-align:center;vertical-align:middle;"><span style="color:#fff;font-size:20px;font-weight:800;line-height:38px;display:block;">L</span></td>
      <td style="padding-left:10px;font-size:19px;font-weight:700;color:#111520;">LoadScan</td>
    </tr></table>
  </td></tr>
  <tr><td style="background:#fff;border-radius:16px;border:1px solid #DDE3F0;padding:44px 40px 36px;">
    <p style="margin:0 0 10px;font-size:11px;font-weight:600;letter-spacing:0.1em;text-transform:uppercase;color:#2550DB;">Enterprise Plan Active</p>
    <h1 style="margin:0 0 18px;font-size:26px;font-weight:800;color:#111520;line-height:1.15;">Your team invite codes are ready</h1>
    <p style="margin:0 0 24px;font-size:15px;color:#4B5563;line-height:1.7;">Your LoadScan Enterprise plan includes <strong>${seats} team seat${seats !== 1 ? "s" : ""}</strong>. Share the codes below with your teammates — each code can be used once during signup.</p>
    <table cellpadding="0" cellspacing="0" style="width:100%;margin-bottom:24px;">
      ${codeRows}
    </table>
    <p style="margin:0 0 16px;font-size:14px;color:#6B7280;line-height:1.65;">Teammates enter their code on the signup screen in the LoadScan app. Each code is single-use and ties their account to your team.</p>
    <hr style="border:none;border-top:1px solid #E5E9F4;margin:28px 0;"/>
    <p style="margin:0;font-size:12px;color:#9CA3AF;line-height:1.7;">You can also generate new invite links anytime from <strong>Settings → Membership</strong> in the app.<br/>Questions? <a href="mailto:support@load-scan.com" style="color:#2550DB;">support@load-scan.com</a></p>
  </td></tr>
  <tr><td align="center" style="padding-top:20px;">
    <p style="margin:0;font-size:12px;color:#9CA3AF;">2026 LoadScan &nbsp;&middot;&nbsp; <a href="https://load-scan.com/privacy" style="color:#9CA3AF;text-decoration:none;">Privacy Policy</a></p>
  </td></tr>
</table></td></tr></table>
</body></html>`;

  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "LoadScan <noreply@load-scan.com>",
      to: [email],
      subject: `Your LoadScan team invite codes (${seats} seat${seats !== 1 ? "s" : ""})`,
      html,
    }),
  });
}

async function lookupOwnerEmail(admin: SupabaseClient, ownerID: string): Promise<string | null> {
  const { data } = await admin
    .from("profiles")
    .select("email")
    .eq("id", ownerID)
    .maybeSingle();

  return asString(data?.email) ?? null;
}

export function createAdminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

export async function applySubscriptionUpdate(
  admin: SupabaseClient,
  args: {
    emailInviteCodes: boolean;
    expiresAtISO: string | null;
    orgID: string;
    productID: string;
    status: SubscriptionStatus;
  },
): Promise<string[]> {
  const plan = PLAN_CONFIG[args.productID];
  if (!plan) throw new Error("Unknown App Store product.");

  const { data: org } = await admin
    .from("organizations")
    .select("app_store_product_id, owner_id")
    .eq("id", args.orgID)
    .single();

  const previousProductID = asString(org?.app_store_product_id);

  await admin
    .from("organizations")
    .update({
      app_store_product_id: args.productID,
      subscription_type: plan.subscription_type,
      subscription_status: args.status,
      billing_platform: "app_store",
      subscription_expires_at: args.expiresAtISO,
      seat_limit: plan.seat_limit,
      extra_seats: plan.extra_seats,
    })
    .eq("id", args.orgID);

  const { count: memberCount } = await admin
    .from("org_members")
    .select("user_id", { count: "exact", head: true })
    .eq("org_id", args.orgID);

  const targetAvailableCodes = args.status === "active" && plan.extra_seats > 0
    ? Math.max(plan.seat_limit - (memberCount ?? 0), 0)
    : 0;

  const generatedCodes = await reconcileInviteCodes(admin, {
    orgID: args.orgID,
    ownerID: asString(org?.owner_id),
    resetPool: previousProductID !== args.productID || targetAvailableCodes === 0,
    targetAvailableCodes,
  });

  if (args.emailInviteCodes && org?.owner_id) {
    const ownerEmail = await lookupOwnerEmail(admin, String(org.owner_id));
    if (ownerEmail) {
      await sendInviteEmail(ownerEmail, generatedCodes, plan.extra_seats);
    }
  }

  return generatedCodes;
}

export function extractNotificationData(payload: Record<string, unknown>) {
  const data = asRecord(payload.data) ?? {};
  return {
    notificationType: asString(payload.notificationType),
    subtype: asString(payload.subtype),
    signedRenewalInfo: asString(data.signedRenewalInfo),
    signedTransactionInfo: asString(data.signedTransactionInfo),
  };
}
