-- =====================================================================
-- Cadastro de usuarios pelo administrador, direto no banco
-- (sem limite de cadastros por hora e sem envio de e-mail)
-- Cole tudo em: Supabase -> SQL Editor -> New query -> Run
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;

-- Criar usuario (somente administrador)
-- O usuario sera obrigado a trocar a senha provisoria no primeiro acesso
create or replace function public.admin_criar_usuario(p_email text, p_senha text, p_nome text, p_perfil text)
returns uuid
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  uid uuid := gen_random_uuid();
  em  text := lower(trim(p_email));
begin
  if public.meu_perfil() <> 'admin' then raise exception 'permission denied: apenas administradores'; end if;
  if p_perfil not in ('visitante','editor','admin') then raise exception 'perfil invalido'; end if;
  if length(coalesce(p_senha, '')) < 6 then raise exception 'weak password: minimo 6 caracteres'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid email'; end if;
  if exists (select 1 from auth.users where lower(email) = em) then raise exception 'already registered'; end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change, email_change_token_new)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
          crypt(p_senha, gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('nome', p_nome, 'trocar_senha', true),
          now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text,
          jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true),
          'email', now(), now(), now());

  insert into public.perfis (id, email, nome, perfil) values (uid, em, p_nome, p_perfil)
  on conflict (id) do update set email = excluded.email, nome = excluded.nome, perfil = excluded.perfil;

  return uid;
end $$;

-- Definir nova senha provisoria para um usuario (somente administrador)
-- O usuario sera obrigado a trocar no proximo acesso
create or replace function public.admin_definir_senha(p_id uuid, p_senha text)
returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if public.meu_perfil() <> 'admin' then raise exception 'permission denied: apenas administradores'; end if;
  if length(coalesce(p_senha, '')) < 6 then raise exception 'weak password: minimo 6 caracteres'; end if;
  update auth.users
     set encrypted_password = crypt(p_senha, gen_salt('bf')),
         raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || '{"trocar_senha": true}'::jsonb,
         updated_at = now()
   where id = p_id;
end $$;

-- Apagar usuario de vez (somente administrador)
create or replace function public.admin_apagar_usuario(p_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
declare em text;
begin
  if public.meu_perfil() <> 'admin' then raise exception 'permission denied: apenas administradores'; end if;
  if p_id = auth.uid() then raise exception 'voce nao pode apagar o proprio usuario'; end if;
  select lower(email) into em from auth.users where id = p_id;
  if em = any(public.admins_fixos()) then raise exception 'administrador fixo nao pode ser apagado'; end if;
  delete from public.perfis where id = p_id;
  delete from auth.users where id = p_id;
end $$;

revoke all on function public.admin_criar_usuario(text, text, text, text) from public, anon;
revoke all on function public.admin_definir_senha(uuid, text) from public, anon;
revoke all on function public.admin_apagar_usuario(uuid) from public, anon;
grant execute on function public.admin_criar_usuario(text, text, text, text) to authenticated;
grant execute on function public.admin_definir_senha(uuid, text) to authenticated;
grant execute on function public.admin_apagar_usuario(uuid) to authenticated;
