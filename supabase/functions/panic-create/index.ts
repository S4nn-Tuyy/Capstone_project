import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

declare const EdgeRuntime: {
  waitUntil(promise: Promise<unknown>): void;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const allowedTypes = new Set(["keamanan", "kebakaran", "medis", "lainnya"]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

async function escalateAfterSixtySeconds(
  admin: ReturnType<typeof createClient>,
  incidentId: string,
): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 60_000));
  const { data, error } = await admin.rpc("escalate_insiden_if_unanswered", {
    p_insiden_id: incidentId,
  });
  if (error) {
    console.error("Panic escalation failed", incidentId, error.message);
    return;
  }
  if (data === true) console.info("Panic incident escalated", incidentId);
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse({ error: "Authentication required" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publishableKey || !serviceRoleKey) {
    console.error("Required Supabase Edge Function secrets are unavailable");
    return jsonResponse({ error: "Server configuration error" }, 500);
  }

  const caller = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: authError } = await caller.auth.getUser();
  if (authError || !userData.user) {
    return jsonResponse({ error: "Invalid session" }, 401);
  }

  let body: { request_id?: unknown; jenis?: unknown; is_latihan?: unknown };
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  if (typeof body.request_id !== "string" || !uuidPattern.test(body.request_id)) {
    return jsonResponse({ error: "request_id must be a UUID" }, 400);
  }
  if (typeof body.jenis !== "string" || !allowedTypes.has(body.jenis)) {
    return jsonResponse({ error: "Unsupported incident type" }, 400);
  }
  if (body.is_latihan !== undefined && typeof body.is_latihan !== "boolean") {
    return jsonResponse({ error: "is_latihan must be boolean" }, 400);
  }

  const isTraining = body.is_latihan === true;
  const { data, error } = await caller.rpc("create_insiden", {
    p_request_id: body.request_id,
    p_jenis: body.jenis,
    p_is_latihan: isTraining,
  });
  if (error) {
    console.error("Could not create panic incident", error.message);
    const status = error.code === "42501" ? 403 : 400;
    return jsonResponse({ error: error.message }, status);
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) return jsonResponse({ error: "Incident was not created" }, 500);

  if (!result.is_training && result.incident_id) {
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    // This is a best-effort, bounded background task on Supabase Edge Runtime.
    // A durable scheduler/queue is still preferable for production-critical alerts.
    EdgeRuntime.waitUntil(escalateAfterSixtySeconds(admin, result.incident_id));
  }

  return jsonResponse({
    incident: result,
    notification: "in_app_realtime",
    escalation_scheduled: !result.is_training && Boolean(result.incident_id),
  }, 202);
});
