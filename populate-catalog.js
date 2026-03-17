#!/usr/bin/env node
/**
 * populate-catalog.js
 *
 * Fetches appliance products from the Best Buy API and upserts them into
 * the Supabase product_catalog table.
 *
 * Requirements: Node 18+ (uses built-in fetch)
 *
 * Usage:
 *   BESTBUY_API_KEY=xxx \
 *   SUPABASE_URL=https://xxxx.supabase.co \
 *   SUPABASE_SERVICE_KEY=xxx \
 *   node populate-catalog.js
 *
 * Get your Best Buy API key (free): https://developer.bestbuy.com
 * Get your Supabase service key: Supabase dashboard → Project Settings → API → service_role secret
 */

const BESTBUY_API_KEY  = process.env.BESTBUY_API_KEY;
const SUPABASE_URL     = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

if (!BESTBUY_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error('Missing required environment variables.');
  console.error('  BESTBUY_API_KEY   — from developer.bestbuy.com');
  console.error('  SUPABASE_URL      — e.g. https://xxxx.supabase.co');
  console.error('  SUPABASE_SERVICE_KEY — from Supabase dashboard → Project Settings → API');
  process.exit(1);
}

// Appliance sub-categories to pull from Best Buy.
// Each entry is a Best Buy category ID that maps to a specific appliance type.
const APPLIANCE_CATEGORIES = [
  { id: 'abcat0901011', label: 'Refrigerators'       },
  { id: 'abcat0901021', label: 'Freezers'             },
  { id: 'abcat0904011', label: 'Washing Machines'     },
  { id: 'abcat0904021', label: 'Dryers'               },
  { id: 'abcat0905011', label: 'Ranges & Ovens'       },
  { id: 'abcat0905021', label: 'Microwaves'           },
  { id: 'abcat0912011', label: 'Dishwashers'          },
  { id: 'abcat0903011', label: 'Air Conditioners'     },
  { id: 'abcat0902011', label: 'Vacuums'              },
  { id: 'abcat0912031', label: 'Trash Compactors'     },
  { id: 'abcat0906011', label: 'Garbage Disposals'    },
];

const PAGE_SIZE  = 100;   // Max allowed by Best Buy API
const BATCH_SIZE = 50;    // Records per Supabase upsert call
const DELAY_MS   = 250;   // Pause between Best Buy API pages to stay polite

// Mirrors the iOS app's ModelNumberNormalizer:
// uppercase, strip spaces, dashes, slashes, dots
function normalizeModelNumber(raw) {
  return raw.toUpperCase().replace(/[\s\-\/\\.]/g, '');
}

async function fetchBestBuyPage(categoryId, page) {
  const filter = `(categoryPath.id=${categoryId}&modelNumber=*&regularPrice>0)`;
  const show   = 'modelNumber,name,regularPrice,manufacturer';
  const url    = `https://api.bestbuy.com/v1/products${filter}?format=json&show=${show}&pageSize=${PAGE_SIZE}&page=${page}&apiKey=${BESTBUY_API_KEY}`;

  const res = await fetch(url);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Best Buy API ${res.status}: ${body}`);
  }
  return res.json();
}

async function upsertToSupabase(records) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/product_catalog`, {
    method: 'POST',
    headers: {
      'Content-Type':  'application/json',
      'apikey':        SUPABASE_SERVICE_KEY,
      'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
      'Prefer':        'resolution=merge-duplicates',
    },
    body: JSON.stringify(records),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Supabase upsert ${res.status}: ${body}`);
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function processCategory(category) {
  console.log(`\n── ${category.label} (${category.id})`);

  // Fetch page 1 to learn total count
  const first      = await fetchBestBuyPage(category.id, 1);
  const totalPages = first.totalPages ?? 1;
  const total      = first.total ?? 0;

  if (total === 0) {
    console.log('   No products found, skipping.');
    return { inserted: 0, skipped: 0 };
  }

  console.log(`   ${total} products across ${totalPages} pages`);

  let inserted = 0;
  let skipped  = 0;
  let batch    = [];

  const processPage = async (products) => {
    for (const p of products) {
      if (!p.modelNumber || !p.name || !p.regularPrice) {
        skipped++;
        continue;
      }
      const normalized = normalizeModelNumber(p.modelNumber);
      if (!normalized || normalized.length < 3) {
        skipped++;
        continue;
      }
      batch.push({
        normalized_model_number: normalized,
        product_name:            p.name,
        msrp:                    p.regularPrice,
        source:                  'bestbuy-catalog',
        confidence:              1.0,
      });

      if (batch.length >= BATCH_SIZE) {
        await upsertToSupabase(batch);
        inserted += batch.length;
        batch = [];
      }
    }
  };

  await processPage(first.products ?? []);

  for (let page = 2; page <= totalPages; page++) {
    await sleep(DELAY_MS);
    const data = await fetchBestBuyPage(category.id, page);
    await processPage(data.products ?? []);

    if (page % 5 === 0 || page === totalPages) {
      process.stdout.write(`   Page ${page}/${totalPages} — ${inserted} inserted so far\r`);
    }
  }

  // Flush remaining batch
  if (batch.length > 0) {
    await upsertToSupabase(batch);
    inserted += batch.length;
    batch = [];
  }

  console.log(`   ✓ ${inserted} inserted, ${skipped} skipped`);
  return { inserted, skipped };
}

async function main() {
  console.log('ApplianceManifest — Catalog Seeder');
  console.log('====================================');
  console.log(`Supabase: ${SUPABASE_URL}`);
  console.log(`Categories: ${APPLIANCE_CATEGORIES.length}`);

  let totalInserted = 0;
  let totalSkipped  = 0;

  for (const category of APPLIANCE_CATEGORIES) {
    try {
      const { inserted, skipped } = await processCategory(category);
      totalInserted += inserted;
      totalSkipped  += skipped;
    } catch (err) {
      console.error(`\n   ERROR in ${category.label}: ${err.message}`);
    }
  }

  console.log('\n====================================');
  console.log(`Done! Inserted/updated: ${totalInserted} | Skipped: ${totalSkipped}`);
}

main().catch(err => {
  console.error('\nFatal error:', err.message);
  process.exit(1);
});
