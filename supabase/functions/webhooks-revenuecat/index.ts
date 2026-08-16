// POST /webhooks-revenuecat — crédite le ledger après un achat.
//
// RevenueCat n'utilise pas de HMAC : il renvoie le secret partagé configuré
// dans son tableau de bord, en clair, dans l'en-tête Authorization. La
// comparaison se fait donc à temps constant, et le crédit passe par
// `grant_credits`, idempotente sur l'ID d'événement — un webhook rejoué ne
// crédite jamais deux fois.

import { badRequest, handler, json, requireEnv, HttpError } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { constantTimeEquals } from "../_shared/webhook-signature.ts";

/**
 * Crédits accordés par produit.
 *
 * ⚠️ Valeurs provisoires : la grille définitive est arrêtée au Lot 5 de la
 * Phase 1, à partir du coût réel par morceau mesuré au Lot 1. Un identifiant
 * inconnu n'est jamais crédité au hasard — il est journalisé et acquitté.
 */
const CREDITS_BY_PRODUCT: Record<string, number> = {
  "melodix_pack_small": 50,
  "melodix_pack_large": 250,
  "melodix_sub_monthly": 300,
  "melodix_sub_yearly": 4000,
};

/** Types d'événements qui accordent des crédits. */
const GRANTING_EVENTS = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "NON_RENEWING_PURCHASE",
  "UNCANCELLATION",
]);

/** Types d'événements qui font retomber l'utilisateur en gratuit. */
const REVOKING_EVENTS = new Set(["EXPIRATION"]);

interface RevenueCatEvent {
  id: string;
  type: string;
  app_user_id: string;
  product_id?: string | null;
  entitlement_ids?: string[] | null;
}

Deno.serve(handler(async (req) => {
  if (req.method !== "POST") throw badRequest("Méthode non autorisée");

  const authorization = req.headers.get("Authorization") ?? "";
  if (!constantTimeEquals(authorization, requireEnv("REVENUECAT_WEBHOOK_SECRET"))) {
    throw new HttpError(401, "Webhook rejeté : secret invalide", "invalid_signature");
  }

  const { event } = await req.json() as { event?: RevenueCatEvent };
  if (!event?.id || !event.type || !event.app_user_id) {
    throw badRequest("Charge utile RevenueCat incomplète");
  }

  // RevenueCat envoie des événements de test depuis son tableau de bord :
  // on les acquitte sans toucher à la comptabilité.
  if (event.type === "TEST") return json({ ok: true, ignored: "test" });

  const db = serviceClient();

  if (REVOKING_EVENTS.has(event.type)) {
    // L'abonnement expire : l'utilisateur repasse en gratuit mais garde les
    // crédits déjà achetés — ils ont été payés.
    await db.from("profiles").update({ tier: "free" }).eq("id", event.app_user_id);
    return json({ ok: true, tier: "free" });
  }

  if (!GRANTING_EVENTS.has(event.type)) {
    return json({ ok: true, ignored: event.type });
  }

  const amount = event.product_id ? CREDITS_BY_PRODUCT[event.product_id] : undefined;
  if (!amount) {
    // Produit non répertorié : on acquitte en 200 pour que RevenueCat cesse de
    // réessayer, et on journalise pour corriger la grille.
    console.error("revenuecat_unknown_product", {
      eventId: event.id,
      productId: event.product_id,
    });
    return json({ ok: true, ignored: "unknown_product" });
  }

  // Idempotent : l'index unique sur external_event_id absorbe les rejeux.
  const { error } = await db.rpc("grant_credits", {
    p_user_id: event.app_user_id,
    p_amount: amount,
    p_reason: `revenuecat:${event.type.toLowerCase()}`,
    p_external_event_id: event.id,
  });

  if (error) {
    // Erreur transitoire : on renvoie 500 pour que RevenueCat réessaie.
    throw new Error(`Crédit impossible : ${error.message}`);
  }

  const tier = event.entitlement_ids?.length ? "pro" : undefined;
  if (tier) {
    await db.from("profiles").update({ tier }).eq("id", event.app_user_id);
  }

  return json({ ok: true, credited: amount });
}));
