# Register Site — MU Porcaria

Página pública de cadastro de jogadores pro servidor OpenMU. Visual baseado num design dark fantasy / medieval (pedra, ouro, embers) com tom PT-BR brincalhão.

## Stack

- **Frontend**: HTML/CSS/JS puro (sem framework, sem build). Cinzel + Inter + JetBrains Mono via Google Fonts.
- **Backend**: Node 20 + Express + bcryptjs + pg.
- **DB**: Postgres do próprio OpenMU (mesmo container `database` do compose).
- **Imagem**: `node:20-alpine` multi-stage, roda como user não-root, ~120 MB.

## Endpoints

| Método | Rota | O que faz |
|---|---|---|
| `GET` | `/` | Página de cadastro |
| `GET` | `/health` | `200` se Postgres responde, `503` senão |
| `GET` | `/api/stats` | `{ accountsCreated, status }` — usado pelo painel "Status do Reino" |
| `POST` | `/api/register` | `{ user, email, password }` → cria conta. Rate-limited. |

## Variáveis de ambiente

| Var | Default | Descrição |
|---|---|---|
| `PORT` | `3000` | Porta HTTP |
| `PGHOST` | `database` | Host do Postgres |
| `PGPORT` | `5432` | Porta |
| `PGDATABASE` | `openmu` | Database |
| `PGUSER` | `postgres` | User |
| `PGPASSWORD` | — | **Obrigatório** |
| `BCRYPT_ROUNDS` | `11` | Workfactor BCrypt (mesmo default do `BCrypt.Net-Next`) |
| `RATE_WINDOW_MS` | `600000` | Janela de rate limit (10 min) |
| `RATE_MAX` | `3` | Máximo de cadastros por IP por janela |
| `TRUST_PROXY` | `true` | `true` quando atrás de Traefik/Coolify (pra o IP real chegar no rate limit) |

## Compatibilidade BCrypt com OpenMU

O OpenMU verifica senhas em `AccountRepository.cs:125` com `BCrypt.Verify(password, hash)` da lib `BCrypt.Net-Next`. Hashes gerados pelo `bcryptjs` com prefixo `$2a$` são interoperáveis — testado a múltiplas rodadas.

Se quiser trocar pra `argon2`/`scrypt`, **não vai funcionar**: o OpenMU só conhece BCrypt.

## Schema da tabela

A inserção bate exatamente com `data."Account"` (ver `OpenMU/src/Persistence/EntityFramework/Migrations/00000000000000_Initial.cs:487`):

```sql
INSERT INTO data."Account" (
  "Id",                  -- uuid PK (gen_random_uuid)
  "LoginName",           -- varchar(10) NOT NULL
  "PasswordHash",        -- text NOT NULL (bcrypt $2a$11$...)
  "SecurityCode",        -- text NOT NULL (4 dígitos aleatórios)
  "EMail",               -- text NOT NULL
  "RegistrationDate",    -- timestamptz NOT NULL (now())
  "State",               -- int NOT NULL (0 = Normal)
  "TimeZone",            -- smallint NOT NULL (0)
  "VaultPassword",       -- text NOT NULL ('')
  "IsVaultExtended"      -- bool NOT NULL (false)
) VALUES (...);
```

`UnlockedCharacterClasses`, `Vault` e demais relacionamentos ficam em branco — o OpenMU lida com eles no primeiro login do jogador.

## Rodar local

```bash
cd register-site
npm install
PGPASSWORD=admin PGHOST=localhost npm start
# abre http://localhost:3000
```

(Precisa de um Postgres rodando com o schema do OpenMU já criado.)

## Próximos passos sugeridos

- **Captcha**: Cloudflare Turnstile (gratuito, sem cookie). Adicionar widget no form e chamada de verificação no `/api/register`.
- **Confirmação por e-mail**: hoje qualquer e-mail vale. Pra exigir confirmação, adicionar uma flag `email_verified` (custom em outra tabela ou via campo extra) e fluxo de magic link.
- **Captcha de proof-of-work**: alternativa leve ao Turnstile pra evitar bot básico sem CAPTCHA visível.
- **Cookie banner / LGPD**: se for público brasileiro, vale.
