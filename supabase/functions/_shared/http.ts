// Réponses HTTP et gestion d'erreurs communes aux Edge Functions.
//
// Pas d'en-têtes CORS : le client est une app iOS native (ADR 000), pas un
// navigateur. Les ajouter reviendrait à autoriser un appelant qui n'existe pas.

export class HttpError extends Error {
  constructor(readonly status: number, message: string, readonly code?: string) {
    super(message);
  }
}

export const badRequest = (m: string) => new HttpError(400, m, "bad_request");
export const unauthorized = (m = "Authentification requise") =>
  new HttpError(401, m, "unauthorized");
export const forbidden = (m: string) => new HttpError(403, m, "forbidden");
export const paymentRequired = (m = "Crédits insuffisants") =>
  new HttpError(402, m, "insufficient_credits");

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

/**
 * Enveloppe un handler : convertit les exceptions en réponses JSON typées et
 * garantit qu'aucune trace interne ne fuit vers le client.
 */
export function handler(fn: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    try {
      return await fn(req);
    } catch (err) {
      if (err instanceof HttpError) {
        return json({ error: { code: err.code, message: err.message } }, err.status);
      }
      // Le détail part dans les logs, jamais dans la réponse.
      console.error("unhandled_error", err);
      return json(
        { error: { code: "internal_error", message: "Erreur interne" } },
        500,
      );
    }
  };
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Variable d'environnement manquante : ${name}`);
  }
  return value;
}

export async function readJson<T>(req: Request): Promise<T> {
  try {
    return (await req.json()) as T;
  } catch {
    throw badRequest("Corps de requête JSON invalide");
  }
}
