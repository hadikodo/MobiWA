// Decides whether a WhatsApp chat is from a customer and which category fits.
// The Gemini key is read from the GEMINI_API_KEY secret; it never reaches the app.
//
// POST { phone, messages: [{text, fromCustomer, time}], categories: [{name, description}], business }
// → { is_customer, category, category_description, name, reason }
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

const GEMINI = "https://generativelanguage.googleapis.com/v1beta";
let cachedModel: string | null = null;

type Msg = { text: string; fromCustomer: boolean; time?: string };
type Cat = { name: string; description?: string };

async function pickModel(key: string): Promise<string> {
  if (cachedModel) return cachedModel;
  const override = Deno.env.get("GEMINI_MODEL");
  if (override) return (cachedModel = override);
  const res = await fetch(`${GEMINI}/models?pageSize=200`, { headers: { "x-goog-api-key": key } });
  const body = await res.json();
  if (!res.ok) throw new Error(body?.error?.message ?? `Gemini error ${res.status}`);
  const stable = /^gemini-(\d+(?:\.\d+)?)-flash$/;
  const names: string[] = (body.models ?? [])
    .filter((m: any) => (m.supportedGenerationMethods ?? []).includes("generateContent"))
    .map((m: any) => String(m.name).replace("models/", ""));
  const best = names
    .filter((n) => stable.test(n))
    .sort((a, b) => parseFloat(b.match(stable)![1]) - parseFloat(a.match(stable)![1]))[0];
  cachedModel = best ?? names.find((n) => n.includes("flash")) ?? "gemini-2.5-flash";
  return cachedModel;
}

function buildPrompt(phone: string, messages: Msg[], categories: Cat[], business: string): string {
  const transcript = messages
    .slice(-80)
    .map((m) => `${m.fromCustomer ? "THEM" : "ME"}${m.time ? ` [${m.time}]` : ""}: ${String(m.text).slice(0, 1000)}`)
    .join("\n");
  const cats = categories.length
    ? categories.map((c) => `- ${c.name}${c.description ? `: ${c.description}` : ""}`).join("\n")
    : "(none yet)";
  return `You sort WhatsApp chats for a business. "ME" is the business, "THEM" is the other person.
${business ? `About the business: ${business}\n` : ""}
Decide if THEM is a CUSTOMER: a person who bought, ordered, asked about a product/service,
asked for a price, availability, delivery, or support for something the business sells.
NOT a customer: spam, ads, wrong number, friends/family chat, suppliers selling to us,
job seekers, bots, scams, empty greetings with no request, or unrelated conversations.

If CUSTOMER, choose ONE category describing what they requested.
- Reuse an existing category whenever it fits (return its exact name).
- Otherwise create a new one: 1-3 words, Title Case, in English, about the product/service
  (e.g. "iPhone Repair", "Car Parts", "Wedding Cakes"). Never "Customers", "Leads", "Other".
Existing customer categories:
${cats}

Chat with ${phone}:
${transcript}

Reply with JSON only:
{"is_customer": true|false, "category": "name or empty", "category_description": "one short line about what this category covers", "name": "their name if they said it, else empty", "reason": "max 12 words why"}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // Only signed-in, active users may use the AI.
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: {
      headers: {
        Authorization: req.headers.get("Authorization") ?? "",
        "x-device-token": req.headers.get("x-device-token") ?? "",
      },
    },
  });
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: { user } } = await supabase.auth.getUser(token);
  if (!user) return json({ error: "Please sign in again." }, 401);
  const { data: profile } = await supabase.from("profiles").select("active").eq("id", user.id).single();
  if (!profile?.active) return json({ error: "Your account is disabled." }, 403);
  // One account = one device: only the bound device may use the AI.
  const { data: deviceOk } = await supabase.rpc("device_ok");
  if (deviceOk !== true) return json({ error: "This account is signed in on another device." }, 401);
  // Per-user quota (protects the AI bill if an account is misused).
  const { data: quotaOk } = await supabase.rpc("ai_quota_take");
  if (quotaOk !== true) return json({ error: "AI limit reached for now. Please try again later." }, 429);

  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) return json({ error: "AI is not configured on the server (GEMINI_API_KEY secret missing)." }, 500);

  let input: { phone?: string; messages?: Msg[]; categories?: Cat[]; business?: string };
  try {
    input = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  const messages = Array.isArray(input.messages) ? input.messages : [];
  if (!messages.length) return json({ error: "No messages" }, 400);

  try {
    const model = await pickModel(key);
    const prompt = buildPrompt(
      String(input.phone ?? ""),
      messages,
      Array.isArray(input.categories) ? input.categories.slice(0, 200) : [],
      String(input.business ?? "").slice(0, 1000),
    );
    const res = await fetch(`${GEMINI}/models/${model}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.1, responseMimeType: "application/json" },
      }),
    });
    const body = await res.json();
    if (!res.ok) {
      // Pass rate limits through so the app can wait and retry.
      return json({ error: body?.error?.message ?? `Gemini error ${res.status}` }, res.status === 429 ? 429 : 502);
    }
    const text: string = (body.candidates?.[0]?.content?.parts ?? []).map((p: any) => p.text ?? "").join("");
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start < 0 || end <= start) return json({ error: "AI gave no answer" }, 502);
    const m = JSON.parse(text.slice(start, end + 1));
    const category = String(m.category ?? "").trim().slice(0, 40);
    const isCustomer = (m.is_customer === true || String(m.is_customer).toLowerCase() === "true") && !!category;
    return json({
      is_customer: isCustomer,
      category: isCustomer ? category : "",
      category_description: String(m.category_description ?? "").trim(),
      name: String(m.name ?? "").trim(),
      reason: String(m.reason ?? "").trim(),
      model,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 502);
  }
});
