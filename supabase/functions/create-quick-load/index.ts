import {
  json,
  requireAuthenticatedOrgContext,
  serviceRoleClient,
} from "../_shared/sellerInventory.ts";

type InventoryUnitRow = {
  id: string;
  org_id: string;
  model_number: string;
  product_name: string;
  brand: string | null;
  appliance_category: string | null;
  msrp: number;
  asking_price: number;
  condition: string;
  photo_path: string | null;
  status: string;
};

type GroupedUnitBucket = {
  manifestItemID: string;
  modelNumber: string;
  productName: string;
  brand: string | null;
  applianceCategory: string | null;
  msrp: number;
  ourPrice: number;
  condition: string;
  photoPath: string | null;
  unitIDs: string[];
};

function groupKey(unit: InventoryUnitRow) {
  return [
    unit.model_number,
    unit.product_name,
    unit.brand ?? "",
    unit.appliance_category ?? "",
    Number(unit.msrp ?? 0).toFixed(2),
    Number(unit.asking_price ?? 0).toFixed(2),
    unit.condition,
    unit.photo_path ?? "",
  ].join("::");
}

function buildLoadReference() {
  return `LOAD-${Math.floor(Date.now() / 1000)}`;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const admin = serviceRoleClient();
  let createdManifestID: string | null = null;

  try {
    const context = await requireAuthenticatedOrgContext(admin, request);
    const body = await request.json().catch(() => null);
    const title = String(body?.title ?? "").trim() || "Inventory Load";
    const loadReference = String(body?.loadReference ?? "").trim() || buildLoadReference();
    const inventoryUnitIDs = Array.isArray(body?.inventoryUnitIDs)
      ? Array.from(new Set(body.inventoryUnitIDs.map((value: unknown) => String(value ?? "").trim()).filter(Boolean)))
      : [];

    if (inventoryUnitIDs.length === 0) {
      return json({ error: "At least one inventory unit is required." }, 400);
    }

    const { data: selectedUnits, error: unitsError } = await admin
      .from("inventory_units")
      .select("id,org_id,model_number,product_name,brand,appliance_category,msrp,asking_price,condition,photo_path,status")
      .in("id", inventoryUnitIDs)
      .eq("org_id", context.orgID)
      .returns<InventoryUnitRow[]>();

    if (unitsError) {
      throw unitsError;
    }

    const units = selectedUnits ?? [];
    if (units.length != inventoryUnitIDs.length) {
      return json({ error: "Some selected inventory units were not found." }, 404);
    }

    if (units.some((unit) => unit.status !== "in_stock" && unit.status !== "listed")) {
      return json({ error: "Only in-stock or listed inventory can be added to a quick load." }, 409);
    }

    const now = new Date().toISOString();
    createdManifestID = crypto.randomUUID();

    const { error: manifestError } = await admin
      .from("manifests")
      .insert({
        id: createdManifestID,
        owner_id: context.userID,
        title,
        load_reference: loadReference,
        status: "draft",
        org_id: context.orgID,
        created_at: now,
        updated_at: now,
      });

    if (manifestError) {
      throw manifestError;
    }

    const grouped = new Map<string, GroupedUnitBucket>();
    for (const unit of units) {
      const key = groupKey(unit);
      const existing = grouped.get(key);
      if (existing) {
        existing.unitIDs.push(unit.id);
        continue;
      }
      grouped.set(key, {
        manifestItemID: crypto.randomUUID(),
        modelNumber: unit.model_number,
        productName: unit.product_name,
        brand: unit.brand,
        applianceCategory: unit.appliance_category,
        msrp: Number(unit.msrp ?? 0),
        ourPrice: Number(unit.asking_price ?? 0),
        condition: unit.condition,
        photoPath: unit.photo_path,
        unitIDs: [unit.id],
      });
    }

    const manifestItems = Array.from(grouped.values()).map((bucket) => ({
      id: bucket.manifestItemID,
      manifest_id: createdManifestID,
      model_number: bucket.modelNumber,
      product_name: bucket.productName,
      brand: bucket.brand,
      appliance_category: bucket.applianceCategory,
      msrp: bucket.msrp,
      our_price: bucket.ourPrice,
      condition: bucket.condition,
      quantity: bucket.unitIDs.length,
      photo_path: bucket.photoPath,
      lookup_status: "confirmed",
      created_at: now,
    }));

    const { error: itemError } = await admin
      .from("manifest_items")
      .insert(manifestItems);

    if (itemError) {
      throw itemError;
    }

    const linkRows = Array.from(grouped.values()).flatMap((bucket) =>
      bucket.unitIDs.map((unitID) => ({
        manifest_id: createdManifestID,
        manifest_item_id: bucket.manifestItemID,
        inventory_unit_id: unitID,
        restore_status: (units.find((unit) => unit.id === unitID)?.status ?? "in_stock"),
        release_on_delete: true,
      })));

    const { error: linkError } = await admin
      .from("manifest_inventory_links")
      .insert(linkRows);

    if (linkError) {
      throw linkError;
    }

    const { error: reserveError } = await admin
      .from("inventory_units")
      .update({
        status: "reserved",
        reserved_at: now,
        sold_at: null,
        sold_price: null,
      })
      .in("id", inventoryUnitIDs);

    if (reserveError) {
      throw reserveError;
    }

    return json({
      manifestID: createdManifestID,
      manifestItemCount: manifestItems.length,
      reservedUnitCount: inventoryUnitIDs.length,
    });
  } catch (error) {
    if (createdManifestID) {
      try {
        await admin.from("manifests").delete().eq("id", createdManifestID);
      } catch {}
    }

    const message = error instanceof Error ? error.message : String(error);
    const status = message === "Unauthorized" ? 401 : 400;
    return json({ error: message || "Unable to create quick load." }, status);
  }
});
