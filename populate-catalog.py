#!/usr/bin/env python3
"""
ApplianceManifest — Catalog Seeder
Fetches appliance products from Best Buy API and upserts into Supabase product_catalog.
"""

import json
import os
import re
import time
import urllib.request
import urllib.parse
import urllib.error

BESTBUY_API_KEY = os.environ.get("BESTBUY_API_KEY")
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")

# Search by name keyword — proven to work with this API key
APPLIANCE_SEARCHES = [
    ("refrigerator*",  "Refrigerators"),
    ("washer*",        "Washers"),
    ("dryer*",         "Dryers"),
    ("dishwasher*",    "Dishwashers"),
    ("microwave*",     "Microwaves"),
    ("range*",         "Ranges"),
    ("oven*",          "Ovens"),
    ("freezer*",       "Freezers"),
    ("cooktop*",       "Cooktops"),
]

PAGE_SIZE   = 100
BATCH_SIZE  = 50
PAGE_DELAY  = 1.5
RETRY_WAIT  = 65
MAX_RETRIES = 3

def require_env():
    missing = [
        name for name, value in [
            ("BESTBUY_API_KEY", BESTBUY_API_KEY),
            ("SUPABASE_URL", SUPABASE_URL),
            ("SUPABASE_SERVICE_KEY", SUPABASE_SERVICE_KEY),
        ]
        if not value
    ]
    if missing:
        joined = ", ".join(missing)
        raise SystemExit(
            f"Missing required environment variables: {joined}\n"
            "Usage:\n"
            "  BESTBUY_API_KEY=... SUPABASE_URL=https://xxxx.supabase.co "
            "SUPABASE_SERVICE_KEY=... python3 populate-catalog.py"
        )

def normalize_model(raw):
    return re.sub(r'[^A-Z0-9]', '', raw.upper())

def fetch_page(name_keyword, page, attempt=1):
    encoded = urllib.parse.quote(name_keyword)
    url = (
        f'https://api.bestbuy.com/v1/products'
        f'(modelNumber=*&regularPrice>0&name={encoded})'
        f'?format=json'
        f'&show=modelNumber,name,regularPrice'
        f'&pageSize={PAGE_SIZE}'
        f'&page={page}'
        f'&apiKey={BESTBUY_API_KEY}'
    )
    req = urllib.request.Request(url, headers={'User-Agent': 'ApplianceManifest/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code in (403, 429) and attempt <= MAX_RETRIES:
            print(f'   Rate limited (attempt {attempt}), waiting {RETRY_WAIT}s...', flush=True)
            time.sleep(RETRY_WAIT)
            return fetch_page(name_keyword, page, attempt + 1)
        raise

def upsert_to_supabase(records):
    data = json.dumps(records).encode('utf-8')
    req  = urllib.request.Request(
        f'{SUPABASE_URL}/rest/v1/product_catalog',
        data=data, method='POST',
        headers={
            'Content-Type':  'application/json',
            'apikey':        SUPABASE_SERVICE_KEY,
            'Authorization': f'Bearer {SUPABASE_SERVICE_KEY}',
            'Prefer':        'resolution=merge-duplicates',
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=30):
            pass
    except urllib.error.HTTPError as e:
        raise Exception(f'Supabase {e.code}: {e.read().decode()}')

def process(keyword, label):
    print(f'\n── {label}')
    try:
        first = fetch_page(keyword, 1)
    except Exception as e:
        print(f'   ERROR: {e}')
        return 0, 0

    total       = first.get('total', 0)
    total_pages = first.get('totalPages', 1)

    if total == 0:
        print('   No products found.')
        return 0, 0

    print(f'   {total} products across {total_pages} pages')

    inserted = 0
    skipped  = 0
    batch    = []

    seen_in_run = set()

    def flush():
        nonlocal inserted, batch
        if not batch:
            return
        # Deduplicate within the batch — keep last occurrence (most recent data)
        deduped = {r['normalized_model_number']: r for r in batch}
        # Also skip models already inserted earlier in this run
        unique = [r for k, r in deduped.items() if k not in seen_in_run]
        seen_in_run.update(deduped.keys())
        batch = []
        if unique:
            upsert_to_supabase(unique)
            inserted += len(unique)

    def consume(products):
        nonlocal skipped
        for p in products:
            model = (p.get('modelNumber') or '').strip()
            name  = (p.get('name') or '').strip()
            price = p.get('regularPrice')
            if not model or not name or not price:
                skipped += 1
                continue
            normalized = normalize_model(model)
            if len(normalized) < 3:
                skipped += 1
                continue
            batch.append({
                'normalized_model_number': normalized,
                'product_name':            name,
                'msrp':                    price,
                'source':                  'bestbuy-catalog',
                'confidence':              1.0,
            })
            if len(batch) >= BATCH_SIZE:
                flush()

    consume(first.get('products', []))

    for page in range(2, total_pages + 1):
        time.sleep(PAGE_DELAY)
        try:
            data = fetch_page(keyword, page)
            consume(data.get('products', []))
        except Exception as e:
            print(f'   WARNING page {page}: {e}')
            continue
        if page % 5 == 0 or page == total_pages:
            print(f'   Page {page}/{total_pages} — {inserted + len(batch)} processed', flush=True)

    try:
        flush()
    except Exception as e:
        print(f'   WARNING final flush: {e}')
    print(f'   ✓ {inserted} inserted, {skipped} skipped')
    return inserted, skipped

def main():
    require_env()
    print('ApplianceManifest — Catalog Seeder')
    print('====================================')

    total_in = 0
    total_sk = 0

    for keyword, label in APPLIANCE_SEARCHES:
        ins, skp = process(keyword, label)
        total_in += ins
        total_sk += skp
        time.sleep(PAGE_DELAY)

    print('\n====================================')
    print(f'Done!  Inserted/updated: {total_in}  |  Skipped: {total_sk}')

if __name__ == '__main__':
    main()
