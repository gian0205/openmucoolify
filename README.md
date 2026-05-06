# OpenMU no Coolify — Guia de Deploy

Stack pronta para subir o servidor [OpenMU](https://github.com/MUnique/OpenMU) (MU Online S6E3) num Coolify self-hosted, com correções dos problemas conhecidos do `docker-compose` oficial.

## O que esta stack faz

- **Painel admin** (Blazor) exposto em HTTPS via Traefik do Coolify, com Let's Encrypt automático.
- **Portas TCP de jogo** (Connect, Game, Chat) publicadas direto no host, como o cliente do MU exige.
- **PostgreSQL 16** com volume persistente, healthcheck e senha gerada pelo Coolify.
- **Página pública de cadastro** (Node + design dark fantasy "MU Porcaria") em outro subdomínio, plugada direto no Postgres do OpenMU. Veja [register-site/](register-site/).
- Sem nginx + `.htpasswd` à parte — basic auth (se quiser) é configurada na própria UI do Coolify.

## Correções vs. compose oficial

| Item | Oficial | Aqui |
|---|---|---|
| Volume Postgres | `/var/lib/postgresql` (não persiste!) | `/var/lib/postgresql/data` |
| Senha Postgres | `admin` hardcoded | `${SERVICE_PASSWORD_POSTGRES}` (gerada) |
| Tag `postgres` | sem tag | `postgres:16-alpine` |
| Restart policy | nenhuma | `unless-stopped` |
| Healthcheck DB | nenhum | `pg_isready` + `depends_on: condition: service_healthy` |
| Reverse proxy | nginx + .htpasswd próprio | Traefik nativo do Coolify |
| Porta 5432 | publicada | só na rede interna |

## Passo a passo no Coolify

### 1. Pré-requisitos
- Coolify v4 instalado e funcionando.
- Um domínio (ex.: `admin.seuservidor.com`) com DNS apontando pro IP do Coolify.
- Portas TCP **44405, 44406, 55901–55906, 55980** abertas no firewall do servidor (UFW, security group da cloud, etc).

### 2. Criar o recurso
1. No projeto do Coolify, **+ New Resource → Docker Compose Empty**.
2. Cole o conteúdo de [`docker-compose.yaml`](./docker-compose.yaml).
3. Salve.

### 3. Configurar os domínios
Você precisa de **dois subdomínios** apontando pro IP do Coolify:

- Em **Environment Variables** o Coolify mostra duas vars:
  - `SERVICE_FQDN_OPENMU_8080` → painel admin. Ex.: `https://admin.seuservidor.com`
  - `SERVICE_FQDN_REGISTER_3000` → página de cadastro. Ex.: `https://cadastro.seuservidor.com`
- Coolify cuida dos certificados Let's Encrypt sozinho.

### 4. Senhas
- `SERVICE_PASSWORD_POSTGRES` é gerada automaticamente. Não precisa mexer.
- Se quiser proteger o painel admin com basic auth extra, use **Settings → Basic Auth** do recurso no Coolify (mais simples que o `.htpasswd` do compose oficial).

### 5. Firewall — abrir as portas TCP de jogo
Sem isso o cliente do MU não conecta. Exemplo no Ubuntu com UFW:

```bash
sudo ufw allow 44405:44406/tcp
sudo ufw allow 55901:55906/tcp
sudo ufw allow 55980/tcp
sudo ufw reload
```

Em cloud (AWS/GCP/Hetzner), libere o mesmo range no security group / firewall do provedor.

### 6. Deploy
- Clique em **Deploy**.
- Acompanhe os logs. O `openmu-startup` cria o schema do banco e roles automaticamente no primeiro boot (pode levar 1–3 min).

### 7. Acesso ao admin
- Abra `https://admin.seuservidor.com`.
- Em **Configuration → System** ative **Auto Start** se quiser que os GameServers subam sozinhos no próximo restart.
- Em **Setup**, ajuste o **IP resolver** pra que o servidor anuncie o IP público correto pros clientes (senão dá disconnect ao trocar de mapa).

### 8. Contas de teste
Já vêm criadas: `test0`–`test9` (níveis 1–90), `test300`, `testgm`. Senha = nome do usuário.

### 9. Cadastro público de jogadores

Acesse `https://cadastro.seuservidor.com` (o que você definiu em `SERVICE_FQDN_REGISTER_3000`). Quem entrar consegue criar conta sozinho — o backend Node valida, gera hash BCrypt compatível com o `.NET BCrypt.Net` que o OpenMU usa, e dá `INSERT` direto em `data."Account"`.

Restrições já aplicadas:
- Login: 4–10 caracteres `[A-Za-z0-9_]` (limite de `varchar(10)` do schema do OpenMU).
- Senha: 8–64 caracteres, hashed com BCrypt cost 11.
- Rate limit: **3 cadastros por IP a cada 10 minutos** (configurável via `RATE_MAX` / `RATE_WINDOW_MS`).
- `SecurityCode` é gerado aleatório (4 dígitos) — o jogador pode trocar depois pelo painel admin.

Antes de abrir pro público vale colocar **captcha** (Cloudflare Turnstile, hCaptcha) e ativar o **basic auth do Coolify** num staging. Detalhes do mini-serviço em [register-site/](register-site/).

## Conectando o cliente

- Patch o cliente Season 6 Episode 3 pra apontar pro **Connect Server** em `seuservidor.com:44405` (cliente original) ou `:44406` (open source).
- O Connect Server retorna a lista de GameServers (55901–55906) que o cliente conecta em seguida.

## Troubleshooting

**Painel abre mas dá erro de banco**
Veja os logs do `database`. Garanta que o healthcheck passou antes do `openmu` subir (já configurado aqui via `depends_on.condition: service_healthy`).

**Cliente conecta no Connect Server mas trava ao escolher servidor**
IP resolver errado. Em **Setup → IP Resolver**, troque pra "Custom" e coloque o IP/domínio público.

**Quero múltiplos servidores ou Dapr distribuído**
A pasta `deploy/distributed/` do repo upstream existe mas está marcada como *broken & unsupported*. Pra começar, fique no all-in-one — aguenta tranquilo algumas centenas de jogadores numa VM decente.

**Backup do banco**
```bash
docker exec database pg_dump -U postgres openmu | gzip > openmu-$(date +%F).sql.gz
```
Configure no Coolify em **Scheduled Backups** se quiser automatizar (Coolify v4+ suporta backup nativo de Postgres).

## Melhorias sugeridas pro upstream

Vale abrir PR no [MUnique/OpenMU](https://github.com/MUnique/OpenMU) com:

1. **Bug do volume Postgres** — `deploy/all-in-one/docker-compose.yml` perde dados em todo `docker compose down -v` ou recreate da imagem. Trocar pra `/var/lib/postgresql/data`.
2. **Pinning de versão** — `postgres` sem tag pega `latest`, que pode trazer major version e quebrar compat (ex.: 17 mudou wal config). Pinar `postgres:16-alpine`.
3. **Healthcheck + `depends_on.condition`** — evita race condition no primeiro boot.
4. **Default password** — substituir `admin` por aviso explícito ou geração via script.
5. **Documentar deploy em PaaS** — Coolify, Dokploy, CapRover são alvos comuns. Um exemplo `docker-compose.coolify.yml` ajuda muito.
