-- Chat schema for Aurea Move Sales Chat
create extension if not exists "uuid-ossp";

create table if not exists public.conversations (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default timezone('utc', now()),
  visitor_id text,
  consent boolean default false,
  contact jsonb,
  locale text
);

create table if not exists public.messages (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid references public.conversations(id) on delete cascade,
  role text not null check (role in ('user','assistant','system')),
  content text not null,
  created_at timestamptz not null default timezone('utc', now()),
  metadata jsonb
);

create index if not exists idx_messages_conversation on public.messages(conversation_id, created_at);

create table if not exists public.events (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid references public.conversations(id) on delete cascade,
  type text not null,
  payload jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

-- FAQ chunks (embeddings optional for phase 2)
create table if not exists public.faq_chunks (
  id uuid primary key default uuid_generate_v4(),
  source text,
  chunk text not null,
  embedding vector(1536),
  tags text[],
  created_at timestamptz not null default timezone('utc', now())
);

-- Optional mirror of WooCommerce products (not used by function in MVP)
create table if not exists public.products (
  id text primary key,
  name text,
  description text,
  price numeric(12,2),
  currency text,
  permalink text,
  images jsonb,
  categories text[],
  stock_status text,
  updated_at timestamptz default timezone('utc', now())
);
