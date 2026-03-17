drop policy if exists "catalog_authenticated_write" on public.product_catalog;

create policy "catalog_authenticated_write"
on public.product_catalog for insert
to authenticated
with check (true);

drop policy if exists "catalog_authenticated_update" on public.product_catalog;

create policy "catalog_authenticated_update"
on public.product_catalog for update
to authenticated
using (true)
with check (true);

drop policy if exists "sticker_photos_insert_own" on storage.objects;

create policy "sticker_photos_insert_own"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'sticker-photos'
  and owner = auth.uid()
);

drop policy if exists "sticker_photos_select_own" on storage.objects;

create policy "sticker_photos_select_own"
on storage.objects for select
to authenticated
using (
  bucket_id = 'sticker-photos'
  and owner = auth.uid()
);

drop policy if exists "sticker_photos_update_own" on storage.objects;

create policy "sticker_photos_update_own"
on storage.objects for update
to authenticated
using (
  bucket_id = 'sticker-photos'
  and owner = auth.uid()
)
with check (
  bucket_id = 'sticker-photos'
  and owner = auth.uid()
);

drop policy if exists "sticker_photos_delete_own" on storage.objects;

create policy "sticker_photos_delete_own"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'sticker-photos'
  and owner = auth.uid()
);
