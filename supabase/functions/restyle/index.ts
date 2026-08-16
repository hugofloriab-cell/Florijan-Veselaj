// POST /restyle — change le genre d'un morceau sans réécrire les paroles.
//
// Le cœur du produit : l'utilisateur ne repart pas de zéro. On repart des
// paroles et de la seed de la version existante, on ne remplace que le prompt
// de style, et le résultat devient une version *enfant* — l'original reste
// écoutable et l'arbre d'édition garde la trace du chemin parcouru.

import {
  badRequest,
  handler,
  json,
  paymentRequired,
  readJson,
  requireEnv,
} from "../_shared/http.ts";
import { requireUserId, serviceClient, userClient } from "../_shared/supabase.ts";
import { CREDIT_COST, getEngine } from "../_shared/engine/index.ts";
import { flattenLyrics, type LyricsSection } from "../_shared/lyrics.ts";

interface RestyleBody {
  /** Version de départ. Le rendu produit deviendra son enfant. */
  versionId: string;
  stylePrompt: string;
  /**
   * Conserver la seed de la version parente (défaut). L'arrangement et la
   * métrique restent alors comparables, et seule la couleur change — c'est ce
   * qui rend les deux versions écoutables l'une après l'autre. Passer `false`
   * pour une relecture complètement différente.
   */
  keepSeed?: boolean;
}

interface ParentVersion {
  id: string;
  project_id: string;
  seed: number | null;
  lyrics_snapshot: LyricsSection[] | null;
}

Deno.serve(handler(async (req) => {
  if (req.method !== "POST") throw badRequest("Méthode non autorisée");

  const asUser = userClient(req);
  await requireUserId(asUser);

  const body = await readJson<RestyleBody>(req);
  if (!body.versionId) throw badRequest("versionId requis");
  if (!body.stylePrompt?.trim()) throw badRequest("stylePrompt requis");

  // Lecture sous RLS : une version d'un autre utilisateur est introuvable.
  const { data: parent } = await asUser
    .from("versions")
    .select("id, project_id, seed, lyrics_snapshot")
    .eq("id", body.versionId)
    .single<ParentVersion>();

  if (!parent) throw badRequest("Version introuvable");

  const sections = parent.lyrics_snapshot ?? [];
  if (sections.length === 0) {
    throw badRequest("La version de départ ne porte aucune parole");
  }

  const seed = body.keepSeed === false
    ? crypto.getRandomValues(new Uint32Array(1))[0]
    : parent.seed ?? crypto.getRandomValues(new Uint32Array(1))[0];

  // Débit et création du job dans la même transaction. `p_version_id` reste nul
  // ici : il désignera la version *enfant*, qui n'existe pas encore.
  const { data: jobId, error: jobError } = await asUser.rpc("create_paid_job", {
    p_project_id: parent.project_id,
    p_kind: "restyle",
    p_credits_cost: CREDIT_COST.restyle,
    p_payload: {
      style_prompt: body.stylePrompt,
      parent_version_id: parent.id,
      seed,
    },
  });

  if (jobError) {
    if (jobError.message?.includes("Crédits insuffisants")) throw paymentRequired();
    throw badRequest(jobError.message ?? "Création du job impossible");
  }

  const asService = serviceClient();

  try {
    const { data: version, error: versionError } = await asService
      .from("versions")
      .insert({
        project_id: parent.project_id,
        parent_version_id: parent.id,
        label: body.stylePrompt.slice(0, 80),
        status: "generating",
        seed,
        prompt_snapshot: { style_prompt: body.stylePrompt },
        lyrics_snapshot: sections,
      })
      .select("id")
      .single<{ id: string }>();

    if (versionError || !version) {
      throw new Error(versionError?.message ?? "Création de la version impossible");
    }

    const engine = getEngine();
    const { providerJobId } = await engine.generate({
      jobId,
      stylePrompt: body.stylePrompt,
      lyrics: flattenLyrics(sections),
      seed,
      webhookUrl:
        `${requireEnv("SUPABASE_URL")}/functions/v1/webhooks-provider?job_id=${jobId}`,
    });

    await asService
      .from("jobs")
      .update({
        status: "running",
        version_id: version.id,
        provider: engine.name,
        provider_job_id: providerJobId,
      })
      .eq("id", jobId);

    return json({ jobId, versionId: version.id, parentVersionId: parent.id }, 202);
  } catch (err) {
    await asService.rpc("fail_job_and_refund", {
      p_job_id: jobId,
      p_error: err instanceof Error ? err.message : String(err),
    });
    throw err;
  }
}));
