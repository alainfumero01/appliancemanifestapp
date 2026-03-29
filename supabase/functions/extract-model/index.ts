import { normalizeModelNumber } from "../_shared/catalogLookup.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

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

  const prompt = `You are analyzing a photo of an appliance sticker, data plate, or energy label.
Your task is to identify the PRODUCT MODEL NUMBER only.

You must distinguish the model number from other values commonly present on appliance labels.

Treat these as strong model-number clues:
- It often appears near labels such as: "Model", "Model No", "Model #", "Mod.", "M/N", "Modelo", "Modèle", "Type", or "Item No."
- It is usually 5 to 20 characters long.
- It is often a mix of uppercase letters and digits.
- It may contain a small number of hyphens, but should be normalized without spaces or punctuation in the final output.
- Example patterns: WRF560SEHZ, RF28R7351SG, FFHB2750TS7A, GDF570SGJWW.

Do NOT return any of the following:
- Serial numbers or S/N values
- UPC, EAN, barcodes, or long all-digit product codes
- Electrical specs like 120V, 60Hz, 15A, 1500W
- FCC IDs, UL numbers, manufacturing dates, or revision numbers
- Capacity values, color codes, or internal factory codes unless they are clearly the model number

Decision rules:
- If both model and serial are visible, always choose the model.
- If multiple codes are visible, prefer the one explicitly labeled as model.
- If the best candidate is uncertain or only weakly implied, return an empty string.
- Normalize the result to uppercase letters and digits only.

Return ONLY valid JSON with exactly this shape and no extra text:
{"modelNumber":"EXTRACTEDMODEL"}

If you cannot confidently identify a model number, return:
{"modelNumber":""}`;

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
      max_tokens: 100,
    }),
  });

  if (!aiResponse.ok) {
    const err = await aiResponse.text();
    return new Response(JSON.stringify({ error: `OpenAI error: ${err}` }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  const aiData = await aiResponse.json();
  const content = aiData.choices?.[0]?.message?.content ?? "{}";

  let modelNumber = "";
  try {
    const parsed = JSON.parse(content);
    modelNumber = normalizeModelNumber(parsed.modelNumber);
  } catch {
    modelNumber = "";
  }

  return Response.json({ modelNumber });
});
