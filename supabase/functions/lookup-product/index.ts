import { createClient } from "jsr:@supabase/supabase-js@2";

type LookupResponse = {
  normalizedModelNumber: string;
  productName: string;
  msrp: number;
  source: string;
  confidence: number;
  status: string;
};

const FRESH_AI_SOURCE = "model-ai-msrp-v2";

function shouldUseCachedCatalogEntry(source: unknown): boolean {
  const normalized = String(source ?? "")
    .trim()
    .toLowerCase();
  return normalized != "model-ai";
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const { modelNumber } = await request.json();
  const normalized = String(modelNumber).toUpperCase().replace(/[^A-Z0-9]/g, "");

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    {
      global: {
        headers: { Authorization: authorization }
      },
      auth: { autoRefreshToken: false, persistSession: false }
    }
  );

  const { data: cached } = await supabase
    .from("product_catalog")
    .select("normalized_model_number, product_name, msrp, source, confidence")
    .eq("normalized_model_number", normalized)
    .maybeSingle();

  if (cached && shouldUseCachedCatalogEntry(cached.source)) {
    const response: LookupResponse = {
      normalizedModelNumber: cached.normalized_model_number,
      productName: cached.product_name,
      msrp: Number(cached.msrp),
      source: String(cached.source || "catalog-cache"),
      confidence: cached.confidence,
      status: "cached"
    };
    return Response.json(response);
  }

  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAIKey) {
    return new Response(JSON.stringify({ error: "OPENAI_API_KEY is not configured." }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }

  const prompt = `You are helping an internal appliance resale team verify and price items.

Given the model number "${normalized}", first determine if this is a home appliance (refrigerator, washer, dryer, dishwasher, oven, range, microwave, freezer, air conditioner, water heater, etc.).

If it IS a home appliance, return:
- the most likely full product name
- the ORIGINAL manufacturer MSRP / list price in US dollars at full retail
- a short source note
- confidence

Important MSRP rules:
- MSRP means the original list price or manufacturer suggested retail price.
- Do NOT use the current sale price, promo price, discounted price, outlet price, open-box price, refurbished price, used price, or marketplace resale price.
- If both a crossed-out/original price and a lower current price exist, use the higher original MSRP.
- If you cannot confidently determine the original MSRP, set msrp to 0, priceType to "unknown", and lower confidence.

If it is NOT a home appliance, set isAppliance to false and leave other fields empty/zero.`;
  const aiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: "gpt-4.1-mini",
      input: prompt,
      text: {
        format: {
          type: "json_schema",
          name: "product_lookup",
          schema: {
            type: "object",
            properties: {
              isAppliance: { type: "boolean" },
              productName: { type: "string" },
              msrp: { type: "number" },
              priceType: { type: "string", enum: ["original_msrp", "unknown"] },
              source: { type: "string" },
              confidence: { type: "number" }
            },
            required: ["isAppliance", "productName", "msrp", "priceType", "source", "confidence"],
            additionalProperties: false
          }
        }
      }
    })
  });

  if (!aiResponse.ok) {
    return new Response(JSON.stringify({ error: "AI lookup failed." }), {
      status: 502,
      headers: { "Content-Type": "application/json" }
    });
  }

  const aiData = await aiResponse.json();
  const outputText = aiData.output?.[0]?.content?.[0]?.text ?? "{}";
  const parsed = JSON.parse(outputText);

  if (parsed.isAppliance === false) {
    return new Response(JSON.stringify({ error: "not_appliance" }), {
      status: 422,
      headers: { "Content-Type": "application/json" }
    });
  }

  const response: LookupResponse = {
    normalizedModelNumber: normalized,
    productName: parsed.productName,
    msrp: parsed.priceType === "original_msrp" ? Number(parsed.msrp) : 0,
    source: FRESH_AI_SOURCE,
    confidence: Number(parsed.confidence),
    status: "aiSuggested"
  };

  return Response.json(response);
});
