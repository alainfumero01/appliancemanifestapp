import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const body = await request.json().catch(() => null);

  if (!body) {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const normalizedModelNumber = String(body.normalizedModelNumber ?? "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .trim();
  const productName = String(body.productName ?? "").trim();
  const msrp = Number(body.msrp ?? 0);
  const source = String(body.source ?? "operator-confirmed").trim() || "operator-confirmed";
  const confidence = Number(body.confidence ?? 0);

  if (!normalizedModelNumber || !productName || !Number.isFinite(msrp) || msrp < 0) {
    return new Response(JSON.stringify({ error: "normalizedModelNumber, productName, and valid msrp are required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    {
      auth: { autoRefreshToken: false, persistSession: false },
    }
  );

  const payload = {
    normalized_model_number: normalizedModelNumber,
    product_name: productName,
    msrp,
    source,
    confidence,
    last_verified_at: new Date().toISOString(),
  };

  const { data, error } = await supabase
    .from("product_catalog")
    .upsert(payload, { onConflict: "normalized_model_number" })
    .select("normalized_model_number, product_name, msrp, source, confidence")
    .single();

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  return Response.json({
    normalizedModelNumber: data.normalized_model_number,
    productName: data.product_name,
    msrp: Number(data.msrp),
    source: "catalog-cache",
    confidence: Number(data.confidence ?? 0),
    status: "confirmed",
  });
});
