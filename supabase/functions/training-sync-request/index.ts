import { authenticatedUser } from "../_shared/client.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";

Deno.serve(async req => {
  const options = handleOptions(req);if (options) return options;
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);
  try {
    const { client } = await authenticatedUser(req);
    const body = await req.json().catch(() => ({}));
    const platform = body.platform ? String(body.platform) : null;
    const { data, error } = await client.rpc("enqueue_training_sync", { platform_name: platform });
    if (error) throw error;
    return jsonResponse(data);
  } catch (error) {
    const value = error as { message?: string; status?: number };
    return jsonResponse({ error: value.message || "无法创建同步任务" }, value.status || 500);
  }
});
