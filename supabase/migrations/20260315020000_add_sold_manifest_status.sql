-- Allow 'sold' as a valid manifest status.
-- The existing check constraint only permitted 'draft' and 'completed'.

alter table manifests
  drop constraint if exists manifests_status_check;

alter table manifests
  add constraint manifests_status_check
  check (status in ('draft', 'completed', 'sold'));
