import { createClient } from "jsr:@supabase/supabase-js@2";

export type LookupResponse = {
  normalizedModelNumber: string;
  productName: string;
  msrp: number;
  source: string;
  confidence: number;
  status: string;
};

type CatalogProductRow = {
  normalized_model_number: string;
  product_name: string;
  msrp: number;
  source: string | null;
  confidence: number;
};

type ProductLookupCandidateRow = {
  normalized_model_number: string;
  product_name: string;
  msrp: number;
  source: string | null;
  confidence: number;
  verification_state: string | null;
  hit_count: number | null;
};

type ModelAliasRow = {
  alias_model_number: string;
  canonical_model_number: string;
  source: string | null;
  confidence: number | null;
  hit_count: number | null;
};

export type LookupLayer = "catalog" | "alias_catalog" | "candidate" | "alias_candidate" | "ai" | "not_appliance";

export type ResolvedLookup = {
  response: LookupResponse;
  layer: LookupLayer;
};

export const LEGACY_AI_SOURCE = "model-ai";
export const FRESH_AI_SOURCE = "model-ai-msrp-v2";
export const OPERATOR_CONFIRMED_SOURCE = "operator-confirmed";

function normalizeSource(source: unknown): string {
  return String(source ?? "").trim().toLowerCase();
}

