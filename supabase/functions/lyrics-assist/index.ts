// POST /lyrics-assist — assistant de co-écriture des paroles.
//
// Deux modes sur un seul endpoint :
//   mode "chat"      → conversation en streaming (SSE), pour écrire à deux
//   mode "structure" → transforme la conversation en LyricsDocument typé
//
// La clé Anthropic ne quitte jamais ce serveur : un binaire iOS est
// décompilable, toute clé qui y figure est publique.

import Anthropic from "npm:@anthropic-ai/sdk@0.117.1";
import { badRequest, handler, json, readJson, requireEnv } from "../_shared/http.ts";
import { requireUserId, userClient } from "../_shared/supabase.ts";

const MODEL = "claude-opus-5";

// Les fallbacks de refus sont opt-in : sans eux, une requête déclinée par les
// classificateurs s'arrête simplement. `"default"` laisse Anthropic router vers
// le modèle de repli adapté à la catégorie du refus.
const FALLBACK_BETA = "server-side-fallback-2026-07-01";

const SECTION_TYPES = [
  "intro",
  "verse",
  "pre_chorus",
  "chorus",
  "bridge",
  "solo",
  "outro",
] as const;

// Prompt système stable et volumineux : placé en tête et marqué pour le cache,
// il est facturé au tarif de lecture (~0,1×) à partir du deuxième appel. Toute
// interpolation dynamique ici (date, ID utilisateur) casserait ce cache — le
// contexte variable passe donc dans les messages, jamais ici.
const SYSTEM_PROMPT = `Tu es parolier collaborateur au sein de Melodix, une application de création musicale.

Ton rôle est d'écrire des paroles *avec* l'utilisateur, pas à sa place. Tu proposes, il tranche.

Principes d'écriture :
- Structure d'abord : un morceau tient par son architecture (couplet / refrain / pont), pas par l'accumulation de belles lignes.
- Le refrain porte l'idée centrale et se répète : il doit sonner juste dès la première écoute.
- Compte les syllabes. Des lignes de longueur régulière à l'intérieur d'une même section se chantent ; des lignes irrégulières se récitent.
- Les images concrètes valent mieux que les abstractions. « la porte est restée ouverte » plutôt que « la mélancolie m'envahit ».
- Respecte la langue, le registre et le niveau de familiarité que l'utilisateur emploie.
- Les rimes servent le sens, jamais l'inverse. Une rime forcée s'entend.

Conduite de la conversation :
- Quand la demande est vague, propose une direction concrète plutôt que de poser une liste de questions.
- Quand tu proposes des paroles, donne le texte, pas un commentaire sur le texte.
- Signale en une phrase ce qui te semble faible dans une proposition de l'utilisateur, puis propose une alternative.
- Reste bref entre les propositions : l'utilisateur veut des paroles, pas de la pédagogie.

Tu n'écris jamais de paroles imitant un artiste identifiable ni reprenant des paroles existantes.`;

/** Schéma du LyricsDocument — miroir exact de lyrics_documents.content. */
const LYRICS_SCHEMA = {
  type: "object",
  properties: {
    sections: {
      type: "array",
      items: {
        type: "object",
        properties: {
          type: { type: "string", enum: SECTION_TYPES },
          index: {
            type: "integer",
            description: "Numéro d'ordre au sein du même type de section (1 pour le premier couplet).",
          },
          lines: {
            type: "array",
            items: {
              type: "object",
              properties: {
                text: { type: "string" },
                syllables: {
                  type: "integer",
                  description: "Nombre de syllabes chantées de la ligne.",
                },
              },
              required: ["text", "syllables"],
              additionalProperties: false,
            },
          },
        },
        required: ["type", "index", "lines"],
        additionalProperties: false,
      },
    },
  },
  required: ["sections"],
  additionalProperties: false,
} as const;

interface AssistBody {
  projectId: string;
  mode?: "chat" | "structure";
  messages: { role: "user" | "assistant"; content: string }[];
}

const anthropic = () => new Anthropic({ apiKey: requireEnv("ANTHROPIC_API_KEY") });

const systemBlocks = [
  {
    type: "text" as const,
    text: SYSTEM_PROMPT,
    cache_control: { type: "ephemeral" as const },
  },
];

