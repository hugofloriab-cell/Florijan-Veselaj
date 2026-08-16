// Vérification de signature au format Standard Webhooks (utilisé par Replicate,
// fal.ai, RevenueCat et la plupart des fournisseurs).
//
// Sans cette vérification, l'endpoint de webhook est une porte ouverte :
// n'importe qui pourrait déclarer un job terminé et injecter l'URL audio de son
// choix dans le morceau d'un utilisateur.

import { HttpError } from "./http.ts";

const TOLERANCE_SECONDS = 5 * 60;

const unauthorizedWebhook = (reason: string) =>
  new HttpError(401, `Webhook rejeté : ${reason}`, "invalid_signature");

// Allocation explicite sur un ArrayBuffer : WebCrypto attend un `BufferSource`,
// que le Uint8Array par défaut (adossé à un ArrayBufferLike) ne satisfait pas.
function base64ToBytes(b64: string): Uint8Array<ArrayBuffer> {
  const binary = atob(b64);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function utf8Bytes(input: string): Uint8Array<ArrayBuffer> {
  const encoded = new TextEncoder().encode(input);
  const bytes = new Uint8Array(new ArrayBuffer(encoded.byteLength));
  bytes.set(encoded);
  return bytes;
}

/** Comparaison à temps constant : une comparaison naïve fuit la signature. */
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/**
 * @param secret Secret du fournisseur, avec ou sans le préfixe `whsec_`.
 * @throws HttpError 401 si la signature, l'horodatage ou les en-têtes sont invalides.
 */
export async function verifyStandardWebhook(
  req: Request,
  rawBody: string,
  secret: string,
): Promise<void> {
  const id = req.headers.get("webhook-id");
  const timestamp = req.headers.get("webhook-timestamp");
  const signatureHeader = req.headers.get("webhook-signature");

  if (!id || !timestamp || !signatureHeader) {
    throw unauthorizedWebhook("en-têtes de signature absents");
  }

  // Fenêtre temporelle : borne la fenêtre de rejeu d'une requête interceptée.
  const sentAt = Number(timestamp);
  if (!Number.isFinite(sentAt)) {
    throw unauthorizedWebhook("horodatage invalide");
  }
  if (Math.abs(Date.now() / 1000 - sentAt) > TOLERANCE_SECONDS) {
    throw unauthorizedWebhook("horodatage hors tolérance");
  }

  const key = await crypto.subtle.importKey(
    "raw",
    base64ToBytes(secret.replace(/^whsec_/, "")),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expected = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, utf8Bytes(`${id}.${timestamp}.${rawBody}`)),
  );

  // L'en-tête peut porter plusieurs signatures séparées par des espaces
  // (rotation de secret en cours) : une seule correspondance suffit.
  const candidates = signatureHeader
    .split(" ")
    .map((part) => part.split(",", 2)[1])
    .filter((sig): sig is string => Boolean(sig));

  for (const candidate of candidates) {
    try {
      if (timingSafeEqual(expected, base64ToBytes(candidate))) return;
    } catch {
      // Signature mal encodée : on passe à la suivante.
    }
  }

  throw unauthorizedWebhook("signature invalide");
}
