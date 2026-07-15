import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Supabase service configuration is missing");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export function userClient(req: Request): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !key) throw new Error("Supabase public configuration is missing");
  return createClient(url, key, {
    global: { headers: { Authorization: req.headers.get("Authorization") || "" } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function authenticatedUser(req: Request) {
  const client = userClient(req);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) throw Object.assign(new Error("请先登录"), { status: 401 });
  return { client, user: data.user };
}

export function requireWorkerSecret(req: Request) {
  const expected = Deno.env.get("TRAINING_WORKER_SECRET") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization") || "";
  const actual = req.headers.get("x-worker-secret") || (authorization.startsWith("Bearer ") ? authorization.slice(7) : "");
  if (!expected || actual.length !== expected.length) throw Object.assign(new Error("worker authorization failed"), { status: 401 });
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ actual.charCodeAt(i);
  if (diff !== 0) throw Object.assign(new Error("worker authorization failed"), { status: 401 });
}
