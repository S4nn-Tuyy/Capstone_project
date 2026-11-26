import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const kinds = new Set(["umum", "penting", "darurat"]);
const audiences = new Set(["semua", "rt", "peran"]);
const roles = new Set(["warga", "security", "pengurus_rt", "pengurus_rw", "admin"]);

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
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
  if (authError || !userData.user) return jsonResponse({ error: "Invalid session" }, 401);

  let body: {
    jenis?: unknown;
    audiens?: unknown;
    target_rt_id?: unknown;
    target_peran?: unknown;
    judul?: unknown;
    isi?: unknown;
  };
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  if (typeof body.jenis !== "string" || !kinds.has(body.jenis)) {
    return jsonResponse({ error: "Jenis pengumuman tidak valid" }, 400);
  }
  if (typeof body.audiens !== "string" || !audiences.has(body.audiens)) {
    return jsonResponse({ error: "Audiens tidak valid" }, 400);
  }
  if (typeof body.judul !== "string" || body.judul.trim().length < 1 || body.judul.trim().length > 120) {
    return jsonResponse({ error: "Judul wajib diisi (maksimal 120 karakter)" }, 400);
  }
  if (typeof body.isi !== "string" || body.isi.trim().length < 1 || body.isi.trim().length > 5000) {
    return jsonResponse({ error: "Isi wajib diisi (maksimal 5000 karakter)" }, 400);
  }

  const audience = body.audiens;
  let targetRtId: string | null = null;
  let targetRole: string | null = null;
  if (audience === "rt") {
    if (typeof body.target_rt_id !== "string" || !uuidPattern.test(body.target_rt_id)) {
      return jsonResponse({ error: "Target RT tidak valid" }, 400);
    }
    targetRtId = body.target_rt_id;
  } else if (audience === "peran") {
    if (typeof body.target_peran !== "string" || !roles.has(body.target_peran)) {
      return jsonResponse({ error: "Target peran tidak valid" }, 400);
    }
    targetRole = body.target_peran;
  } else if (body.target_rt_id != null || body.target_peran != null) {
    return jsonResponse({ error: "Audiens umum tidak menerima target tambahan" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await admin.rpc("publish_pengumuman", {
    p_author_id: userData.user.id,
    p_jenis: body.jenis,
    p_audiens: audience,
    p_target_rt_id: targetRtId,
    p_target_peran: targetRole,
    p_judul: body.judul.trim(),
    p_isi: body.isi.trim(),
  });
  if (error) {
    console.error("Could not publish announcement", error.code, error.message);
    const status = error.code === "42501" ? 403 : 400;
    return jsonResponse({ error: error.message }, status);
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) return jsonResponse({ error: "Pengumuman tidak berhasil diterbitkan" }, 500);
  return jsonResponse({ announcement: result }, 201);
});
