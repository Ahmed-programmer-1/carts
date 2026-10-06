// ============================================================
// مكتبتي — Edge Function: publish-to-community
// ============================================================
// طريقة النشر: من لوحة Supabase (Dashboard) > Edge Functions > Create
// a new function > اسمها "publish-to-community" > الصق الكود ده كامل
// كما هو > Deploy. مفيش سطر أوامر (CLI) مطلوب.
//
// ده الملف الوحيد اللي فيه توكن GitHub، وهو موجود هنا بس — على سيرفر
// Supabase — ومش بيتبعت للمتصفح أبدًا تحت أي ظرف. الموقع العام
// (index.html) بيكلم الدالة دي بس عن طريق sb.functions.invoke(...)،
// وهي اللي بتتكلم مع GitHub بالنيابة عنه.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ------------------------------------------------------------
// 🔑 حط بيانات GitHub هنا مباشرة (التوكن هيفضل هنا بس، جوه سيرفر
// Supabase — متتنسخش أو تتحط في أي ملف تاني):
// ------------------------------------------------------------
const GITHUB_TOKEN = "ضع_التوكن_هنا"; // Fine-grained PAT — صلاحية Contents: Read & Write على الريبو ده بس كفاية
const GITHUB_OWNER = "ahmed-programmer-1"; // اسم حساب GitHub بتاعك
const GITHUB_REPO = "CC"; // اسم الريبو (تأكد منه من رابط الموقع/GitHub Pages)
const GITHUB_BRANCH = "main"; // اسم الفرع الأساسي — عدّله لو مختلف عندك
const COMMUNITY_FOLDER = "ملفات المجتمع"; // اسم المجلد اللي هتترفع فيه الملفات

// الكلمات دي محجوزة — مالهاش قسم يتحطها بنفسه، لأنها إما بتتحدد أوتوماتيك
// (الأكثر تحميلاً) أو الأدمن بس اللي بيحددها (المميزة)
const RESERVED_CATEGORIES = ["مميز", "مميزة", "المميزة", "الأكثر تحميلاً", "الأكثر تحميلا", "الأكثر متابعة", "trending", "featured"];

function sanitizeCategories(input: unknown, mimeType: string | null): string[] {
  const raw = Array.isArray(input) ? input : [];
  const cleaned = raw
    .map((c) => String(c || "").trim())
    .filter((c) => c && !RESERVED_CATEGORIES.includes(c.toLowerCase()) && !RESERVED_CATEGORIES.includes(c));
  // أي ملف PDF بيتحط أوتوماتيك في قسم "ملفات PDF" مهما كان مين رافعه
  // ومهما كانت الأقسام التانية اللي اختارها
  if ((mimeType || "").toLowerCase().includes("pdf") && !cleaned.includes("ملفات PDF")) {
    cleaned.push("ملفات PDF");
  }
  return [...new Set(cleaned)].slice(0, 10);
}
// ------------------------------------------------------------

// دول بيتحطوا تلقائيًا من Supabase لكل Edge Function — مش محتاج تكتبهم انت
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function ghHeaders() {
  return {
    Authorization: "Bearer " + GITHUB_TOKEN,
    Accept: "application/vnd.github+json",
  };
}

