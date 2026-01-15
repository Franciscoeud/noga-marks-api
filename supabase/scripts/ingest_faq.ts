import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

async function ingest() {
  const text = await Deno.readTextFile(new URL("../../data/faq.md", import.meta.url));
  const chunks = text
    .split(/\n+/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"));

  const rows = chunks.map((chunk) => ({
    source: "faq.md",
    chunk,
    tags: ["faq", "aurea"],
  }));

  const { error } = await supabase.from("faq_chunks").insert(rows);
  if (error) throw error;
  console.log(`Inserted ${rows.length} FAQ chunks.`);
}

ingest().catch((err) => {
  console.error("Failed to ingest FAQ:", err);
  Deno.exit(1);
});
