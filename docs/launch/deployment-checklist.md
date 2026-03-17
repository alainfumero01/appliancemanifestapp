# LoadScan Deployment Checklist

## App Store Connect
- Create the `LoadScan` app record
- Set subtitle, promotional text, description, keywords, and release notes from `docs/launch/app-store-copy.md`
- Create one auto-renewable subscription group
- Add these subscription products:
  - `com.alainfumero.loadscan.individual.monthly`
  - `com.alainfumero.loadscan.enterprise5.monthly`
  - `com.alainfumero.loadscan.enterprise10.monthly`
  - `com.alainfumero.loadscan.enterprise15.monthly`
- Add subscription screenshots and pricing
- Complete the App Privacy questionnaire using `docs/launch/app-privacy-questionnaire.md`

## Public URLs
- Host `public/privacy-policy.html`
- Host `public/terms.html`
- Host `public/support.html`
- Add the live privacy policy URL and support URL to App Store Connect

## Required Final Replacements
- Replace `[replace-with-support-email]` in public pages
- Replace `[replace-with-mailing-address-or-po-box]` in legal pages
- Verify operator name remains `Alain Fumero`

## Supabase
- Run all migrations in `supabase/migrations`
- Deploy Edge Functions:
  - `sign-in`
  - `sign-up-with-invite`
  - `extract-model`
  - `lookup-product`
  - `confirm-product`
  - `current-entitlements`
  - `enterprise-invite-link`
  - `list-org-members`
  - `remove-org-member`
  - `sync-app-store-subscription`
  - `record-manifest-save`
- Set required secrets:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `OPENAI_API_KEY`

## iOS App
- Verify `CFBundleDisplayName` is `LoadScan`
- Configure bundle identifier and signing
- Confirm StoreKit products resolve on-device
- Test:
  - first 3 free manifests
  - upgrade flow
  - restore purchases
  - enterprise invite flow
  - team member removal

## Release Validation
- Privacy policy URL opens
- Support URL opens
- Pricing in the app matches App Store pricing
- Paywall copy matches subscription disclosures
- Export, scan, and manifest save flows work on a real device