async function ghGetSha(path: string): Promise<string | null> {
  const url = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${encodeURI(path)}?ref=${GITHUB_BRANCH}`;
  const res = await fetch(url, { headers: ghHeaders() });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error("تعذّر قراءة GitHub (" + res.status + ")");
  const j = await res.json();
  return j.sha as string;
}

// نفس حساب Git للـblob: sha1("blob <size>\0" + bytes) — لو الملف على GitHub متطابق
// معاه، منعيدش رفعه (بيوفر commit مكرر ووقت ومساحة)
async function gitBlobSha(bytes: Uint8Array): Promise<string> {
  const head = new TextEncoder().encode(`blob ${bytes.length}\0`);
  const all = new Uint8Array(head.length + bytes.length);
  all.set(head, 0); all.set(bytes, head.length);
  const digest = await crypto.subtle.digest("SHA-1", all);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function ghPutFile(path: string, base64Content: string, message: string, localSha?: string) {
  const sha = await ghGetSha(path);
  if (sha && localSha && sha === localSha) {
    return { content: { download_url: `https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/${GITHUB_BRANCH}/${encodeURI(path)}` }, unchanged: true };
  }
  const url = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${encodeURI(path)}`;
  const res = await fetch(url, {
    method: "PUT",
    headers: { ...ghHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({
      message,
      content: base64Content,
      branch: GITHUB_BRANCH,
      ...(sha ? { sha } : {}),
    }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error("فشل رفع GitHub (" + res.status + "): " + t.slice(0, 300));
  }
  return await res.json();
}

// تحويل الملف لـbase64 على شكل أجزاء صغيرة — عشان ملفات كبيرة ما
// تكسرش الدالة (String.fromCharCode مع كل البايتات مرة واحدة بيفشل
// على ملفات كبيرة نسبيًا)
// اسم ملف آمن لمسار GitHub: يشيل / \\ .. وأي رموز تحكم، ويحدد الطول
function safeGhName(name: string): string {
  let n = String(name || "file").replace(/[\\/\u0000-\u001f<>:"|?*#%]/g, "_").replace(/\.{2,}/g, "_").trim();
  n = n.replace(/^\.+/, "_");
  if (!n) n = "file";
  if (n.length > 120) {
    const dot = n.lastIndexOf(".");
    const ext = dot > 0 && n.length - dot <= 10 ? n.slice(dot) : "";
    n = n.slice(0, 110) + ext;
  }
  return n;
}
const MAX_FILE_BYTES = 25 * 1024 * 1024; // حد أقصى للملف الواحد (GitHub Contents API + ذاكرة الدالة)
const MAX_FILES_PER_CALL = 20;
const DAILY_LIMIT = 40;

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader) return json({ error: "لازم تسجّل دخول" }, 401);

    // عميل بصلاحية المستخدم نفسه — بنستخدمه بس عشان نتأكد مين هو فعليًا
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "جلسة غير صالحة" }, 401);
    const userId = userData.user.id;

    const body = await req.json().catch(() => ({}));
    const cardId = body?.card_id;
    const requestedCategories = body?.categories;
    if (!cardId) return json({ error: "card_id مطلوب" }, 400);

    // عميل بصلاحية service role — بيتخطى RLS، محتاجينه عشان نقرأ/نكتب
    // بيانات مش بتاعة المستخدم مباشرة (زي جدول community_files)
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: card, error: cardErr } = await admin
      .from("cards")
      .select("id, name, owner_id, visibility, approved, deleted_at, profiles(display_name)")
      .eq("id", cardId)
      .single();
    if (cardErr || !card) return json({ error: "البطاقة مش موجودة" }, 404);
    if (card.owner_id !== userId) return json({ error: "مش مسموح — مش انت صاحب البطاقة دي" }, 403);
    // النشر بقى فوري — مش شرط الأدمن يوافق على البطاقة الأول. المراجعة
    // بقت بعدية: الملف بيظهر للعامة على طول (status الافتراضي 'pending')،
    // والأدمن بيراجعه من admin.html بعدين ويقرر يوافق أو يرفض
    if (card.visibility !== "public" || card.deleted_at) {
      return json({ error: "البطاقة لازم تكون عامة عشان تتنشر" }, 400);
    }

    // حد يومي لكل مستخدم: 40 ملف في آخر 24 ساعة (يحمي الريبو من الإغراق)
    const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    const { count: recent } = await admin.from("community_files").select("id", { count: "exact", head: true })
      .eq("owner_id", userId).gte("published_at", since);
    if ((recent || 0) >= DAILY_LIMIT) return json({ error: "وصلت للحد اليومي للنشر (" + DAILY_LIMIT + " ملف) — حاول بكرة" }, 429);

    const { data: files, error: filesErr } = await admin
      .from("files")
      .select("*")
      .eq("card_id", cardId);
    if (filesErr) return json({ error: filesErr.message }, 500);
    if (!files?.length) return json({ error: "لازم البطاقة تحتوي على ملف واحد على الأقل" }, 400);

    const ownerName = (card as any).profiles?.display_name || null;
    const published: string[] = [];
    const failed: string[] = [];

    for (const f of files.slice(0, MAX_FILES_PER_CALL)) {
      try {
        if ((f.size_bytes || 0) > MAX_FILE_BYTES) { failed.push(f.name + " (أكبر من 25MB)"); continue; }
        const { data: blob, error: dlErr } = await admin.storage.from("study-files").download(f.storage_path);
        if (dlErr || !blob) { failed.push(f.name); continue; }
        const bytes = new Uint8Array(await blob.arrayBuffer());
        const b64 = toBase64(bytes);
        const safeName = safeGhName(f.name);
        const ghPath = `${COMMUNITY_FOLDER}/${cardId}/${safeName}`;
        const result = await ghPutFile(ghPath, b64, `نشر ملفات المجتمع: ${card.name} — ${f.name}`, await gitBlobSha(bytes));
        const categories = sanitizeCategories(requestedCategories, f.mime_type);

        const { error: upErr } = await admin.from("community_files").upsert(
          {
            card_id: cardId,
            file_id: f.id,
            owner_id: userId,
            owner_display_name: ownerName,
            card_name: card.name,
            file_name: safeName,
            categories,
            size_bytes: f.size_bytes,
            mime_type: f.mime_type,
            github_path: ghPath,
            download_url: result?.content?.download_url,
            published_at: new Date().toISOString(),
          },
          { onConflict: "card_id,file_name" }
        );
        if (upErr) { failed.push(f.name); continue; }
        published.push(f.name);
      } catch (_e) {
        failed.push(f.name);
      }
    }

    if (!published.length) return json({ error: "فشل رفع كل الملفات على GitHub" }, 500);
    return json({ ok: true, published, failed });
  } catch (ex) {
    return json({ error: (ex as Error).message || "خطأ غير متوقع" }, 500);
  }
});