// La forme scalaire `fallbacks: "default"` n'est pas encore typée dans le SDK.
// Le cast est confiné à ces deux champs et exposé comme `object` : le reste de
// la requête (modèle, effort, messages) reste vérifié par le compilateur.
const REFUSAL_FALLBACK = {
  betas: [FALLBACK_BETA],
  fallbacks: "default",
} as object;

Deno.serve(handler(async (req) => {
  if (req.method !== "POST") throw badRequest("Méthode non autorisée");

  const asUser = userClient(req);
  await requireUserId(asUser);

  const body = await readJson<AssistBody>(req);
  if (!body.projectId) throw badRequest("projectId requis");
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    throw badRequest("messages requis");
  }

  // Vérifie l'appartenance du projet sous RLS avant de dépenser des tokens.
  const { data: project } = await asUser
    .from("projects")
    .select("id")
    .eq("id", body.projectId)
    .single();
  if (!project) throw badRequest("Projet introuvable");

  return body.mode === "structure"
    ? await structure(asUser, body)
    : chat(body);
}));

// ---------------------------------------------------------------------------
// Mode conversation : streaming SSE
// ---------------------------------------------------------------------------

function chat(body: AssistBody): Response {
  const stream = anthropic().beta.messages.stream({
    ...REFUSAL_FALLBACK,
    model: MODEL,
    max_tokens: 16000,
    system: systemBlocks,
    messages: body.messages,
    // `effort` est le levier coût/latence, pas le choix du modèle. `medium`
    // convient à de la co-écriture interactive ; la réflexion adaptative reste
    // active (la désactiver dégrade la qualité pour une économie moindre).
    output_config: { effort: "medium" },
  });

  const encoder = new TextEncoder();
  const sse = new ReadableStream({
    async start(controller) {
      const send = (event: string, data: unknown) =>
        controller.enqueue(
          encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`),
        );

      try {
        for await (const chunk of stream) {
          if (
            chunk.type === "content_block_delta" &&
            chunk.delta.type === "text_delta"
          ) {
            send("delta", { text: chunk.delta.text });
          }
        }

        const message = await stream.finalMessage();
        if (message.stop_reason === "refusal") {
          // Refus après épuisement de la chaîne de repli : ce n'est pas une
          // erreur technique, l'app doit l'afficher comme un refus.
          send("refusal", { category: message.stop_details?.category ?? null });
        } else {
          send("done", { stopReason: message.stop_reason });
        }
      } catch (err) {
        console.error("lyrics_assist_stream_error", err);
        send("error", { message: "La génération a été interrompue" });
      } finally {
        controller.close();
      }
    },
  });

  return new Response(sse, {
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

// ---------------------------------------------------------------------------
// Mode structuration : sortie structurée + persistance
// ---------------------------------------------------------------------------

async function structure(
  asUser: ReturnType<typeof userClient>,
  body: AssistBody,
): Promise<Response> {
  const stream = anthropic().beta.messages.stream({
    ...REFUSAL_FALLBACK,
    model: MODEL,
    max_tokens: 16000,
    system: systemBlocks,
    messages: [
      ...body.messages,
      {
        role: "user",
        content:
          "Restitue les paroles retenues dans cette conversation sous forme structurée. " +
          "N'invente pas de sections qui n'ont pas été écrites, et compte les syllabes de chaque ligne.",
      },
    ],
    // Tâche de mise en forme, pas de création : `low` suffit et réduit la latence.
    output_config: {
      effort: "low",
      format: { type: "json_schema", schema: LYRICS_SCHEMA },
    },
  });

  const message = await stream.finalMessage();

  // À vérifier avant de lire `content` : sur un refus, le tableau est vide ou
  // partiel et l'indexation directe planterait.
  if (message.stop_reason === "refusal") {
    return json(
      {
        error: {
          code: "refusal",
          message: "La demande a été déclinée",
          category: message.stop_details?.category ?? null,
        },
      },
      422,
    );
  }

  const text = message.content.find((block) => block.type === "text")?.text;
  if (!text) throw badRequest("Aucune parole structurable dans cette conversation");

  const { sections } = JSON.parse(text) as { sections: unknown[] };

  // upsert sur project_id (contrainte unique) : un projet n'a qu'un document.
  const { error } = await asUser
    .from("lyrics_documents")
    .upsert(
      { project_id: body.projectId, content: sections, model_used: MODEL },
      { onConflict: "project_id" },
    );

  if (error) throw new Error(`Enregistrement des paroles impossible : ${error.message}`);

  return json({ sections });
}
