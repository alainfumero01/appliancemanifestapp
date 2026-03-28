import { createClient } from "jsr:@supabase/supabase-js@2";

type IngestResponse = {
  normalizedModelNumber: string;
  productName: string;
  msrp: number;
  source: string;
  confidence: number;
  status: string;
};

type ProductCatalogRow = {
  normalized_model_number: string;
  product_name: string;
  msrp: number;
  source: string | null;
  confidence: number;
};

type VerificationResult = {
  verdict: "verified" | "uncertain" | "mismatch";
  correctedModelNumber: string;
  confidence: number;
  notes: string;
};

const FRESH_AI_SOURCE = "model-ai-msrp-v2";

function shouldUseCachedCatalogEntry(source: unknown): boolean {
  const normalized = String(source ?? "")
    .trim()
    .toLowerCase();
  return normalized != "model-ai";
}

function normalizeModelNumber(value: unknown): string {
  return String(value ?? "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .trim();
}

function toResponse(row: ProductCatalogRow): IngestResponse {
  return {
    normalizedModelNumber: row.normalized_model_number,
    productName: row.product_name,
    msrp: Number(row.msrp),
    source: String(row.source || "catalog-cache"),
    confidence: Number(row.confidence ?? 0),
    status: "cached",
  };
}

async function fetchCachedCandidate(supabase: ReturnType<typeof createClient>, normalized: string) {
  const { data } = await supabase
    .from("product_catalog")
    .select("normalized_model_number, product_name, msrp, source, confidence")
    .eq("normalized_model_number", normalized)
    .maybeSingle<ProductCatalogRow>();

  if (!data || !shouldUseCachedCatalogEntry(data.source)) {
    return null;
  }

  return toResponse(data);
}

async function lookupCandidateWithAI(openAIKey: string, normalized: string): Promise<IngestResponse> {
  const lookupPrompt = `You are helping an internal appliance resale team verify and price items.
Given the model number "${normalized}", determine:
1. Whether this is a home appliance (refrigerator, washer, dryer, dishwasher, oven, range, microwave, freezer, air conditioner, water heater, etc.)
2. If it IS an appliance: the most likely full product name, the ORIGINAL manufacturer MSRP / list price in US dollars at full retail, a short source note, the price type, and confidence.

Important MSRP rules:
- MSRP means the original list price or manufacturer suggested retail price.
- Do NOT use the current sale price, promo price, discounted price, outlet price, open-box price, refurbished price, used price, or marketplace resale price.
- If both a crossed-out/original price and a lower current price exist, use the higher original MSRP.
- If you cannot confidently determine the original MSRP, set msrp to 0, priceType to "unknown", and lower confidence.

Return ONLY valid JSON:
{
  "isAppliance": true,
  "productName": "Brand Appliance Type Model",
  "msrp": 799.00,
  "priceType": "original_msrp",
  "source": "manufacturer or retailer evidence",
  "confidence": 0.92
}

If this is NOT a home appliance, return:
{
  "isAppliance": false,
  "productName": "",
  "msrp": 0,
  "priceType": "unknown",
  "source": "",
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
    throw new Error(`OpenAI lookup error: ${err}`);
  }

  const aiData = await aiResponse.json();
  const content = aiData.choices?.[0]?.message?.content ?? "{}";

  let parsed: {
    isAppliance?: boolean;
    productName?: string;
    msrp?: number;
    priceType?: string;
    source?: string;
    confidence?: number;
  } = {};
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new Error("Failed to parse product lookup response");
  }

  if (parsed.isAppliance === false) {
    throw new Error("not_appliance");
  }

  return {
    normalizedModelNumber: normalized,
    productName: String(parsed.productName ?? ""),
    msrp: parsed.priceType === "original_msrp" ? Number(parsed.msrp ?? 0) : 0,
    source: FRESH_AI_SOURCE,
    confidence: Number(parsed.confidence ?? 0),
    status: "aiSuggested",
  };
}

async function resolveCandidate(
  supabase: ReturnType<typeof createClient>,
  openAIKey: string,
  normalized: string,
): Promise<IngestResponse> {
  const cached = await fetchCachedCandidate(supabase, normalized);
  if (cached) {
    return cached;
  }
  return await lookupCandidateWithAI(openAIKey, normalized);
}

async function verifyCandidateAgainstImage(
  openAIKey: string,
  imageBase64: string,
  candidate: IngestResponse,
): Promise<VerificationResult> {
  const prompt = `You are double-checking an appliance sticker read.

Inspect only the image and decide whether it supports this proposed result:
- Proposed model number: ${candidate.normalizedModelNumber}
- Proposed product name: ${candidate.productName}

Rules:
- Focus on whether the sticker/data plate actually supports the proposed MODEL NUMBER.
- If the proposed model number clearly matches what is visible, verdict should be "verified".
- If the image is too blurry, partial, or ambiguous to confirm the exact model, verdict should be "uncertain".
- If the image clearly suggests a different model number or clearly conflicts with the proposed result, verdict should be "mismatch".
- If you can read a better/corrected model number, return it in correctedModelNumber using uppercase letters and digits only.
- Only use correctedModelNumber when the image itself strongly supports it.

Return ONLY valid JSON:
{
  "verdict": "verified",
  "correctedModelNumber": "",
  "confidence": 0.93,
  "notes": "short reason"
}`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
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
                detail: "high",
              },
            },
            {
              type: "text",
              text: prompt,
            },
          ],
        },
      ],
      response_format: { type: "json_object" },
      max_tokens: 180,
    }),
  });

  if (!response.ok) {
    throw new Error("Verification request failed");
  }

  const data = await response.json();
  const content = data.choices?.[0]?.message?.content ?? "{}";
  const parsed = JSON.parse(content);

  return {
    verdict: parsed.verdict === "verified" || parsed.verdict === "mismatch" ? parsed.verdict : "uncertain",
    correctedModelNumber: normalizeModelNumber(parsed.correctedModelNumber),
    confidence: Number(parsed.confidence ?? 0),
    notes: String(parsed.notes ?? ""),
  };
}

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

  const normalized = normalizeModelNumber(extracted.modelNumber);

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

  let candidate: IngestResponse;
  try {
    candidate = await resolveCandidate(supabase, openAIKey, normalized);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message === "not_appliance") {
      return new Response(JSON.stringify({ error: "not_appliance" }), {
        status: 422,
        headers: { "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ error: message }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const verification = await verifyCandidateAgainstImage(openAIKey, imageBase64, candidate);

    if (verification.verdict === "mismatch"
      && verification.correctedModelNumber
      && verification.correctedModelNumber !== candidate.normalizedModelNumber) {
      try {
        candidate = await resolveCandidate(supabase, openAIKey, verification.correctedModelNumber);
      } catch {
        candidate = {
          ...candidate,
          normalizedModelNumber: verification.correctedModelNumber,
        };
      }
    }

    if (verification.verdict !== "verified") {
      candidate = {
        ...candidate,
        confidence: Math.min(
          candidate.confidence,
          verification.confidence > 0 ? verification.confidence : 0.45,
        ),
        status: "needsReview",
      };
    }
  } catch {
    candidate = {
      ...candidate,
      confidence: Math.min(candidate.confidence, 0.5),
      status: "needsReview",
    };
  }

  return Response.json(candidate);
});
