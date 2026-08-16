// POST /generate — lance la génération d'un morceau.
//
// Ordre volontaire : débit puis dispatch. `create_paid_job` crée le job et
// écrit le débit dans la même transaction, donc un solde insuffisant annule le
// job avec lui et aucun appel fournisseur n'est jamais émis sans paiement.

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

interface GenerateBody {
  projectId: string;
  /** Remplace le prompt de style enregistré sur le projet, pour ce rendu. */
  stylePrompt?: string;
  durationMs?: number;
}

interface LyricsLine {
  text: string;
}
interface LyricsSection {
  type: string;
  index?: number;
  lines: LyricsLine[];
}

/** Aplatit le document structuré en texte à marqueurs pour le moteur audio. */
function flattenLyrics(content: LyricsSection[]): string {
  return content
    .map((section) => {
      const heading = section.index
        ? `[${section.type} ${section.index}]`
        : `[${section.type}]`;
      return [heading, ...section.lines.map((l) => l.text)].join("\n");
    })
    .join("\n\n");
}

Deno.serve(handler(async (req) => {
  if (req.method !== "POST") throw badRequest("Méthode non autorisée");

  const asUser = userClient(req);
  await requireUserId(asUser);

  const body = await readJson<GenerateBody>(req);
  if (!body.projectId) throw badRequest("projectId requis");

  // Lecture sous RLS : un projet qui n'appartient pas à l'appelant est
  // simplement introuvable, sans contrôle applicatif supplémentaire.
  const { data: project, error: projectError } = await asUser
    .from("projects")
    .select("id, title, genre_prompt, lyrics_documents(content)")
    .eq("id", body.projectId)
    .single();

  if (projectError || !project) throw badRequest("Projet introuvable");

  const lyricsDocument = Array.isArray(project.lyrics_documents)
    ? project.lyrics_documents[0]
    : project.lyrics_documents;
  const sections = (lyricsDocument?.content ?? []) as LyricsSection[];
  if (sections.length === 0) {
    throw badRequest("Écris ou génère des paroles avant de lancer la génération");
  }

  const stylePrompt = body.stylePrompt ?? project.genre_prompt;
  if (!stylePrompt) throw badRequest("Aucun style défini pour ce projet");

  // Seed tirée côté serveur et conservée sur la version : c'est elle qui rendra
  // la régénération d'une section raccordable au reste du morceau.
  const seed = crypto.getRandomValues(new Uint32Array(1))[0];

  // --- Débit + création du job, atomiques ---------------------------------
  const { data: jobId, error: jobError } = await asUser.rpc("create_paid_job", {
    p_project_id: body.projectId,
    p_kind: "generate",
    p_credits_cost: CREDIT_COST.generate,
    p_payload: { style_prompt: stylePrompt, seed, duration_ms: body.durationMs },
  });

  if (jobError) {
    if (jobError.message?.includes("Crédits insuffisants")) throw paymentRequired();
    throw badRequest(jobError.message ?? "Création du job impossible");
  }

  // --- À partir d'ici, les crédits sont débités : tout échec doit rembourser ---
  const asService = serviceClient();

  try {
    const { data: version, error: versionError } = await asService
      .from("versions")
      .insert({
        project_id: body.projectId,
        status: "generating",
        seed,
        prompt_snapshot: { style_prompt: stylePrompt },
        lyrics_snapshot: sections,
      })
      .select("id")
      .single();

    if (versionError || !version) {
      throw new Error(versionError?.message ?? "Création de la version impossible");
    }

    // L'ID du job voyage dans l'URL du webhook : la corrélation ne dépend donc
    // pas d'une écriture en base qui pourrait ne pas être encore committée
    // quand un fournisseur rapide rappelle. La signature reste la garantie
    // d'authenticité — l'URL n'est pas un secret.
    const engine = getEngine();
    const { providerJobId } = await engine.generate({
      jobId,
      stylePrompt,
      lyrics: flattenLyrics(sections),
      durationMs: body.durationMs,
      seed,
      webhookUrl: `${requireEnv("SUPABASE_URL")}/functions/v1/webhooks-provider?job_id=${jobId}`,
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

    return json({ jobId, versionId: version.id }, 202);
  } catch (err) {
    // Panne fournisseur ou erreur interne : l'utilisateur ne paie pas.
    await asService.rpc("fail_job_and_refund", {
      p_job_id: jobId,
      p_error: err instanceof Error ? err.message : String(err),
    });
    throw err;
  }
}));
