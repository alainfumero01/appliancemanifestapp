drop policy if exists "manifests_delete_own" on public.manifests;

create policy "manifests_delete_own"
on public.manifests for delete
using (auth.uid() = owner_id);
