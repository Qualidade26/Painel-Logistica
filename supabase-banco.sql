-- =====================================================================
-- Banco do Painel Operacional da Logistica  Supabase
-- Cole tudo em: Supabase  SQL Editor  New query  Run
-- =====================================================================

-- Dados dos paineis (um registro por documento)
create table if not exists public.docs (
  path        text primary key,
  col         text not null,
  data        jsonb not null,
  updated_at  timestamptz not null default now()
);
create index if not exists docs_col_idx on public.docs (col);

-- Cadastro de usuarios (perfis)
create table if not exists public.perfis (
  id         uuid primary key references auth.users on delete cascade,
  nome       text,
  email      text,
  perfil     text not null default 'pendente'
             check (perfil in ('pendente','visitante','editor','admin','bloqueado')),
  criado_em  timestamptz not null default now()
);
-- Se a tabela "perfis" ja existia com outro formato, completa as colunas que faltam
alter table public.perfis add column if not exists nome      text;
alter table public.perfis add column if not exists email     text;
alter table public.perfis add column if not exists perfil    text not null default 'pendente';
alter table public.perfis add column if not exists criado_em timestamptz not null default now();

-- Travas curtas (evita duas baixas no mesmo item ao mesmo tempo)
create table if not exists public.travas (
  path    text primary key,
  holder  text not null,
  expira  timestamptz not null
);

-- E-mails que ja entram como Administrador (mesma lista do index.html)
create or replace function public.admins_fixos() returns text[]
language sql immutable as $$ select array['operacional@laborhs.com.br'] $$;

-- Perfil de quem esta logado
create or replace function public.meu_perfil() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select 'admin' from auth.users u where u.id = auth.uid() and lower(u.email) = any(public.admins_fixos())),
    (select perfil from public.perfis where id = auth.uid()),
    'nenhum')
$$;

-- Cria o perfil automaticamente quando alguem cria o acesso
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfis (id, email, nome, perfil)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'nome', ''),
          case when lower(new.email) = any(public.admins_fixos()) then 'admin' else 'pendente' end)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.novo_usuario();

-- Atualizacao parcial de um documento (mantem os outros campos)
create or replace function public.doc_merge(p text, d jsonb) returns void
language plpgsql security invoker as $$
begin
  update public.docs set data = data || d, updated_at = now() where path = p;
  if not found then raise exception 'not_found: %', p; end if;
end $$;

-- Trava curta por documento
create or replace function public.doc_acquire(p text, holder text, ttl_ms int) returns boolean
language plpgsql security invoker as $$
declare ok boolean;
begin
  insert into public.travas as t (path, holder, expira)
  values (p, holder, now() + make_interval(secs => ttl_ms / 1000.0))
  on conflict (path) do update
    set holder = excluded.holder, expira = excluded.expira
    where t.expira < now() or t.holder = excluded.holder
  returning true into ok;
  return coalesce(ok, false);
end $$;

-- Seguranca (quem pode ler e gravar)
alter table public.docs   enable row level security;
alter table public.perfis enable row level security;
alter table public.travas enable row level security;

drop policy if exists docs_ler on public.docs;
drop policy if exists docs_inserir on public.docs;
drop policy if exists docs_alterar on public.docs;
drop policy if exists docs_apagar on public.docs;
create policy docs_ler     on public.docs for select using (public.meu_perfil() in ('visitante','editor','admin'));
create policy docs_inserir on public.docs for insert with check (public.meu_perfil() in ('editor','admin'));
create policy docs_alterar on public.docs for update using (public.meu_perfil() in ('editor','admin')) with check (public.meu_perfil() in ('editor','admin'));
create policy docs_apagar  on public.docs for delete using (public.meu_perfil() in ('editor','admin'));

drop policy if exists perfis_ler on public.perfis;
drop policy if exists perfis_alterar on public.perfis;
drop policy if exists perfis_apagar on public.perfis;
create policy perfis_ler     on public.perfis for select using (id = auth.uid() or public.meu_perfil() = 'admin');
create policy perfis_alterar on public.perfis for update using (public.meu_perfil() = 'admin') with check (public.meu_perfil() = 'admin');
create policy perfis_apagar  on public.perfis for delete using (public.meu_perfil() = 'admin');

drop policy if exists travas_tudo on public.travas;
create policy travas_tudo on public.travas for all
  using (public.meu_perfil() in ('editor','admin')) with check (public.meu_perfil() in ('editor','admin'));

-- Atualizacao em tempo real
alter table public.docs replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; end $$;
