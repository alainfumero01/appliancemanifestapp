import { createClient } from "jsr:@supabase/supabase-js@2";

export type AuthenticatedOrgContext = {
  userID: string;
  email: string | null;
  orgID: string;
};

export type InventoryMetadata = {
  productName: string;
  brand: string | null;
  applianceCategory: string | null;
};

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function serviceRoleClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    {
      auth: { autoRefreshToken: false, persistSession: false },
    },
  );
}

function readToken(request: Request) {
  return request.headers.get("X-User-Token")?.trim()
    ?? (request.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
}

export async function requireAuthenticatedOrgContext(
  admin: ReturnType<typeof createClient>,
  request: Request,
): Promise<AuthenticatedOrgContext> {
  const token = readToken(request);
  if (!token) {
    throw new Error("Unauthorized");
  }

  const { data: authData } = await admin.auth.getUser(token);
  const user = authData.user;
  if (!user) {
    throw new Error("Unauthorized");
  }

  const { data: profile } = await admin
    .from("profiles")
    .select("org_id,email")
    .eq("id", user.id)
    .maybeSingle<{ org_id: string | null; email: string | null }>();

  if (!profile?.org_id) {
    throw new Error("Organization access not found.");
  }

  const { data: membership } = await admin
    .from("org_members")
    .select("org_id")
    .eq("org_id", profile.org_id)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!membership) {
    throw new Error("Organization access not found.");
  }

  return {
    userID: user.id,
    email: profile.email ?? user.email ?? null,
    orgID: profile.org_id,
  };
}

export function normalizeApplianceCategory(value: string | null | undefined) {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!normalized) {
    return null;
  }

  if (normalized.includes("refrigerator") || normalized.includes("fridge")) return "refrigerator";
  if (normalized.includes("washer")) return "washer";
  if (normalized.includes("dryer")) return "dryer";
  if (normalized.includes("dishwasher")) return "dishwasher";
  if (normalized.includes("microwave")) return "microwave";
  if (normalized.includes("cooktop")) return "cooktop";
  if (normalized.includes("range")) return "range";
  if (normalized.includes("oven")) return "oven";
  if (normalized.includes("freezer")) return "freezer";
  if (normalized.includes("air conditioner") || normalized.includes("a/c")) return "air-conditioner";
  if (normalized.includes("water heater")) return "water-heater";
  return normalized;
}

export function deriveApplianceCategory(productName: string) {
  const name = productName.toLowerCase();
  if (name.includes("refrigerator") || name.includes("fridge")) return "refrigerator";
  if (name.includes("washer")) return "washer";
  if (name.includes("dryer")) return "dryer";
  if (name.includes("dishwasher")) return "dishwasher";
  if (name.includes("microwave")) return "microwave";
  if (name.includes("cooktop")) return "cooktop";
  if (name.includes("range")) return "range";
  if (name.includes("oven")) return "oven";
  if (name.includes("freezer")) return "freezer";
  if (name.includes("air conditioner") || name.includes(" a/c")) return "air-conditioner";
  if (name.includes("water heater")) return "water-heater";
  return null;
}

export function deriveBrand(productName: string) {
  const cleaned = productName.trim();
  if (!cleaned) return null;
  const firstToken = cleaned.split(/\s+/)[0]?.trim();
  if (!firstToken) return null;
  return firstToken
    .replace(/[^A-Za-z0-9&-]/g, "")
    .slice(0, 40) || null;
}

export async function enrichInventoryMetadata(
  admin: ReturnType<typeof createClient>,
  args: {
    modelNumber: string;
    productName: string;
    brand?: string | null;
    applianceCategory?: string | null;
  },
): Promise<InventoryMetadata> {
  const normalizedModelNumber = String(args.modelNumber ?? "").trim().toUpperCase();
  const fallbackName = String(args.productName ?? "").trim();
  let productName = fallbackName;
  let brand = args.brand?.trim() || null;
  let applianceCategory = normalizeApplianceCategory(args.applianceCategory);

  if (normalizedModelNumber) {
    const { data: catalog } = await admin
      .from("product_catalog")
      .select("product_name,brand,appliance_category")
      .eq("normalized_model_number", normalizedModelNumber)
      .maybeSingle<{ product_name: string; brand: string | null; appliance_category: string | null }>();

    if (catalog) {
      if (!productName) {
        productName = catalog.product_name;
      }
      if (!brand) {
        brand = catalog.brand?.trim() || null;
      }
      if (!applianceCategory) {
        applianceCategory = normalizeApplianceCategory(catalog.appliance_category);
      }
    }
  }

  if (!brand) {
    brand = deriveBrand(productName);
  }
  if (!applianceCategory) {
    applianceCategory = deriveApplianceCategory(productName);
  }

  return {
    productName,
    brand,
    applianceCategory,
  };
}
