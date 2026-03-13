import { createClient } from "jsr:@supabase/supabase-js@2";

type LookupResponse = {
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

  if (cached) {
    const response: LookupResponse = {
      normalizedModelNumber: cached.normalized_model_number,
      productName: cached.product_name,
      msrp: Number(cached.msrp),
      source: cached.source,
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

  const prompt = `You are helping an internal appliance resale team. Given the model number "${normalized}", infer the most likely appliance name and current MSRP. Respond only as JSON with keys productName, msrp, source, confidence.`;
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
              productName: { type: "string" },
              msrp: { type: "number" },
              source: { type: "string" },
              confidence: { type: "number" }
            },
            required: ["productName", "msrp", "source", "confidence"],
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

  const response: LookupResponse = {
    normalizedModelNumber: normalized,
    productName: parsed.productName,
    msrp: Number(parsed.msrp),
    source: parsed.source,
    confidence: Number(parsed.confidence),
    status: "aiSuggested"
  };

  return Response.json(response);
});
