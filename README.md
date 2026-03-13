# Appliance Manifest

Native iPhone app scaffold for capturing appliance sticker photos, extracting model numbers, caching product data in Supabase, and exporting manifests as spreadsheets.

## What's included
- SwiftUI iOS app in `ApplianceManifest`
- Xcode project in `ApplianceManifest.xcodeproj`
- Supabase SQL migration in `supabase/migrations`
- Supabase Edge Functions in `supabase/functions`
- Basic XCTest coverage for normalization and CSV export

## Required configuration
Open [Info.plist](/Users/alainfumero/Documents/IOSapp/ApplianceManifest/Info.plist) and set:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_FUNCTIONS_URL` if your functions URL differs from `SUPABASE_URL/functions/v1`

## Backend setup
1. Apply the migration in [20260313120000_initial_schema.sql](/Users/alainfumero/Documents/IOSapp/supabase/migrations/20260313120000_initial_schema.sql).
2. Deploy the Edge Functions in:
   - [sign-up-with-invite](/Users/alainfumero/Documents/IOSapp/supabase/functions/sign-up-with-invite/index.ts)
   - [lookup-product](/Users/alainfumero/Documents/IOSapp/supabase/functions/lookup-product/index.ts)
   - [export-manifest](/Users/alainfumero/Documents/IOSapp/supabase/functions/export-manifest/index.ts)
3. Set these function secrets in Supabase:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `OPENAI_API_KEY`

## Local build
The app target builds with:

```bash
xcodebuild -project ApplianceManifest.xcodeproj -scheme ApplianceManifest -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /tmp/ApplianceManifestDerivedData CODE_SIGNING_ALLOWED=NO build
```
