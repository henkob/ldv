import { createClient } from "npm:@supabase/supabase-js@2.89.0";
import jpeg from "npm:jpeg-js@0.4.4";
import pngjs from "npm:pngjs@7.0.0";

const origin = "https://ldv.nu";
const cors = {
  "Access-Control-Allow-Origin": origin,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "private, no-store",
};

const reply = (status: number) => new Response(null, { status, headers: cors });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return reply(204);
  if (request.method !== "POST") return reply(405);

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401);

  const payload = await request.json().catch(() => null);
  const questionId = payload?.questionId;
  if (!Number.isSafeInteger(questionId) || questionId < 1) return reply(400);

  const url = Deno.env.get("SUPABASE_URL")!;
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const user = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    ...options,
    global: { headers: { Authorization: authorization } },
  });
  const { data: account, error: authError } = await user.auth.getUser(authorization.slice(7));
  if (authError || !account.user) return reply(401);

  const { data: allowed, error: accessError } = await user.rpc("ldv_zoo_can_view_question", {
    p_question_id: questionId,
  });
  if (accessError) return reply(503);
  if (allowed !== true) return reply(404);

  const storage = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, options);
  const { data: path, error: sourceError } = await storage.rpc("ldv_zoo_portrait_source", {
    p_question_id: questionId,
  });
  if (sourceError) return reply(503);
  if (!path) return reply(404);

  const { data: image, error: imageError } = await storage.storage.from("ldv-avatars").download(path);
  if (imageError || !image) return reply(404);
  if (image.size > 5 * 1024 * 1024) return reply(422);

  try {
    // Encode only pixel data. Storage paths, filenames and image metadata
    // must not reveal the name to the player.
    const bytes = new Uint8Array(await image.arrayBuffer());
    const isPng = bytes[0] === 137 && bytes[1] === 80;
    if (isPng) {
      const header = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      const width = header.getUint32(16);
      const height = header.getUint32(20);
      if (!width || !height || width * height > 12_000_000) return reply(422);
    }
    const pixels = isPng
      ? pngjs.PNG.sync.read(bytes)
      : jpeg.decode(bytes, { maxResolutionInMP: 12, maxMemoryUsageInMB: 64 });
    const clean = jpeg.encode({ width: pixels.width, height: pixels.height, data: pixels.data }, 85);
    return new Response(new Uint8Array(clean.data), {
      headers: { ...cors, "Content-Type": "application/octet-stream", "X-Content-Type-Options": "nosniff" },
    });
  } catch {
    return reply(422);
  }
});
