import { createClient } from "jsr:@supabase/supabase-js@2";

type IngestResponse = {
  normalizedModelNumber: string;
  productName: string;
  msrp: number;
  source: string;
  confidence: number;
  status: string;
};

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const { imageBase64 } = await request.json();

  if (!imageBase64 || typeof imageBase64 !== "string") {
    return new Response(JSON.stringify({ error: "imageBase64 is required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAIKey) {
    return new Response(JSON.stringify({ error: "OPENAI_API_KEY is not configured" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const extractPrompt = `You are analyzing a photo of an appliance sticker, data plate, or energy label.
Your task is to identify the PRODUCT MODEL NUMBER only.

Treat these as strong model-number clues:
- It often appears near labels such as: "Model", "Model No", "Model #", "Mod.", "M/N", "Modelo", "Modèle", "Type", or "Item No."
- It is usually 5 to 20 characters long.
- It is often a mix of uppercase letters and digits.
- It may contain a small number of hyphens, but should be normalized without spaces or punctuation in the final output.

Do NOT return:
- Serial numbers or S/N values
- UPC, EAN, barcodes, or long all-digit codes
- Electrical specs like 120V, 60Hz, 15A, 1500W
- FCC IDs, UL numbers, dates, revision codes, or capacities

Rules:
- If both model and serial are visible, always choose the model.
- If multiple codes are visible, prefer the one explicitly labeled as model.
- If uncertain, return an empty string.
- Normalize the result to uppercase letters and digits only.

Return ONLY valid JSON:
{"modelNumber":"EXTRACTEDMODEL"}

If you cannot confidently identify a model number, return:
{"modelNumber":""}`;

  const extractAIResponse = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image_url",
              image_url: {
                url: `data:image/jpeg;base64,${imageBase64}`,
                detail: "low",
              },
            },
            {
              type: "text",
              text: extractPrompt,
            },
          ],
        },
      ],
      response_format: { type: "json_object" },
      max_tokens: 100,
    }),
  });

  if (!extractAIResponse.ok) {
    const err = await extractAIResponse.text();
    return new Response(JSON.stringify({ error: `Model extraction failed: ${err}` }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  const extractAIData = await extractAIResponse.json();
  const extractContent = extractAIData.choices?.[0]?.message?.content ?? "{}";

  let extracted: { modelNumber?: string } = {};
  try {
    extracted = JSON.parse(extractContent);
  } catch {
    return new Response(JSON.stringify({ error: "Failed to parse model extraction response" }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  const normalized = String(extracted.modelNumber ?? "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .trim();

  if (!normalized) {
    return new Response(JSON.stringify({ error: "Could not identify model number from image" }), {
      status: 422,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Check if this model is already in the product catalog
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    {
      global: { headers: { Authorization: authorization } },
      auth: { autoRefreshToken: false, persistSession: false },
    }
  );

  const { data: cached } = await supabase
    .from("product_catalog")
    .select("normalized_model_number, product_name, msrp, source, confidence")
    .eq("normalized_model_number", normalized)
    .maybeSingle();

  if (cached) {
    const response: IngestResponse = {
      normalizedModelNumber: cached.normalized_model_number,
      productName: cached.product_name,
      msrp: Number(cached.msrp),
      source: "catalog-cache",
      confidence: cached.confidence,
      status: "cached",
    };
    return Response.json(response);
  }

  const lookupPrompt = `You are helping an internal appliance resale team verify and price items.
Given the model number "${normalized}", determine:
1. Whether this is a home appliance (refrigerator, washer, dryer, dishwasher, oven, range, microwave, freezer, air conditioner, water heater, etc.)
2. If it IS an appliance: the most likely full product name, realistic current US MSRP in dollars, and confidence.

Return ONLY valid JSON:
{
  "isAppliance": true,
  "productName": "Brand Appliance Type Model",
  "msrp": 799.00,
  "confidence": 0.92
}

If this is NOT a home appliance, return:
{
  "isAppliance": false,
  "productName": "",
  "msrp": 0,
  "confidence": 0
}`;

  const aiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "user",
          content: lookupPrompt,
        },
      ],
      response_format: { type: "json_object" },
      max_tokens: 180,
    }),
  });

  if (!aiResponse.ok) {
    const err = await aiResponse.text();
    return new Response(JSON.stringify({ error: `OpenAI lookup error: ${err}` }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  const aiData = await aiResponse.json();
  const content = aiData.choices?.[0]?.message?.content ?? "{}";

  let parsed: { isAppliance?: boolean; productName?: string; msrp?: number; confidence?: number } = {};
  try {
    parsed = JSON.parse(content);
  } catch {
    return new Response(JSON.stringify({ error: "Failed to parse product lookup response" }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (parsed.isAppliance === false) {
    return new Response(JSON.stringify({ error: "not_appliance" }), {
      status: 422,
      headers: { "Content-Type": "application/json" },
    });
  }

  const response: IngestResponse = {
    normalizedModelNumber: normalized,
    productName: String(parsed.productName ?? ""),
    msrp: Number(parsed.msrp ?? 0),
    source: "model-ai",
    confidence: Number(parsed.confidence ?? 0),
    status: "aiSuggested",
  };
  return Response.json(response);
});
