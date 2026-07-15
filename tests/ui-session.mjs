import { createClient } from "@supabase/supabase-js";

const url = process.env.TEST_URL;
const serviceKey = process.env.TEST_SERVICE;
const anonKey = process.env.TEST_ANON;
if (!url || !serviceKey || !anonKey) throw new Error("UI test environment is incomplete");

const service = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
});

if (process.argv[2] === "create") {
  const email = `codex-ui-${crypto.randomUUID()}@example.com`;
  const created = await service.auth.admin.createUser({ email, email_confirm: true, user_metadata: { full_name: "界面验收用户" } });
  if (created.error) throw created.error;
  try {
    const generated = await service.auth.admin.generateLink({ type: "magiclink", email, options: { redirectTo: "http://127.0.0.1:4173/#account" } });
    if (generated.error) throw generated.error;
    const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
    const verified = await client.auth.verifyOtp({ token_hash: generated.data.properties.hashed_token, type: "magiclink" });
    if (verified.error) throw verified.error;
    console.log(JSON.stringify({ id: created.data.user.id, session: verified.data.session }));
  } catch (error) {
    await service.auth.admin.deleteUser(created.data.user.id);
    throw error;
  }
} else if (process.argv[2] === "delete") {
  const id = process.argv[3];
  if (!/^[0-9a-f-]{36}$/i.test(id || "")) throw new Error("Invalid UI test user id");
  const deleted = await service.auth.admin.deleteUser(id);
  if (deleted.error) throw deleted.error;
} else {
  throw new Error("Expected create or delete mode");
}
