// Deux clients Supabase, deux niveaux de confiance.
//
// - userClient : porte le JWT de l'appelant, donc la RLS s'applique. C'est le
//   client par défaut pour tout ce qui touche aux données d'un utilisateur.
// - serviceClient : contourne la RLS. Réservé aux webhooks et aux tâches
//   système, jamais utilisé pour servir une requête client directement.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { requireEnv, unauthorized } from "./http.ts";

export function serviceClient(): SupabaseClient {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false } },
  );
}

export function userClient(req: Request): SupabaseClient {
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    throw unauthorized();
  }
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_ANON_KEY"),
    {
      auth: { persistSession: false },
      global: { headers: { Authorization: authorization } },
    },
  );
}

export async function requireUserId(client: SupabaseClient): Promise<string> {
  // getUser() valide la signature du JWT côté serveur : un token forgé est
  // rejeté ici, avant d'atteindre la moindre requête.
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) {
    throw unauthorized("Session invalide ou expirée");
  }
  return data.user.id;
}
