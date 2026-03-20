const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const FORWARD_TOKEN = Deno.env.get("RESEND_INBOUND_TOKEN") ?? "";
const SUPPORT_INBOX = Deno.env.get("SUPPORT_FORWARD_TO") ?? "alainfumero2000@gmail.com";
const SUPPORT_ADDRESS = "support@load-scan.com";

type ReceivedEvent = {
  type?: string;
  data?: {
    email_id?: string;
    from?: string;
    to?: string[];
    subject?: string;
  };
};

type ReceivedEmail = {
  id: string;
  from: string;
  to: string[];
  subject: string | null;
  text: string | null;
  html: string | null;
  reply_to?: string[];
  attachments?: Array<{ filename?: string | null }>;
  raw?: { download_url?: string | null } | null;
};

function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function normalizeEmailAddress(value: string): string {
  const match = value.match(/<([^>]+)>/);
  return (match?.[1] ?? value).trim().toLowerCase();
}

function buildForwardedHTML(email: ReceivedEmail): string {
  const attachmentNames = (email.attachments ?? [])
    .map((attachment) => attachment.filename?.trim())
    .filter(Boolean) as string[];

  const bodyHTML = email.html
    ? email.html
    : `<pre style="white-space:pre-wrap;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;line-height:1.6;color:#111827;background:#F8FAFC;border:1px solid #E5E7EB;border-radius:12px;padding:16px;">${escapeHTML(email.text ?? "(No message body)")}</pre>`;

  const rawLink = email.raw?.download_url
    ? `<p style="margin:16px 0 0;font-size:12px;color:#6B7280;">Raw email download: <a href="${email.raw.download_url}" style="color:#2550DB;">Open raw message</a></p>`
    : "";

  const attachmentsHTML = attachmentNames.length > 0
    ? `<p style="margin:12px 0 0;font-size:12px;color:#6B7280;">Attachments: ${attachmentNames.map(escapeHTML).join(", ")}</p>`
    : "";

  return `<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:24px;background:#F3F4F6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#111827;">
  <table width="100%" cellpadding="0" cellspacing="0">
    <tr>
      <td align="center">
        <table width="640" cellpadding="0" cellspacing="0" style="max-width:640px;width:100%;">
          <tr>
            <td style="background:#FFFFFF;border:1px solid #E5E7EB;border-radius:16px;padding:28px;">
              <p style="margin:0 0 8px;font-size:12px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#2550DB;">Forwarded Support Email</p>
              <h1 style="margin:0 0 20px;font-size:24px;line-height:1.2;color:#111827;">${escapeHTML(email.subject ?? "(No subject)")}</h1>
              <p style="margin:0;font-size:14px;line-height:1.7;color:#4B5563;">
                From: <strong>${escapeHTML(email.from)}</strong><br/>
                To: ${escapeHTML(email.to.join(", "))}<br/>
                Reply using your email client to respond directly to the sender.
              </p>
              ${attachmentsHTML}
              ${rawLink}
              <hr style="border:none;border-top:1px solid #E5E7EB;margin:24px 0;"/>
              ${bodyHTML}
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

Deno.serve(async (request) => {
  const url = new URL(request.url);
  if (request.method !== "POST") {
    return Response.json({ ok: true });
  }

  if (!FORWARD_TOKEN || url.searchParams.get("token") !== FORWARD_TOKEN) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  if (!RESEND_API_KEY) {
    return Response.json({ error: "Missing RESEND_API_KEY" }, { status: 500 });
  }

  let payload: ReceivedEvent;
  try {
    payload = await request.json();
  } catch (_) {
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }

  if (payload.type !== "email.received" || !payload.data?.email_id) {
    return Response.json({ ok: true });
  }

  const recipients = payload.data.to ?? [];
  const sentToSupport = recipients.some((value) => normalizeEmailAddress(value) === SUPPORT_ADDRESS);
  if (!sentToSupport) {
    return Response.json({ ok: true, skipped: true });
  }

  const receivedResponse = await fetch(`https://api.resend.com/emails/receiving/${payload.data.email_id}`, {
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
  });

  if (!receivedResponse.ok) {
    console.error("Failed to retrieve received email", await receivedResponse.text());
    return Response.json({ error: "Failed to retrieve received email" }, { status: 502 });
  }

  const email = await receivedResponse.json() as ReceivedEmail;
  const replyAddress = email.reply_to?.[0]
    ? normalizeEmailAddress(email.reply_to[0])
    : normalizeEmailAddress(email.from);

  const forwardResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "LoadScan Support <support@load-scan.com>",
      to: [SUPPORT_INBOX],
      reply_to: [replyAddress],
      subject: `[LoadScan Support] ${email.subject ?? "(No subject)"}`,
      html: buildForwardedHTML(email),
      text: `Forwarded support email\n\nFrom: ${email.from}\nTo: ${email.to.join(", ")}\nSubject: ${email.subject ?? "(No subject)"}\n\nReply to this email to respond directly to the sender.\n\n${email.text ?? "(No text body provided)"}`,
    }),
  });

  if (!forwardResponse.ok) {
    console.error("Failed to forward received email", await forwardResponse.text());
    return Response.json({ error: "Failed to forward email" }, { status: 502 });
  }

  return Response.json({ ok: true });
});
