import {
  enrichInventoryMetadata,
  json,
  requireAuthenticatedOrgContext,
  serviceRoleClient,
} from "../_shared/sellerInventory.ts";

type ManifestRow = {
  id: string;
  org_id: string | null;
  status: string;
  load_cost: number | null;
  updated_at: string;
};

type ManifestItemRow = {
  id: string;
  manifest_id: string;
  model_number: string;
  product_name: string;
  msrp: number;
  our_price: number | null;
  condition: string | null;
  quantity: number;
  photo_path: string | null;
  brand: string | null;
  appliance_category: string | null;
};

type InventoryUnitRow = {
  id: string;
  source_manifest_item_id: string | null;
  source_manifest_item_index: number | null;
  status: string;
  brand: string | null;
  appliance_category: string | null;
  asking_price: number;
};

function keyFor(itemID: string, index: number) {
  return `${itemID}:${index}`;
}

function normalizeSyncMode(value: unknown) {
  return value === "single" ? "single" : "org_backfill";
}

async function fetchManifestItems(admin: ReturnType<typeof serviceRoleClient>, manifestID: string) {
  const { data, error } = await admin
    .from("manifest_items")
    .select("id,manifest_id,model_number,product_name,msrp,our_price,condition,quantity,photo_path,brand,appliance_category")
    .eq("manifest_id", manifestID)
    .returns<ManifestItemRow[]>();

  if (error) {
    throw error;
  }

  return data ?? [];
}

async function fetchExistingUnits(admin: ReturnType<typeof serviceRoleClient>, manifestItemIDs: string[]) {
  if (manifestItemIDs.length === 0) {
    return new Map<string, InventoryUnitRow>();
  }

  const { data, error } = await admin
    .from("inventory_units")
    .select("id,source_manifest_item_id,source_manifest_item_index,status,brand,appliance_category,asking_price")
    .in("source_manifest_item_id", manifestItemIDs)
    .returns<InventoryUnitRow[]>();

  if (error) {
    throw error;
  }

  return new Map(
    (data ?? [])
      .filter((row) => row.source_manifest_item_id !== null && row.source_manifest_item_index !== null)
      .map((row) => [keyFor(row.source_manifest_item_id as string, row.source_manifest_item_index as number), row]),
  );
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const admin = serviceRoleClient();

  try {
    const context = await requireAuthenticatedOrgContext(admin, request);
    const body = await request.json().catch(() => ({}));
    const syncMode = normalizeSyncMode(body?.syncMode);
    const requestedManifestID = typeof body?.manifestID === "string" ? body.manifestID.trim() : "";

    let manifests: ManifestRow[] = [];

    if (syncMode === "single" && requestedManifestID) {
      const { data, error } = await admin
        .from("manifests")
        .select("id,org_id,status,load_cost,updated_at")
        .eq("id", requestedManifestID)
        .eq("org_id", context.orgID)
        .returns<ManifestRow[]>();

      if (error) {
        throw error;
      }
      manifests = data ?? [];
    } else {
      const { data, error } = await admin
        .from("manifests")
        .select("id,org_id,status,load_cost,updated_at")
        .eq("org_id", context.orgID)
        .order("created_at", { ascending: true })
        .returns<ManifestRow[]>();

      if (error) {
        throw error;
      }
      manifests = data ?? [];
    }

    let insertedCount = 0;
    let updatedCount = 0;

    for (const manifest of manifests) {
      const items = await fetchManifestItems(admin, manifest.id);
      const existingUnits = await fetchExistingUnits(admin, items.map((item) => item.id));
      const manifestTotalMSRP = items.reduce((sum, item) => sum + Number(item.msrp ?? 0) * Number(item.quantity ?? 0), 0);

      for (const item of items) {
        const metadata = await enrichInventoryMetadata(admin, {
          modelNumber: item.model_number,
          productName: item.product_name,
          brand: item.brand,
          applianceCategory: item.appliance_category,
        });

        const unitCostBasis = manifest.load_cost && manifestTotalMSRP > 0
          ? Number(((manifest.load_cost * (Number(item.msrp ?? 0) * Number(item.quantity ?? 0))) / manifestTotalMSRP) / Math.max(Number(item.quantity ?? 1), 1))
          : null;

        for (let index = 0; index < Math.max(Number(item.quantity ?? 0), 0); index += 1) {
          const existing = existingUnits.get(keyFor(item.id, index));
          if (existing) {
            const updatePayload: Record<string, unknown> = {};

            if (!existing.brand && metadata.brand) {
              updatePayload.brand = metadata.brand;
            }
            if (!existing.appliance_category && metadata.applianceCategory) {
              updatePayload.appliance_category = metadata.applianceCategory;
            }
            if ((existing.asking_price ?? 0) === 0 && Number(item.our_price ?? 0) > 0) {
              updatePayload.asking_price = Number(item.our_price ?? 0);
            }
            if (manifest.status === "sold" && existing.status !== "sold") {
              updatePayload.status = "sold";
              updatePayload.sold_price = Number(item.our_price ?? 0);
              updatePayload.sold_at = manifest.updated_at;
            }

            if (Object.keys(updatePayload).length > 0) {
              const { error } = await admin
                .from("inventory_units")
                .update(updatePayload)
                .eq("id", existing.id);

              if (error) {
                throw error;
              }
              updatedCount += 1;
            }
            continue;
          }

          const { error } = await admin
            .from("inventory_units")
            .insert({
              org_id: context.orgID,
              source_manifest_id: manifest.id,
              source_manifest_item_id: item.id,
              source_manifest_item_index: index,
              model_number: item.model_number,
              product_name: metadata.productName,
              brand: metadata.brand,
              appliance_category: metadata.applianceCategory,
              msrp: Number(item.msrp ?? 0),
              asking_price: Number(item.our_price ?? 0),
              cost_basis: unitCostBasis,
              sold_price: manifest.status === "sold" ? Number(item.our_price ?? 0) : null,
              condition: item.condition ?? "used",
              status: manifest.status === "sold" ? "sold" : "in_stock",
              photo_path: item.photo_path,
              sold_at: manifest.status === "sold" ? manifest.updated_at : null,
            });

          if (error) {
            throw error;
          }
          insertedCount += 1;
        }
      }
    }

    return json({
      syncedManifestCount: manifests.length,
      insertedCount,
      updatedCount,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message === "Unauthorized" ? 401 : 400;
    return json({ error: message || "Unable to sync inventory." }, status);
  }
});
