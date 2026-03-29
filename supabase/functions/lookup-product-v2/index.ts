import { createClient } from "jsr:@supabase/supabase-js@2";

import { resolveLookup } from "../_shared/catalogLookup.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const body = await request.json().catch(() => null);
  const modelNumber = String(body?.modelNumber ?? "").trim();
  if (!modelNumber) {
    return new Response(JSON.stringify({ error: "modelNumber is required." }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAIKey) {
    return new Response(JSON.stringify({ error: "OPENAI_API_KEY is not configured." }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    {
      auth: { autoRefreshToken: false, persistSession: false },
    },
  );

  try {
    const resolved = await resolveLookup(supabase, openAIKey, modelNumber, { logLookup: true });
    return Response.json(resolved.response);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message === "not_appliance") {
      return new Response(JSON.stringify({ error: "not_appliance" }), {
        status: 422,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ error: message || "Lookup failed." }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }
});
