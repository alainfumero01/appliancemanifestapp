import {
  json,
  requireAuthenticatedOrgContext,
  serviceRoleClient,
} from "../_shared/sellerInventory.ts";

type ManifestRow = {
  id: string;
  org_id: string | null;
  status: string;
};

type ManifestItemRow = {
  id: string;
  our_price: number | null;
};

type ManifestLinkRow = {
  id: string;
  inventory_unit_id: string;
  manifest_item_id: string;
  restore_status: string;
  release_on_delete: boolean;
};

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const admin = serviceRoleClient();

  try {
    const context = await requireAuthenticatedOrgContext(admin, request);
    const body = await request.json().catch(() => null);
    const manifestID = String(body?.manifestID ?? "").trim();

    if (!manifestID) {
      return json({ error: "manifestID is required." }, 400);
    }

    const { data: manifest } = await admin
      .from("manifests")
      .select("id,org_id,status")
      .eq("id", manifestID)
      .eq("org_id", context.orgID)
      .maybeSingle<ManifestRow>();

    if (!manifest) {
      return json({ error: "Manifest not found." }, 404);
    }

    const { data: links, error: linkError } = await admin
      .from("manifest_inventory_links")
      .select("id,inventory_unit_id,manifest_item_id,restore_status,release_on_delete")
      .eq("manifest_id", manifestID)
      .returns<ManifestLinkRow[]>();

    if (linkError) {
      throw linkError;
    }

    const activeLinks = links ?? [];
    if (activeLinks.length == 0) {
      return json({ updatedUnitCount: 0 });
    }

    const { data: manifestItems, error: itemError } = await admin
      .from("manifest_items")
      .select("id,our_price")
      .eq("manifest_id", manifestID)
      .returns<ManifestItemRow[]>();

    if (itemError) {
      throw itemError;
    }

    const priceByItemID = new Map((manifestItems ?? []).map((item) => [item.id, Number(item.our_price ?? 0)]));
    const now = new Date().toISOString();

    if (manifest.status === "sold") {
      for (const link of activeLinks) {
        const { error: unitError } = await admin
          .from("inventory_units")
          .update({
            status: "sold",
            reserved_at: null,
            sold_at: now,
            sold_price: priceByItemID.get(link.manifest_item_id) ?? 0,
          })
          .eq("id", link.inventory_unit_id);

        if (unitError) {
          throw unitError;
        }
      }

      const { error: updateLinksError } = await admin
        .from("manifest_inventory_links")
        .update({ release_on_delete: false })
        .eq("manifest_id", manifestID);

      if (updateLinksError) {
        throw updateLinksError;
      }
    } else {
      const { error: updateUnitsError } = await admin
        .from("inventory_units")
        .update({
          status: "reserved",
          reserved_at: now,
          sold_at: null,
          sold_price: null,
        })
        .in("id", activeLinks.map((link) => link.inventory_unit_id));

      if (updateUnitsError) {
        throw updateUnitsError;
      }

      const { error: updateLinksError } = await admin
        .from("manifest_inventory_links")
        .update({ release_on_delete: true })
        .eq("manifest_id", manifestID);

      if (updateLinksError) {
        throw updateLinksError;
      }
    }

    return json({ updatedUnitCount: activeLinks.length });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message === "Unauthorized" ? 401 : 400;
    return json({ error: message || "Unable to sync linked inventory status." }, status);
  }
});
