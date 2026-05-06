# OpenMU — Mapa dos Subsistemas e Pontos de Customização

Este guia mostra **onde** ficam as coisas no código do OpenMU e **como** customizar gameplay (rates, drops, itens, mapas, eventos), tanto via Admin Panel (sem recompilar) quanto via fork + build de imagem própria.

> Refs apontam para o repositório upstream `MUnique/OpenMU` (branch `master`). Você tem o clone em `OpenMU/` ao lado deste README.

---

## 1. Visão geral dos subsistemas

O OpenMU é um monorepo .NET 10 com cada subsistema em uma `csproj` separada dentro de `src/`:

| Pasta | Papel |
|---|---|
| `Startup/` | **Entry point all-in-one**. Junta Connect/Game/Chat/Login/Friend/Guild num único processo. Tem `Program.cs`, `appsettings.json`, `Dockerfile`. |
| `ConnectServer/` | Recebe a primeira conexão do cliente (porta **44405/44406**) e devolve a lista de GameServers. |
| `GameServer/` | Engine do jogo. Carrega mapas, executa lógica, fala com Persistence. Cada **definição de GameServer** vira uma porta (**55901–55906** por padrão). |
| `GameLogic/` | Regras puras: combate, movimento, party, guilda, EXP, drop. Independente de rede e DB. Aqui mora o `IGameContext.ExperienceRate` etc. |
| `ChatServer/` | Servidor de chat global (porta **55980**). |
| `LoginServer/` | Coordena login entre múltiplos GameServers (anti-double-login). |
| `FriendServer/` / `GuildServer/` | Estado compartilhado de amigos e guildas. |
| `Persistence/` | EF Core + PostgreSQL. Aqui está o **schema** e a **massa inicial** (`Initialization/`) que popula o banco no primeiro boot. |
| `Network/` | Pacotes TCP, definidos em XML (`Network/Packets/*.xml`) e gerados via source generator. |
| `PlugIns/` | Framework de plugins (descoberta, configuração, hot-toggle pela UI). |
| `Web/` | **AdminPanel** (Blazor Server, porta **8080** → exposta pelo Coolify), API, Map viewer. |
| `Dapr/` | Variante distribuída (cada subsistema num container separado, comunica via Dapr). Marcada como *broken & unsupported*. |
| `DataModel/` | Entidades + interfaces compartilhadas entre Persistence e GameLogic. |

### Fluxo de uma sessão de jogador

```
Cliente MU
   │
   ▼  44405/tcp
ConnectServer ── retorna lista de GameServers
   │
   ▼  55901-55906/tcp
GameServer (carrega Persistence) ── valida login via LoginServer
   │
   ├── ChatServer  (55980/tcp)        ─ chat global
   ├── FriendServer / GuildServer     ─ estado social
   └── PostgreSQL                     ─ contas, personagens, itens
```

---

## 2. Customização SEM mexer no código (caminho recomendado)

A maioria das configurações de gameplay é **dado**, gravado no Postgres na primeira inicialização. Você edita pela Admin Panel e os valores ficam vivos.

### 2.1 No Admin Panel (`https://seu-dominio/`)

| O que | Onde |
|---|---|
| **Experience rate global** | Configuration → Game Configuration → `ExperienceRate` (default `1.0`) |
| **Master EXP rate** | mesma tela → `MasterExperienceRate` |
| **EXP rate por GameServer** (multiplica com a global) | Servers → [GameServer X] → `ExperienceRate` |
| **Nível máximo / Master max** | Game Configuration → `MaximumLevel` (400), `MaximumMasterLevel` (200) |
| **Drop groups (chance por monstro)** | Configuration → Drop Item Groups |
| **Loja de NPCs (preços/itens)** | Configuration → Monsters → [NPC] → Merchant Store |
| **Itens** (stats, drops, opções) | Configuration → Items |
| **Mapas** (spawn, terreno, gates) | Configuration → Maps |
| **Quests** | Configuration → Quests |
| **Plugins ativos** (Happy Hour, Invasions, periodic tasks) | Plug-Ins → ativa/desativa + Configuration |

> Tudo isso fica no Postgres — o volume `dbdata` do compose preserva entre restarts.

### 2.2 Cálculo efetivo do EXP

`Player.cs` faz a conta assim (ver `src/GameLogic/Player.cs:1189-1194`):

```
exp_ganho = exp_base
          × GameContext.ExperienceRate                 ← global × server (GameServerContext.cs:106)
          × (PlayerAttributes.ExperienceRate
             + PlayerAttributes.BonusExperienceRate)   ← seals, happy hour, etc.
```

Então se você quer um servidor "100x", basta `GameConfiguration.ExperienceRate = 100` na admin panel — sem fork.

### 2.3 Plugins úteis ja prontos

- `PeriodicTasks/HappyHourPlugIn.cs` — multiplicador extra por janela de horário.
- `PeriodicTasks/BloodCastleStartPlugIn.cs`, `ChaosCastleStartPlugIn.cs`, `DevilSquareStartPlugIn.cs` — abertura programada dos eventos.
- `InvasionEvents/` — invasões (Golden Dragon, Red Dragon, etc).
- `PlayerLosesExperienceAfterDeathPlugIn` — penalidade de morte (configurável).
- `PeriodicSaveProgressPlugIn` — autosave.