export function normalizeModelNumber(value: unknown): string {
  return String(value ?? "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .trim();
}

export function isTrustedCatalogSource(source: unknown): boolean {
  const normalized = normalizeSource(source);
  return normalized.length > 0 && !normalized.startsWith("model-ai");
}

export function canonicalConfirmedSource(source: unknown): string {
  const normalized = normalizeSource(source);
  if (normalized === "bestbuy-catalog") {
    return normalized;
  }
  if (normalized === OPERATOR_CONFIRMED_SOURCE) {
    return normalized;
  }
  return OPERATOR_CONFIRMED_SOURCE;
}

function toCatalogResponse(row: CatalogProductRow, status: string): LookupResponse {
  return {
    normalizedModelNumber: row.normalized_model_number,
    productName: row.product_name,
    msrp: Number(row.msrp ?? 0),
    source: String(row.source || "catalog-cache"),
    confidence: Number(row.confidence ?? 0),
    status,
  };
}

function toCandidateResponse(row: ProductLookupCandidateRow, status: string): LookupResponse {
  return {
    normalizedModelNumber: row.normalized_model_number,
    productName: row.product_name,
    msrp: Number(row.msrp ?? 0),
    source: String(row.source || FRESH_AI_SOURCE),
    confidence: Number(row.confidence ?? 0),
    status,
  };
}

async function fetchTrustedCatalogRow(
  supabase: ReturnType<typeof createClient>,
  normalizedModelNumber: string,
): Promise<CatalogProductRow | null> {
  const { data, error } = await supabase
    .from("product_catalog")
    .select("normalized_model_number, product_name, msrp, source, confidence")
    .eq("normalized_model_number", normalizedModelNumber)
    .maybeSingle<CatalogProductRow>();

  if (error) {
    throw error;
  }

  if (!data || !isTrustedCatalogSource(data.source)) {
    return null;
  }

  return data;
}

async function fetchProvisionalCandidateRow(
  supabase: ReturnType<typeof createClient>,
  normalizedModelNumber: string,
): Promise<ProductLookupCandidateRow | null> {
  const { data, error } = await supabase
    .from("product_lookup_candidates")
    .select("normalized_model_number, product_name, msrp, source, confidence, verification_state, hit_count")
    .eq("normalized_model_number", normalizedModelNumber)
    .neq("verification_state", "rejected")
    .maybeSingle<ProductLookupCandidateRow>();

  if (error) {
    throw error;
  }

  return data ?? null;
}

async function fetchModelAliasRow(
  supabase: ReturnType<typeof createClient>,
  aliasModelNumber: string,
): Promise<ModelAliasRow | null> {
  const { data, error } = await supabase
    .from("model_aliases")
    .select("alias_model_number, canonical_model_number, source, confidence, hit_count")
    .eq("alias_model_number", aliasModelNumber)
    .maybeSingle<ModelAliasRow>();

  if (error) {
    throw error;
  }

  return data ?? null;
}

async function touchCandidate(
  supabase: ReturnType<typeof createClient>,
  candidate: ProductLookupCandidateRow,
): Promise<ProductLookupCandidateRow> {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from("product_lookup_candidates")
    .update({
      hit_count: Number(candidate.hit_count ?? 0) + 1,
      last_seen_at: now,
      last_used_at: now,
    })
    .eq("normalized_model_number", candidate.normalized_model_number)
    .select("normalized_model_number, product_name, msrp, source, confidence, verification_state, hit_count")
    .single<ProductLookupCandidateRow>();

  if (error) {
    throw error;
  }

  return data;
}

async function touchAlias(
  supabase: ReturnType<typeof createClient>,
  alias: ModelAliasRow,
): Promise<void> {
  await supabase
    .from("model_aliases")
    .update({
      hit_count: Number(alias.hit_count ?? 0) + 1,
      last_seen_at: new Date().toISOString(),
    })
    .eq("alias_model_number", alias.alias_model_number);
}

export async function upsertCatalogEntry(
  supabase: ReturnType<typeof createClient>,
  entry: {
    normalizedModelNumber: string;
    productName: string;
    msrp: number;
    source: string;
    confidence: number;
  },
): Promise<CatalogProductRow> {
  const payload = {
    normalized_model_number: normalizeModelNumber(entry.normalizedModelNumber),
    product_name: String(entry.productName).trim(),
    msrp: Number(entry.msrp ?? 0),
    source: canonicalConfirmedSource(entry.source),
    confidence: Number(entry.confidence ?? 0),
    last_verified_at: new Date().toISOString(),
  };

  const { data, error } = await supabase
    .from("product_catalog")
    .upsert(payload, { onConflict: "normalized_model_number" })
    .select("normalized_model_number, product_name, msrp, source, confidence")
    .single<CatalogProductRow>();

  if (error) {
    throw error;
  }

  await supabase
    .from("product_lookup_candidates")
    .update({
      verification_state: "confirmed",
      last_promoted_at: new Date().toISOString(),
      last_seen_at: new Date().toISOString(),
      last_used_at: new Date().toISOString(),
    })
    .eq("normalized_model_number", payload.normalized_model_number);

  return data;
}
export async function upsertModelAliases(
  supabase: ReturnType<typeof createClient>,
  canonicalModelNumber: string,
  aliasModelNumbers: string[],
  source = "operator-correction",
): Promise<void> {
  const canonical = normalizeModelNumber(canonicalModelNumber);
  if (!canonical) {
    return;
  }

  const rows = Array.from(new Set(
    aliasModelNumbers
      .map((value) => normalizeModelNumber(value))
      .filter((value) => value.length > 0 && value !== canonical),
  )).map((aliasModelNumber) => ({
    alias_model_number: aliasModelNumber,
    canonical_model_number: canonical,
    source,
    confidence: 1,
    last_seen_at: new Date().toISOString(),
  }));

  if (rows.length === 0) {
    return;
  }

  const { error } = await supabase
    .from("model_aliases")
    .upsert(rows, { onConflict: "alias_model_number" });

  if (error) {
    throw error;
  }

  for (const row of rows) {
    await supabase
      .from("product_lookup_candidates")
      .delete()
      .eq("normalized_model_number", row.alias_model_number);
  }
}

async function upsertProvisionalCandidate(
  supabase: ReturnType<typeof createClient>,
  response: LookupResponse,
): Promise<ProductLookupCandidateRow> {
  const now = new Date().toISOString();
  const payload = {
    normalized_model_number: normalizeModelNumber(response.normalizedModelNumber),
    product_name: String(response.productName ?? "").trim(),
    msrp: Number(response.msrp ?? 0),
    source: String(response.source ?? FRESH_AI_SOURCE).trim() || FRESH_AI_SOURCE,
    confidence: Number(response.confidence ?? 0),
    verification_state: "provisional",
    hit_count: 1,
    first_seen_at: now,
    last_seen_at: now,
    last_used_at: now,
  };

  const { data, error } = await supabase
    .from("product_lookup_candidates")
    .upsert(payload, { onConflict: "normalized_model_number" })
    .select("normalized_model_number, product_name, msrp, source, confidence, verification_state, hit_count")
    .single<ProductLookupCandidateRow>();

  if (error) {
    throw error;
  }

  return data;
}

async function recordLookupLog(
  supabase: ReturnType<typeof createClient>,
  entry: {
    queryModelNumber: string;
    normalizedQueryModelNumber: string;
    resolvedModelNumber: string;
    lookupLayer: LookupLayer;
    responseStatus: string;
    resolvedSource: string;
    confidence: number;
  },
): Promise<void> {
  await supabase.from("product_lookup_logs").insert({
    query_model_number: entry.queryModelNumber,
    normalized_query_model_number: entry.normalizedQueryModelNumber,
    resolved_model_number: entry.resolvedModelNumber,
    lookup_layer: entry.lookupLayer,
    response_status: entry.responseStatus,
    resolved_source: entry.resolvedSource,
    confidence: entry.confidence,
  });
}

async function lookupCandidateWithAI(openAIKey: string, normalized: string): Promise<LookupResponse> {
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
      "Content-Type": "application/json",
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
              confidence: { type: "number" },
            },
            required: ["isAppliance", "productName", "msrp", "priceType", "source", "confidence"],
            additionalProperties: false,
          },
        },
      },
    }),
  });

  if (!aiResponse.ok) {
    throw new Error("AI lookup failed.");
  }

  const aiData = await aiResponse.json();
  const outputText = aiData.output?.[0]?.content?.[0]?.text ?? "{}";
  const parsed = JSON.parse(outputText);

  if (parsed.isAppliance === false) {
    throw new Error("not_appliance");
  }

  return {
    normalizedModelNumber: normalized,
    productName: String(parsed.productName ?? "").trim(),
    msrp: parsed.priceType === "original_msrp" ? Number(parsed.msrp ?? 0) : 0,
    source: FRESH_AI_SOURCE,
    confidence: Number(parsed.confidence ?? 0),
    status: "aiSuggested",
  };
}

