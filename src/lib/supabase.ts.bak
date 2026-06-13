import { createBrowserClient } from "@supabase/ssr";

/**
 * Supabase client (browser). Optional — the tool runs without it.
 * Only saved searches + lead persistence need this. If the env vars
 * aren't set, `isSupabaseConfigured()` returns false and the UI hides
 * the save/load features.
 */

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

export function isSupabaseConfigured(): boolean {
  return Boolean(url && anonKey);
}

export function createClient() {
  if (!url || !anonKey) {
    throw new Error(
      "Supabase isn't configured. Add NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY."
    );
  }
  return createBrowserClient(url, anonKey);
}
