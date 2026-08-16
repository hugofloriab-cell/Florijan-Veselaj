// POST /webhooks-provider?job_id=… — callback du fournisseur GPU.
//
// Seul endroit du système autorisé à déclarer un job terminé. Trois garanties :
// la signature est vérifiée avant toute lecture du corps, le traitement est
// idempotent (un rejeu ne rembourse ni ne duplique rien), et l'audio est
// recopié dans notre Storage — les URLs fournisseur expirent en quelques heures.

import { badRequest, handler, json, requireEnv } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { getEngine, type ProviderEvent } from "../_shared/engine/index.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

type StemKind = "vocals" | "drums" | "bass" | "other";
const STEM_KINDS: StemKind[] = ["vocals", "drums", "bass", "other"];

interface JobRow {
  id: string;
  user_id: string;
  project_id: string | null;
  version_id: string | null;
  kind: string;
  status: string;
}

Deno.serve(handler(async (req) => {
  if (req.method !== "POST") throw badRequest("Méthode non autorisée");

  const jobId = new URL(req.url).searchParams.get("job_id");
  if (!jobId) throw badRequest("job_id manquant");

  // Le corps brut doit être lu tel quel : re-sérialiser du JSON changerait les
  // octets et invaliderait le HMAC.
  const rawBody = await req.text();
  const engine = getEngine();
  const event = await engine.verifyAndParseWebhook(req, rawBody);

  const db = serviceClient();
  const { data: job } = await db
    .from("jobs")
    .select("id, user_id, project_id, version_id, kind, status")
    .eq("id", jobId)
    .single<JobRow>();

  if (!job) throw badRequest("Job introuvable");

  // Idempotence : un fournisseur qui rejoue son callback ne doit rien rejouer
  // de notre côté. On acquitte en 200 pour qu'il cesse de réessayer.
  if (job.status === "succeeded" || job.status === "failed") {
    return json({ ok: true, deduplicated: true });
  }

  switch (event.status) {
    case "running":
      await db.from("jobs").update({ status: "running" }).eq("id", job.id);
      return json({ ok: true });

    case "failed":
      await db.rpc("fail_job_and_refund", { p_job_id: job.id, p_error: event.error });
      if (job.version_id) {
        await db.from("versions").update({ status: "failed" }).eq("id", job.version_id);
      }
      return json({ ok: true });

    case "succeeded":
      await onSucceeded(db, job, event);
      return json({ ok: true });
  }
}));

async function onSucceeded(
  db: SupabaseClient,
  job: JobRow,
  event: Extract<ProviderEvent, { status: "succeeded" }>,
): Promise<void> {
  if (event.outputUrls.length === 0) {
    await db.rpc("fail_job_and_refund", {
      p_job_id: job.id,
      p_error: "Le fournisseur a réussi sans produire de fichier",
    });
    return;
  }

  if (job.kind === "generate" || job.kind === "restyle") {
    await ingestMaster(db, job, event.outputUrls[0]);
  } else if (job.kind === "separate_stems") {
    await ingestStems(db, job, event.outputUrls);
  }

  await db
    .from("jobs")
    .update({ status: "succeeded", completed_at: new Date().toISOString() })
    .eq("id", job.id);
}

/** Recopie le master, marque la version prête, puis enchaîne la séparation. */
async function ingestMaster(
  db: SupabaseClient,
  job: JobRow,
  sourceUrl: string,
): Promise<void> {
  if (!job.version_id || !job.project_id) return;

  const path = `${job.user_id}/${job.project_id}/${job.version_id}/master.wav`;
  await copyToStorage(db, sourceUrl, "masters", path);

  await db
    .from("versions")
    .update({ status: "ready", master_audio_path: path })
    .eq("id", job.version_id);

  await db
    .from("projects")
    .update({ current_version_id: job.version_id })
    .eq("id", job.project_id);

  await dispatchStemSeparation(db, job, path);
}

async function ingestStems(
  db: SupabaseClient,
  job: JobRow,
  urls: string[],
): Promise<void> {
  if (!job.version_id || !job.project_id) return;

  const rows = [];
  for (const url of urls) {
    const kind = inferStemKind(url);
    if (!kind) continue;
    const path = `${job.user_id}/${job.project_id}/${job.version_id}/${kind}.wav`;
    await copyToStorage(db, url, "stems", path);
    rows.push({ version_id: job.version_id, kind, storage_path: path });
  }

  if (rows.length > 0) {
    // Une re-séparation de la même version écrase les pistes existantes plutôt
    // que de violer la contrainte unique (version_id, kind).
    await db.from("stems").upsert(rows, { onConflict: "version_id,kind" });
  }
}

/**
 * Enchaîne la séparation en pistes. Job à coût nul : elle fait partie de ce que
 * la génération a déjà payé.
 */
async function dispatchStemSeparation(
  db: SupabaseClient,
  job: JobRow,
  masterPath: string,
): Promise<void> {
  const { data: signed } = await db.storage
    .from("masters")
    .createSignedUrl(masterPath, 3600);
  if (!signed?.signedUrl) return;

  const { data: stemJob } = await db
    .from("jobs")
    .insert({
      user_id: job.user_id,
      project_id: job.project_id,
      version_id: job.version_id,
      kind: "separate_stems",
      status: "running",
      credits_cost: 0,
    })
    .select("id")
    .single<{ id: string }>();

  if (!stemJob) return;

  const engine = getEngine();
  try {
    const { providerJobId } = await engine.separateStems({
      jobId: stemJob.id,
      audioUrl: signed.signedUrl,
      webhookUrl: `${requireEnv("SUPABASE_URL")}/functions/v1/webhooks-provider?job_id=${stemJob.id}`,
    });
    await db
      .from("jobs")
      .update({ provider: engine.name, provider_job_id: providerJobId })
      .eq("id", stemJob.id);
  } catch (err) {
    // La séparation échoue mais le morceau existe : on n'invalide pas la
    // génération, l'utilisateur pourra relancer la séparation depuis l'éditeur.
    await db
      .from("jobs")
      .update({
        status: "failed",
        error: err instanceof Error ? err.message : String(err),
        completed_at: new Date().toISOString(),
      })
      .eq("id", stemJob.id);
  }
}

async function copyToStorage(
  db: SupabaseClient,
  sourceUrl: string,
  bucket: string,
  path: string,
): Promise<void> {
  const response = await fetch(sourceUrl);
  if (!response.ok) {
    throw new Error(`Téléchargement du rendu impossible (${response.status})`);
  }
  const { error } = await db.storage
    .from(bucket)
    .upload(path, await response.arrayBuffer(), {
      contentType: response.headers.get("content-type") ?? "audio/wav",
      upsert: true,
    });
  if (error) throw new Error(`Écriture Storage impossible : ${error.message}`);
}

function inferStemKind(url: string): StemKind | null {
  const name = new URL(url).pathname.toLowerCase();
  return STEM_KINDS.find((kind) => name.includes(kind)) ?? null;
}
