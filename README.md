# Painel Operacional — Logística

Labor Health Supply · Uma empresa BUNZL

Painel com as abas: Resumo da Operação, Ocupação de Estoque, Acompanhamento de Insumos,
Acompanhamento de Produtividade e Curva ABC — Vendas e Devolução.

## Arquivos

- `index.html`: o painel completo, num arquivo só
- `supabase-banco.sql`: script de criação do banco (rodar uma vez no SQL Editor do Supabase)

## Publicar no GitHub Pages

1. Envie os arquivos desta pasta para o repositório (Add file → Upload files → Commit changes).
2. Vá em **Settings → Pages**.
3. Em **Branch**, escolha `main` e a pasta `/ (root)`, depois clique em **Save**.
4. Em 1 ou 2 minutos o link aparece no topo da página de Pages.

## Banco de dados

Enquanto o banco não estiver configurado, o painel abre em **modo teste**: os dados ficam salvos
só no navegador de quem está usando.

Para ligar ao Supabase, a configuração fica no começo do `index.html`, no bloco `PAINEL_CONFIG`:

```js
banco: 'supabase',
supabase: { url: 'https://xxxx.supabase.co', anonKey: 'eyJ...' },
```

## Perfis de acesso

- **Pendente**: criou o acesso e aguarda liberação
- **Visitante**: só consulta
- **Editor**: consulta e altera os dados
- **Administrador**: tudo do Editor e também libera usuários (menu "Usuários")
- **Bloqueado**: sem acesso

O e-mail `operacional@laborhs.com.br` entra como Administrador automaticamente.
