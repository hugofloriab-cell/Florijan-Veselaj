import { ReplicateEngine } from "./replicate.ts";
import type { MusicEngine } from "./types.ts";

export type * from "./types.ts";

/**
 * Point d'entrée unique vers le moteur audio. Tout le backend passe par ici :
 * changer de fournisseur revient à ajouter un `case`, pas à toucher aux
 * Edge Functions.
 */
export function getEngine(): MusicEngine {
  const name = Deno.env.get("MUSIC_ENGINE") ?? "replicate";
  switch (name) {
    case "replicate":
      return new ReplicateEngine();
    default:
      throw new Error(`Moteur audio inconnu : ${name}`);
  }
}

/**
 * Coût en crédits par type de job.
 *
 * ⚠️ Valeurs provisoires. Elles sont arrêtées au Lot 5 de la Phase 1, à partir
 * des coûts réels mesurés au Lot 1 — pas devinées ici.
 */
export const CREDIT_COST: Record<string, number> = {
  generate: 10,
  regenerate_section: 4,
  restyle: 8,
  vocal_align: 6,
  separate_stems: 0, // enchaîné automatiquement, déjà payé par la génération
  export: 0,
};
