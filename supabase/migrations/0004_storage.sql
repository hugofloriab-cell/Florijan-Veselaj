-- Melodix — buckets de stockage
--
-- Convention de chemin, appliquée par les politiques ci-dessous :
--   {user_id}/{project_id}/{version_id}/{fichier}
-- Le premier segment étant l'UUID du propriétaire, l'isolation se vérifie sans
-- jointure : storage.foldername(name)[1] = auth.uid().
--
-- Tous les buckets sont privés. L'app n'accède aux fichiers que par URL signée à
-- durée courte, générée côté serveur.

insert into storage.buckets (id, name, public)
values
  ('masters', 'masters', false),   -- mixdowns générés
  ('stems',   'stems',   false),   -- pistes séparées (Demucs)
  ('peaks',   'peaks',   false),   -- waveforms pré-calculées
  ('exports', 'exports', false),   -- MP3 / zip WAV, purgeables
  ('uploads', 'uploads', false)    -- prises de voix de l'utilisateur
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Lecture : l'utilisateur ne voit que son propre préfixe
-- ---------------------------------------------------------------------------

create policy storage_read_own on storage.objects
  for select to authenticated
  using (
    bucket_id in ('masters', 'stems', 'peaks', 'exports', 'uploads')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- Écriture : uniquement dans `uploads` (prises de voix)
-- ---------------------------------------------------------------------------
--
-- Les masters, stems et exports sont écrits par le service_role au retour des
-- webhooks. Laisser le client y écrire permettrait de substituer l'audio d'un
-- morceau après coup.

create policy storage_write_own_uploads on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'uploads'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy storage_delete_own_uploads on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'uploads'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
