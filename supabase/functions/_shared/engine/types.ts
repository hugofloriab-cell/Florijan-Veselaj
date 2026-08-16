// Interface du moteur audio.
//
// Le choix du fournisseur n'est pas encore arrêté (Lot 1 de la Phase 1 : c'est
// une décision d'abord juridique — beaucoup de modèles populaires sont en
// licence non commerciale). Tout le reste du backend est écrit contre cette
// interface pour que le remplacement du fournisseur reste une seule classe à
// réécrire, pas une refonte.

export type JobKind =
  | "generate"
  | "separate_stems"
  | "regenerate_section"
  | "restyle"
  | "vocal_align"
  | "export";

export interface GenerateRequest {
  jobId: string;
  /** Prompt de style : genre, instrumentation, ambiance. */
  stylePrompt: string;
  /** Paroles aplaties, avec marqueurs de section ([Couplet 1], [Refrain]…). */
  lyrics: string;
  durationMs?: number;
  /**
   * Seed reproductible. Critère éliminatoire dans le choix du moteur : sans
   * elle, un segment re-généré ne se raccorde pas au reste du morceau.
   */
  seed?: number;
  webhookUrl: string;
}

export interface SeparateStemsRequest {
  jobId: string;
  /** URL signée, à durée courte, du master à séparer. */
  audioUrl: string;
  webhookUrl: string;
}

export interface EngineJobHandle {
  /** Identifiant du job côté fournisseur — sert à corréler le webhook. */
  providerJobId: string;
}

/** Événement de webhook, une fois normalisé depuis le format du fournisseur. */
export type ProviderEvent =
  | { status: "running"; providerJobId: string }
  | { status: "succeeded"; providerJobId: string; outputUrls: string[] }
  | { status: "failed"; providerJobId: string; error: string };

export interface MusicEngine {
  readonly name: string;
  generate(req: GenerateRequest): Promise<EngineJobHandle>;
  separateStems(req: SeparateStemsRequest): Promise<EngineJobHandle>;
  /** Vérifie la signature du webhook et normalise sa charge utile. */
  verifyAndParseWebhook(req: Request, rawBody: string): Promise<ProviderEvent>;
}
