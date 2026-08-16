// POST /export — délivre des URLs signées vers l'audio d'une version.
//
// Pas de zip ni de mixdown côté serveur, volontairement : l'app rend le
// mixdown sur l'appareil via le rendu manuel d'AVAudioEngine (ADR 000), donc
// assembler ici un fichier que le téléphone sait produire coûterait du CPU, de
// la bande passante et du stockage pour rien. Cette fonction vend l'accès, pas
// le calcul.

import { badRequest, forbidden, handler, json, readJson } from "../_shared/http.ts";
import { requireUserId, userClient } from "../_shared/supabase.ts";

/** Durée de validité des liens : le temps de télécharger, pas de partager. */
const SIGNED_URL_TTL_SECONDS = 15 * 60;

interface ExportBody {
  versionId: string;
  /** `master` : le mixdown généré. `stems` : les pistes séparées. */
  format?: "master" | "stems";
}

Deno.serve(handler(async (req) => {
  if (req.method !== "POST") throw badRequest("Méthode non autorisée");

  const asUser = userClient(req);
  const userId = await requireUserId(asUser);

  const body = await readJson<ExportBody>(req);
  if (!body.versionId) throw badRequest("versionId requis");
  const format = body.format ?? "master";

  // RLS : une version qui n'appartient pas à l'appelant est introuvable.
  const { data: version } = await asUser
    .from("versions")
    .select("id, status, master_audio_path")
    .eq("id", body.versionId)
    .single<{ id: string; status: string; master_audio_path: string | null }>();

  if (!version) throw badRequest("Version introuvable");
  if (version.status !== "ready") {
    throw badRequest("Cette version n'est pas encore prête");
  }

  if (format === "master") {
    if (!version.master_audio_path) throw badRequest("Aucun master sur cette version");
    return json({
      format,
      files: [
        {
          kind: "master",
          url: await signOrFail(asUser, "masters", version.master_audio_path),
        },
      ],
      expiresInSeconds: SIGNED_URL_TTL_SECONDS,
    });
  }

  // --- Pistes séparées : réservées au tier payant -------------------------
  const { data: profile } = await asUser
    .from("profiles")
    .select("tier")
    .eq("id", userId)
    .single<{ tier: string }>();

  if (!profile || profile.tier === "free") {
    throw forbidden("L'export des pistes séparées est réservé aux abonnés");
  }

  const { data: stems } = await asUser
    .from("stems")
    .select("kind, storage_path")
    .eq("version_id", version.id);

  if (!stems || stems.length === 0) {
    throw badRequest("Les pistes de cette version ne sont pas encore séparées");
  }

  const files = [];
  for (const stem of stems) {
    files.push({
      kind: stem.kind,
      url: await signOrFail(asUser, "stems", stem.storage_path),
    });
  }

  return json({ format, files, expiresInSeconds: SIGNED_URL_TTL_SECONDS });
}));

async function signOrFail(
  client: ReturnType<typeof userClient>,
  bucket: string,
  path: string,
): Promise<string> {
  // La signature passe par le client porteur du JWT : les politiques Storage
  // revalident la propriété, en plus du contrôle applicatif ci-dessus.
  const { data, error } = await client.storage
    .from(bucket)
    .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);

  if (error || !data?.signedUrl) {
    throw new Error(`Signature d'URL impossible pour ${bucket}/${path}`);
  }
  return data.signedUrl;
}
