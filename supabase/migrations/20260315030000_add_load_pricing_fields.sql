-- Store the load cost and target margin % entered during load pricing mode.
-- Both are nullable — only set when the operator used Load Pricing on create.

alter table manifests
  add column if not exists load_cost       numeric(12,2) default null,
  add column if not exists target_margin_pct numeric(5,2) default null;
