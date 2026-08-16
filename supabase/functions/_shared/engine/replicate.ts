// Adaptateur Replicate.
//
// ⚠️ Les identifiants de modèle sont volontairement pris dans l'environnement,
// pas codés en dur : le moteur musical n'est pas encore choisi (Lot 1), et le
// critère décisif est la licence commerciale. Ne pas figer ici un modèle en
// CC-BY-NC — ce serait un défaut juridique, pas seulement technique.

import { requireEnv } from "../http.ts";
import { verifyStandardWebhook } from "../webhook-signature.ts";
import type {
  EngineJobHandle,
  GenerateRequest,
  MusicEngine,
  ProviderEvent,
  SeparateStemsRequest,
} from "./types.ts";

const API = "https://api.replicate.com/v1/predictions";

interface ReplicatePrediction {
  id: string;
  status: "starting" | "processing" | "succeeded" | "failed" | "canceled";
  output?: string | string[] | Record<string, string> | null;
  error?: string | null;
}

export class ReplicateEngine implements MusicEngine {
  readonly name = "replicate";

  private async createPrediction(
    version: string,
    input: Record<string, unknown>,
    webhookUrl: string,
  ): Promise<EngineJobHandle> {
    const response = await fetch(API, {
      method: "POST",
      headers: {
        authorization: `Bearer ${requireEnv("REPLICATE_API_TOKEN")}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        version,
        input,
        webhook: webhookUrl,
        // On ne s'abonne qu'aux transitions utiles : chaque événement `logs`
        // serait un appel de fonction facturé pour rien.
        webhook_events_filter: ["start", "completed"],
      }),
    });

    if (!response.ok) {
      throw new Error(
        `Replicate a refusé la prédiction (${response.status}) : ${await response.text()}`,
      );
    }

    const prediction = (await response.json()) as ReplicatePrediction;
    return { providerJobId: prediction.id };
  }

  generate(req: GenerateRequest): Promise<EngineJobHandle> {
    return this.createPrediction(
      requireEnv("REPLICATE_MUSIC_MODEL_VERSION"),
      {
        prompt: req.stylePrompt,
        lyrics: req.lyrics,
        duration: req.durationMs ? Math.round(req.durationMs / 1000) : undefined,
        seed: req.seed,
      },
      req.webhookUrl,
    );
  }

  separateStems(req: SeparateStemsRequest): Promise<EngineJobHandle> {
    return this.createPrediction(
      requireEnv("REPLICATE_DEMUCS_MODEL_VERSION"),
      { audio: req.audioUrl, stem: "vocals", output_format: "wav" },
      req.webhookUrl,
    );
  }

  async verifyAndParseWebhook(
    req: Request,
    rawBody: string,
  ): Promise<ProviderEvent> {
    await verifyStandardWebhook(req, rawBody, requireEnv("REPLICATE_WEBHOOK_SECRET"));

    const prediction = JSON.parse(rawBody) as ReplicatePrediction;

    switch (prediction.status) {
      case "succeeded":
        return {
          status: "succeeded",
          providerJobId: prediction.id,
          outputUrls: normalizeOutput(prediction.output),
        };
      case "failed":
      case "canceled":
        return {
          status: "failed",
          providerJobId: prediction.id,
          error: prediction.error ?? `Prédiction ${prediction.status}`,
        };
      default:
        return { status: "running", providerJobId: prediction.id };
    }
  }
}

/**
 * La sortie Replicate est une URL, une liste d'URLs ou un objet nommé selon le
 * modèle (Demucs renvoie un objet {vocals, drums, bass, other}). On aplatit.
 */
function normalizeOutput(
  output: ReplicatePrediction["output"],
): string[] {
  if (!output) return [];
  if (typeof output === "string") return [output];
  if (Array.isArray(output)) return output.filter((u) => typeof u === "string");
  return Object.values(output).filter((u) => typeof u === "string");
}