export async function resolveLookup(
  supabase: ReturnType<typeof createClient>,
  openAIKey: string,
  queryModelNumber: string,
  options: { logLookup?: boolean } = {},
): Promise<ResolvedLookup> {
  const normalized = normalizeModelNumber(queryModelNumber);
  if (!normalized) {
    throw new Error("A model number is required.");
  }

  const shouldLog = options.logLookup ?? true;

  try {
    const directCatalog = await fetchTrustedCatalogRow(supabase, normalized);
    if (directCatalog) {
      const response = toCatalogResponse(directCatalog, "cached");
      if (shouldLog) {
        try {
          await recordLookupLog(supabase, {
            queryModelNumber,
            normalizedQueryModelNumber: normalized,
            resolvedModelNumber: response.normalizedModelNumber,
            lookupLayer: "catalog",
            responseStatus: response.status,
            resolvedSource: response.source,
            confidence: response.confidence,
          });
        } catch {}
      }
      return { response, layer: "catalog" };
    }

    const alias = await fetchModelAliasRow(supabase, normalized);
    if (alias) {
      await touchAlias(supabase, alias);

      const aliasCatalog = await fetchTrustedCatalogRow(supabase, alias.canonical_model_number);
      if (aliasCatalog) {
        const response = toCatalogResponse(aliasCatalog, "cached");
        if (shouldLog) {
          try {
            await recordLookupLog(supabase, {
              queryModelNumber,
              normalizedQueryModelNumber: normalized,
              resolvedModelNumber: response.normalizedModelNumber,
              lookupLayer: "alias_catalog",
              responseStatus: response.status,
              resolvedSource: response.source,
              confidence: response.confidence,
            });
          } catch {}
        }
        return { response, layer: "alias_catalog" };
      }

      const aliasCandidate = await fetchProvisionalCandidateRow(supabase, alias.canonical_model_number);
      if (aliasCandidate) {
        const touched = await touchCandidate(supabase, aliasCandidate);
        const response = toCandidateResponse(touched, "needsReview");
        if (shouldLog) {
          try {
            await recordLookupLog(supabase, {
              queryModelNumber,
              normalizedQueryModelNumber: normalized,
              resolvedModelNumber: response.normalizedModelNumber,
              lookupLayer: "alias_candidate",
              responseStatus: response.status,
              resolvedSource: response.source,
              confidence: response.confidence,
            });
          } catch {}
        }
        return { response, layer: "alias_candidate" };
      }
    }

    const directCandidate = await fetchProvisionalCandidateRow(supabase, normalized);
    if (directCandidate) {
      const touched = await touchCandidate(supabase, directCandidate);
      const response = toCandidateResponse(touched, "needsReview");
      if (shouldLog) {
        try {
          await recordLookupLog(supabase, {
            queryModelNumber,
            normalizedQueryModelNumber: normalized,
            resolvedModelNumber: response.normalizedModelNumber,
            lookupLayer: "candidate",
            responseStatus: response.status,
            resolvedSource: response.source,
            confidence: response.confidence,
          });
        } catch {}
      }
      return { response, layer: "candidate" };
    }

    const aiResponse = await lookupCandidateWithAI(openAIKey, normalized);
    await upsertProvisionalCandidate(supabase, aiResponse);
    if (shouldLog) {
      try {
        await recordLookupLog(supabase, {
          queryModelNumber,
          normalizedQueryModelNumber: normalized,
          resolvedModelNumber: aiResponse.normalizedModelNumber,
          lookupLayer: "ai",
          responseStatus: aiResponse.status,
          resolvedSource: aiResponse.source,
          confidence: aiResponse.confidence,
        });
      } catch {}
    }
    return { response: aiResponse, layer: "ai" };
  } catch (error) {
    if (error instanceof Error && error.message === "not_appliance" && shouldLog) {
      try {
        await recordLookupLog(supabase, {
          queryModelNumber,
          normalizedQueryModelNumber: normalized,
          resolvedModelNumber: normalized,
          lookupLayer: "not_appliance",
          responseStatus: "not_appliance",
          resolvedSource: "",
          confidence: 0,
        });
      } catch {}
    }
    throw error;
  }
}
