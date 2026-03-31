import { createClient } from "jsr:@supabase/supabase-js@2";

import {
  OPERATOR_CONFIRMED_SOURCE,
  normalizeModelNumber,
  upsertCatalogEntry,
  upsertModelAliases,
} from "../_shared/catalogLookup.ts";

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

  const normalizedModelNumber = normalizeModelNumber(body.normalizedModelNumber);
  const productName = String(body.productName ?? "").trim();
  const brand = typeof body.brand === "string" ? body.brand.trim() : null;
  const applianceCategory = typeof body.applianceCategory === "string" ? body.applianceCategory.trim() : null;
  const msrp = Number(body.msrp ?? 0);
  const source = String(body.source ?? OPERATOR_CONFIRMED_SOURCE).trim() || OPERATOR_CONFIRMED_SOURCE;
  const confidence = Number(body.confidence ?? 0);
  const aliasModelNumbers = Array.isArray(body.aliasModelNumbers)
    ? body.aliasModelNumbers.map((value) => String(value ?? ""))
    : [];

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
    },
  );

  try {
    const data = await upsertCatalogEntry(supabase, {
      normalizedModelNumber,
      productName,
      brand,
      applianceCategory,
      msrp,
      source,
      confidence,
    });

    await upsertModelAliases(supabase, normalizedModelNumber, aliasModelNumbers);

    return Response.json({
      normalizedModelNumber: data.normalized_model_number,
      productName: data.product_name,
      brand: data.brand ?? null,
      applianceCategory: data.appliance_category ?? null,
      msrp: Number(data.msrp),
      source: String(data.source || OPERATOR_CONFIRMED_SOURCE),
      confidence: Number(data.confidence ?? 0),
      status: "confirmed",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: message || "Unable to confirm product" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
