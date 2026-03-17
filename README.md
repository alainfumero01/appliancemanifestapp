# LoadScan

Native iPhone app for scanning appliance stickers, building resale manifests, caching model data in Supabase, and exporting loads as spreadsheets.

## What's included
- SwiftUI iOS app in `ApplianceManifest`
- Xcode project in `ApplianceManifest.xcodeproj`
- Supabase SQL migration in `supabase/migrations`
- Supabase Edge Functions in `supabase/functions`
- Launch docs and App Store/legal copy in `docs/launch` and `public`
- Basic XCTest coverage for normalization and CSV export

## Required configuration
Open [Info.plist](/Users/alainfumero/Documents/IOSapp/ApplianceManifest/Info.plist) and set:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_FUNCTIONS_URL` if your functions URL differs from `SUPABASE_URL/functions/v1`

## Backend setup
1. Apply the migrations in `supabase/migrations`, including:
   - [20260313120000_initial_schema.sql](/Users/alainfumero/Documents/IOSapp/supabase/migrations/20260313120000_initial_schema.sql)
   - [20260315000000_add_orgs_and_sessions.sql](/Users/alainfumero/Documents/IOSapp/supabase/migrations/20260315000000_add_orgs_and_sessions.sql)
   - [20260315010000_add_subscription_fields.sql](/Users/alainfumero/Documents/IOSapp/supabase/migrations/20260315010000_add_subscription_fields.sql)
2. Deploy the Edge Functions in:
   - [sign-up-with-invite](/Users/alainfumero/Documents/IOSapp/supabase/functions/sign-up-with-invite/index.ts)
   - [sign-in](/Users/alainfumero/Documents/IOSapp/supabase/functions/sign-in/index.ts)
   - [current-entitlements](/Users/alainfumero/Documents/IOSapp/supabase/functions/current-entitlements/index.ts)
   - [record-manifest-save](/Users/alainfumero/Documents/IOSapp/supabase/functions/record-manifest-save/index.ts)
   - [sync-app-store-subscription](/Users/alainfumero/Documents/IOSapp/supabase/functions/sync-app-store-subscription/index.ts)
   - [enterprise-invite-link](/Users/alainfumero/Documents/IOSapp/supabase/functions/enterprise-invite-link/index.ts)
   - [list-org-members](/Users/alainfumero/Documents/IOSapp/supabase/functions/list-org-members/index.ts)
   - [remove-org-member](/Users/alainfumero/Documents/IOSapp/supabase/functions/remove-org-member/index.ts)
   - [lookup-product](/Users/alainfumero/Documents/IOSapp/supabase/functions/lookup-product/index.ts)
   - [export-manifest](/Users/alainfumero/Documents/IOSapp/supabase/functions/export-manifest/index.ts)
   - [confirm-product](/Users/alainfumero/Documents/IOSapp/supabase/functions/confirm-product/index.ts)
   - [extract-model](/Users/alainfumero/Documents/IOSapp/supabase/functions/extract-model/index.ts)
   - [ingest-sticker](/Users/alainfumero/Documents/IOSapp/supabase/functions/ingest-sticker/index.ts)
3. Set these function secrets in Supabase:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `OPENAI_API_KEY`

## Paid launch setup
- Free tier: 3 saved manifests per organization
- Paid plans:
  - `com.alainfumero.loadscan.individual.monthly`
  - `com.alainfumero.loadscan.enterprise5.monthly`
  - `com.alainfumero.loadscan.enterprise10.monthly`
  - `com.alainfumero.loadscan.enterprise15.monthly`
- App Store metadata and launch copy live in:
  - [app-store-copy.md](/Users/alainfumero/Documents/IOSapp/docs/launch/app-store-copy.md)
  - [app-privacy-questionnaire.md](/Users/alainfumero/Documents/IOSapp/docs/launch/app-privacy-questionnaire.md)
  - [deployment-checklist.md](/Users/alainfumero/Documents/IOSapp/docs/launch/deployment-checklist.md)
- Public compliance pages live in:
  - [privacy-policy.html](/Users/alainfumero/Documents/IOSapp/public/privacy-policy.html)
  - [terms.html](/Users/alainfumero/Documents/IOSapp/public/terms.html)
  - [support.html](/Users/alainfumero/Documents/IOSapp/public/support.html)

## Important launch note
The app now includes a dedicated `app-store-server-notifications` edge function, tags purchases with an `appAccountToken`, and uses Apple's official App Store Server library with Apple PKI root certificates to verify signed transactions and notifications. For live App Store production verification, set the `APPLE_APP_ID` secret in Supabase to your numeric App Apple ID from App Store Connect.

## Local build
The app target builds with:

```bash
xcodebuild -project ApplianceManifest.xcodeproj -scheme ApplianceManifest -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /tmp/ApplianceManifestDerivedData CODE_SIGNING_ALLOWED=NO build
```
