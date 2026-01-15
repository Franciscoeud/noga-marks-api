// Supabase Edge Function: aurea-sales-chat
// Deno runtime

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WC_BASE_URL = Deno.env.get("WC_BASE_URL")!;
const WC_CONSUMER_KEY = Deno.env.get("WC_CONSUMER_KEY")!;
const WC_CONSUMER_SECRET = Deno.env.get("WC_CONSUMER_SECRET")!;
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY")!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ChatRequest = {
  conversationId?: string;
  visitorId?: string;
  message: string;
  locale?: string;
  consent?: boolean;
  pageContext?: Record<string, unknown>;
};

type ChatPayload = {
  reply: string;
  suggested_cta: "none" | "view_product" | "checkout" | "view_size_guide" | "contact_human";
  classification?: Record<string, unknown>;
  recommended_products?: Array<{ id: string; name: string; price: string; permalink: string; image?: string }>;
  follow_up_questions?: string[];
  conversationId?: string;
};

function validatePayload(obj: any): ChatPayload {
  const safe: ChatPayload = {
    reply: typeof obj?.reply === "string" ? obj.reply : "Gracias por tu mensaje.",
    suggested_cta: ["none", "view_product", "checkout", "view_size_guide", "contact_human"].includes(
      obj?.suggested_cta,
    )
      ? obj.suggested_cta
      : "none",
    classification: typeof obj?.classification === "object" ? obj.classification : undefined,
    recommended_products: Array.isArray(obj?.recommended_products)
      ? obj.recommended_products
          .filter((p: any) => p?.id && p?.name && p?.permalink)
          .map((p: any) => ({
            id: String(p.id),
            name: String(p.name),
            price: String(p.price ?? ""),
            permalink: String(p.permalink),
            image: p.image ? String(p.image) : undefined,
          }))
      : [],
    follow_up_questions: Array.isArray(obj?.follow_up_questions)
      ? obj.follow_up_questions.map((q: any) => String(q))
      : [],
  };
  return safe;
}

const stopWords = new Set([
  "quiero",
  "busco",
  "tienen",
  "tienes",
  "hay",
  "hola",
  "para",
  "con",
  "sin",
  "por",
  "una",
  "un",
  "el",
  "la",
  "los",
  "las",
  "de",
  "del",
  "en",
  "y",
  "o",
  "que",
  "me",
  "algo",
  "unos",
  "unas",
  "mas",
  "menos",
]);

function normalizeText(value: string) {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ");
}

function buildSearchTerm(message: string) {
  const terms = normalizeText(message)
    .split(/\s+/)
    .filter((word) => word && word.length > 2 && !stopWords.has(word));
  if (terms.length === 0) {
    return message.trim().slice(0, 40);
  }
  return terms.slice(0, 3).join(" ");
}

function buildWooProductsUrl() {
  const base = WC_BASE_URL.replace(/\/+$/, "");
  if (base.includes("/wp-json/wc/v3")) {
    return `${base}/products`;
  }
  return `${base}/wp-json/wc/v3/products`;
}

async function fetchFaqChunks(search: string, limit = 5) {
  const { data } = await supabase
    .from("faq_chunks")
    .select("id, chunk, source, tags")
    .ilike("chunk", `%${search.slice(0, 60)}%`)
    .limit(limit);
  return data ?? [];
}

async function fetchProducts(search: string) {
  const term = buildSearchTerm(search);
  const url = new URL(buildWooProductsUrl());
  url.searchParams.set("search", term);
  url.searchParams.set("per_page", "5");
  url.searchParams.set("status", "publish");
  const resp = await fetch(url.toString(), {
    headers: {
      Authorization: "Basic " + btoa(`${WC_CONSUMER_KEY}:${WC_CONSUMER_SECRET}`),
    },
  });
  if (!resp.ok) {
    console.error("WooCommerce error", resp.status, await resp.text());
    return [];
  }
  const json = await resp.json();
  return (json as any[]).map((p) => ({
    id: String(p.id),
    name: p.name,
    price: p.price_html || p.price || "",
    permalink: p.permalink,
    image: p.images?.[0]?.src,
  }));
}

async function callOpenAI(message: string, faq: any[], products: any[]): Promise<ChatPayload> {
  const system = [
    "Eres Aurea Move Sales, una especialista en athleisure.",
    "Responde en JSON valido con este esquema: { reply, suggested_cta, classification, recommended_products, follow_up_questions }.",
    "Responde en español breve y claro.",
    "Haz 1-2 preguntas de ajuste/talla cuando recomiendes.",
    "No inventes descuentos; sugiere revisar promos vigentes o suscribirse.",
  ].join(" ");

  const content = [
    { role: "system", content: system },
    {
      role: "user",
      content: `Cliente: ${message}\nFAQs:\n${faq.map((f) => "- " + f.chunk).join("\n")}\nProductos:\n${products
        .map((p) => `${p.name} | ${p.price} | ${p.permalink}`)
        .join("\n")}`,
    },
  ];

  const body = {
    model: "gpt-3.5-turbo-0125",
    messages: content,
    temperature: 0.4,
    response_format: { type: "json_object" },
  };

  const resp = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`,
    },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`OpenAI error ${resp.status}: ${errText}`);
  }
  const json = await resp.json();
  const text = json.choices?.[0]?.message?.content || "{}";
  let parsed: any;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { reply: text, suggested_cta: "none" };
  }
  return validatePayload(parsed);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }
  try {
    const body: ChatRequest = await req.json();
    if (!body.message) {
      return new Response("message is required", { status: 400, headers: corsHeaders });
    }

    let convId = body.conversationId;
    if (!convId) {
      const { data, error } = await supabase
        .from("conversations")
        .insert({
          visitor_id: body.visitorId,
          consent: !!body.consent,
          locale: body.locale || "es",
          contact: body.pageContext || {},
        })
        .select("id")
        .single();
      if (error) throw error;
      convId = data.id;
    }

    await supabase.from("messages").insert({
      conversation_id: convId,
      role: "user",
      content: body.message,
      metadata: { pageContext: body.pageContext },
    });

    const [faq, prods] = await Promise.all([fetchFaqChunks(body.message), fetchProducts(body.message)]);
    let aiResponse: ChatPayload;
    try {
      aiResponse = await callOpenAI(body.message, faq, prods);
    } catch (err) {
      console.error("OpenAI error", err);
      aiResponse = {
        reply: "Gracias por tu mensaje. Ahora mismo no puedo procesar la solicitud, ¿puedes reintentarlo?",
        suggested_cta: prods.length ? "view_product" : "contact_human",
        recommended_products: prods,
      };
    }

    if ((aiResponse.recommended_products ?? []).length === 0 && prods.length > 0) {
      aiResponse.recommended_products = prods;
      if (aiResponse.suggested_cta === "none") {
        aiResponse.suggested_cta = "view_product";
      }
    }

    await supabase.from("messages").insert({
      conversation_id: convId,
      role: "assistant",
      content: aiResponse.reply,
      metadata: {
        suggested_cta: aiResponse.suggested_cta,
        classification: aiResponse.classification,
        recommended_products: aiResponse.recommended_products,
      },
    });

    return new Response(JSON.stringify({ ...aiResponse, conversationId: convId }), {
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (err) {
    console.error(err);
    return new Response("Internal error", { status: 500, headers: corsHeaders });
  }
});
