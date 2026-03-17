drop policy if exists "sticker_photos_insert_own" on storage.objects;
drop policy if exists "sticker_photos_select_own" on storage.objects;
drop policy if exists "sticker_photos_update_own" on storage.objects;
drop policy if exists "sticker_photos_delete_own" on storage.objects;

create policy "sticker_photos_insert_authenticated"
on storage.objects for insert
to authenticated
with check (bucket_id = 'sticker-photos');

create policy "sticker_photos_select_authenticated"
on storage.objects for select
to authenticated
using (bucket_id = 'sticker-photos');

create policy "sticker_photos_update_authenticated"
on storage.objects for update
to authenticated
using (bucket_id = 'sticker-photos')
with check (bucket_id = 'sticker-photos');

create policy "sticker_photos_delete_authenticated"
on storage.objects for delete
to authenticated
using (bucket_id = 'sticker-photos');
