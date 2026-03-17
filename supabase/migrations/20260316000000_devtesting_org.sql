-- Create the DEVTESTING beta org (owned by the first user in auth.users,
-- update owner_id after if you want a specific account to own it).

DO $$
DECLARE
  v_owner_id  uuid;
  v_org_id    uuid;
BEGIN
  -- Use the oldest user as the org owner (typically the developer account)
  SELECT id INTO v_owner_id FROM auth.users ORDER BY created_at ASC LIMIT 1;

  -- Create the shared beta testing org
  INSERT INTO organizations (
    name,
    owner_id,
    subscription_type,
    subscription_status,
    billing_platform,
    app_store_product_id,
    subscription_expires_at,   -- NULL = never expires (lifetime)
    seat_limit,
    extra_seats,
    trial_manifest_limit,
    trial_manifests_used
  ) VALUES (
    'Beta Testers',
    v_owner_id,
    'enterprise',
    'active',
    'app_store',
    'com.alainfumero.loadscan.individual.monthly',
    NULL,     -- lifetime — no expiry
    500,      -- up to 500 beta seats
    499,
    9999,
    0
  )
  RETURNING id INTO v_org_id;

  -- Add the owner as a member
  INSERT INTO org_members (org_id, user_id, role)
  VALUES (v_org_id, v_owner_id, 'owner');

  -- Update owner's profile to point to the new org
  UPDATE profiles SET org_id = v_org_id WHERE id = v_owner_id;

  -- Create the unlimited DEVTESTING invite code
  INSERT INTO invite_codes (
    code,
    is_active,
    usage_limit,   -- NULL = unlimited uses
    usage_count,
    created_by,
    org_id
  ) VALUES (
    'DEVTESTING',
    true,
    NULL,   -- unlimited
    0,
    v_owner_id,
    v_org_id
  );

  RAISE NOTICE 'Beta org created: %, invite code: DEVTESTING', v_org_id;
END $$;
