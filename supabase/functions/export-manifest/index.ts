import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const { manifestId } = await request.json();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    {
      global: { headers: { Authorization: authorization } },
      auth: { autoRefreshToken: false, persistSession: false }
    }
  );

  const { data: manifest } = await supabase
    .from("manifests")
    .select("id, title, load_reference, created_at, manifest_items(model_number, product_name, msrp, quantity, photo_path)")
    .eq("id", manifestId)
    .single();

  if (!manifest) {
    return new Response(JSON.stringify({ error: "Manifest not found." }), {
      status: 404,
      headers: { "Content-Type": "application/json" }
    });
  }

  const header = [
    "Manifest Name",
    "Load Reference",
    "Created Date",
    "Model Number",
    "Product Name",
    "MSRP",
    "Quantity",
    "Line Total",
    "Photo Link"
  ];

  const rows = (manifest.manifest_items ?? []).map((item: any) => {
    const lineTotal = Number(item.msrp) * Number(item.quantity);
    return [
      manifest.title,
      manifest.load_reference,
      manifest.created_at,
      item.model_number,
      item.product_name,
      item.msrp,
      item.quantity,
      lineTotal,
      item.photo_path ?? ""
    ];
  });

  const csv = [header, ...rows]
    .map((row) => row.map((value) => `"${String(value).replaceAll(`"`, `""`)}"`).join(","))
    .join("\n");

  return new Response(csv, {
    status: 200,
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${manifest.title}.csv"`
    }
  });
});