### 2.4 Chat commands (GMs)

Mais de 30 comandos em `src/GameLogic/PlugIns/ChatCommands/`:
`/addstr`, `/addagi`, `/addvit`, `/addene`, `/addcmd`, `/ban`, `/kick`, `/clearinv`, `/giveitem`, `/move`, `/post`, `/warp`, etc. Ativa/desativa cada um pela Admin Panel.

---

## 3. Customização COM código (fork + build de imagem própria)

Se quiser mudar o **default** que vai pro banco no primeiro boot (ex.: já nascer 50x), ou mudar regras de combate, fork o repo e construa sua própria imagem.

### 3.1 Onde mexer pelos defaults

| Quero mudar | Arquivo |
|---|---|
| EXP rate default | `src/Persistence/Initialization/GameConfigurationInitializerBase.cs:40` (`this.GameConfiguration.ExperienceRate = 1.0f;`) |
| Level máximo default | mesma classe, linha 42 |
| EXP rate por GameServer no seed | `src/Persistence/Initialization/DataInitializationBase.cs:253` |
| Massa inicial S6 (mapas, items, NPCs, quests) | `src/Persistence/Initialization/VersionSeasonSix/` |
| Definição de mapa específico (ex.: Lorencia spawns) | `src/Persistence/Initialization/VersionSeasonSix/Maps/Lorencia.cs` |
| Stats de classes | `src/Persistence/Initialization/CharacterClasses/CharacterClassInitialization.cs` |
| Skills | `src/Persistence/Initialization/Skills/` + `VersionSeasonSix/SkillsInitializer.cs` |
| Itens (armaduras, armas, jewels) | `src/Persistence/Initialization/VersionSeasonSix/Items/` |
| Chaos Mix (recipes) | `src/Persistence/Initialization/VersionSeasonSix/ChaosMixes.cs` |
| Mensagens/timing de events | `src/Persistence/Initialization/VersionSeasonSix/Events/` |
| Lógica de combate (dano, miss, crit) | `src/GameLogic/Player.cs`, `Attackable*.cs`, `DamageAttributes.cs` |
| Regras de drop | `src/GameLogic/DefaultDropGenerator.cs` |
| Pacotes de rede (S6 protocol) | `src/Network/Packets/*.xml` (são gerados via source generator) |

### 3.2 Build da sua imagem

O `Dockerfile` está em `src/Startup/Dockerfile`. Para buildar:

```bash
cd OpenMU
docker build -f src/Startup/Dockerfile -t meu-openmu:custom .
docker push registry.seu-dominio/meu-openmu:custom
```

Depois, no `docker-compose.yml` deste repo, troque:

```yaml
# de:
image: munique/openmu:latest
# para:
image: registry.seu-dominio/meu-openmu:custom
```

E no Coolify aponte pro registry (ele suporta registries privados nas Settings).

### 3.3 Reseed do banco depois de mudar Initialization

Se você mexeu em `Initialization/` e quer que o banco recarregue do zero:

1. Backup primeiro: `docker exec database pg_dump -U postgres openmu | gzip > antes.sql.gz`
2. Recreia o volume: `docker compose down && docker volume rm <stack>_dbdata && docker compose up -d`
3. Acesse a Admin Panel — ela detecta DB vazio e roda `DataInitialization` (`VersionSeasonSix.DataInitialization` por default, `Id = "season6"`).

> ⚠️ **Reseed apaga personagens, contas, itens.** Só faça em ambiente novo.

---

## 4. Setup distribuído (Dapr) — quando faz sentido

A pasta `src/Dapr/` separa cada subsistema em seu próprio container, comunicando via Dapr sidecars. Vantagens: scale-out de GameServers em máquinas diferentes, resiliência maior. Desvantagens:

- O upstream marca como **broken & unsupported** atualmente.
- Mais portas, mais yaml, mais Postgres tuning.
- Para < 500 jogadores concorrentes, all-in-one resolve numa VM 4 vCPU / 8 GB tranquilamente.

Recomendação: **fique no all-in-one** (que é o que este repo faz) até precisar escalar. Quando precisar, abrimos o Dapr.

---

## 5. Build local (Windows, sem Docker) para desenvolvimento

Se quiser debugar no Visual Studio:

1. Instale .NET SDK 10 e PostgreSQL.
2. Edite `src/Persistence/EntityFramework/ConnectionSettings.xml` com user/senha do seu Postgres local.
3. `dotnet build src/MUnique.OpenMU.sln`
4. `dotnet run --project src/Startup`
5. Abre `http://localhost:8080`.

Hot reload de Blazor funciona pra mexer na Admin Panel.

---

## 6. Onde abrir issue / PR

- Bugs no compose oficial (volume Postgres errado, falta de healthcheck) — ver [README.md](README.md), seção "Melhorias sugeridas pro upstream".
- Issues do core: <https://github.com/MUnique/OpenMU/issues>
- Discord do projeto: link no README do upstream.
