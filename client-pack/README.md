# Client Pack

Helpers que entram no zip do client gerado pela CI [`build-mumain-client.yml`](../.github/workflows/build-mumain-client.yml).

## Conteúdo

| Arquivo | Vai pro zip como | Pra quê |
|---|---|---|
| `play.bat` | `play.bat` | Launcher Windows que chama `main.exe connect /uSERVER /pPORT` |
| `README.player.txt` | `LEIA-ME.txt` | Instruções pro jogador final (PT-BR) |

## Como rodar a CI

### Caminho A — manual (recomendado pra primeira vez)

1. Vai em **Actions** no GitHub do `gian0205/openmucoolify`.
2. Seleciona **Build MuMain Client** na lateral.
3. **Run workflow** → preenche:
   - `mumain_ref`: deixa `main` ou pinha um commit específico (ex.: `abc1234`)
   - `create_release`: marca se quiser que vire uma GitHub Release
4. Roda. Demora uns 15–25 min na primeira vez (build C++ no Windows runner).
5. Quando terminar, baixa o `mumain-client.zip` da aba **Artifacts** do run.

### Caminho B — por tag (pro lançamento "oficial")

```bash
git tag client-v0.1
git push origin client-v0.1
```

A CI dispara, builda, e cria automaticamente uma **GitHub Release** com o zip anexado.

## O que o player recebe

Estrutura do zip:

```
MuPorcaria-Client-<sha>.zip
├── main.exe              ← MuMain compilado
├── *.dll                 ← libs do MuMain
├── play.bat              ← com placeholder seu-dominio.com
└── LEIA-ME.txt           ← instruções
```

**O player precisa, separado:**
- Os assets originais do MU S6 EP3 1.04D English (`Data/`, `Music/`, `Sound/`, `Object/`, `Player/`, `Lang/` etc).

Ele extrai esse zip POR CIMA dessas pastas → roda `play.bat`.

---

## Cliente FULL (com assets) — `build-pack.ps1`

Quando você quer entregar **um zip único** que o player só extrai e roda — sem ter que ir caçar assets — usa o script PowerShell [`build-pack.ps1`](./build-pack.ps1). Ele junta:

```
assets do MU (que VOCÊ tem)  +  binários MuMain  +  play.bat  +  LEIA-ME.txt
                          ↓
              MuPorcaria-Client-vX.zip (1.5–2 GB)
```

### Requisitos

- **Windows + PowerShell 5+** (ou PowerShell 7).
- **Pasta com os assets do MU S6 EP3 1.04D English** num diretório local. Você é responsável por obtê-los — eles são copyright Webzen.
- *(Recomendado)* **gh CLI logado** (`gh auth login`) — o script baixa o MuMain mais recente sozinho. Se não tiver, passa `-MuMainPath` manualmente.
- *(Opcional)* **7-Zip no PATH** — torna a compactação ~10x mais rápida que o `Compress-Archive` nativo.

### Fluxo recomendado (Caminho 2 — só MuMain, sem binários da Webzen)

```powershell
# 0) Dropa só a pasta Data\ (e Music\, Sound\... se for layout antigo) do
#    teu install do MU S6 EP3 dentro de  client-pack\ . NÃO precisa
#    copiar Main.exe, Mu.exe, *.dll — o MuMain substitui isso.

# 1) Limpa binários proprietários se sobraram (HShield, launcher Webzen,
#    DLLs de runtime antigas). Dry-run primeiro:
.\client-pack\purge-webzen.ps1
# Se tudo bateu, apaga de fato:
.\client-pack\purge-webzen.ps1 -Confirm

# 2) Garante que existe pelo menos uma Release do MuMain no GitHub:
#    https://github.com/gian0205/openmucoolify/actions
#    → Build MuMain Client → Run workflow → marca create_release.
#    (espera ~20 min na primeira vez)

# 3) Monta o pack — o script baixa o MuMain sozinho via gh CLI:
.\client-pack\build-pack.ps1 `
    -ServerHost "mu.seudominio.com" `
    -Version    "1.0"

# Saída: .\dist\MuPorcaria-Client-v1.0.zip
```

`-AssetsPath` defaulta pra **a própria pasta `client-pack/`** (lê `$PSScriptRoot`). Se você preferir manter os assets fora do repo, passa explícito:

```powershell
.\client-pack\build-pack.ps1 `
    -AssetsPath "D:\Games\MU-S6EP3" `
    -MuMainPath ".\mumain-bin\unpacked" `
    -ServerHost "mu.seudominio.com" `
    -Version    "1.0"
```

> O script **ignora os helpers** (`build-pack.ps1`, `purge-webzen.ps1`, `play.bat`, `README*.*`) ao copiar pra staging via robocopy `/XF`. Ou seja, é seguro usar `client-pack/` como assets path mesmo com os helpers convivendo lá.

### O que o script faz

1. **Valida** que `AssetsPath` parece um install de MU (procura por `Data/`, `Object/` ou `Player/`).
2. **Copia tudo via robocopy** pra uma pasta de staging.
3. **Remove lixo da Webzen** que o MuMain não usa: `GameGuard/`, `*.des`, `OnePunch.dll`, `CSAuth*.dll`, `Patcher.exe`, `Launcher.exe`, `Update*.exe`, `Settings.ini`, `version.dat`, screenshots/replays do install antigo, logs.
4. **Sobrescreve binários** com os do MuMain (`main.exe` + DLLs).
5. **Gera `play.bat`** com `SERVER=mu.seudominio.com PORT=44406` já preenchidos (CRLF, sem BOM — exigência do `cmd.exe`).
6. **Substitui placeholder no `LEIA-ME.txt`** pelo teu domínio.
7. **Compacta** com 7-Zip (se tiver) ou `Compress-Archive`.
8. **Imprime** path, tamanho, SHA-256.

### Hospedagem do zip pronto

Pra colocar disponível pra download dos players:

| Onde | Bom pra | Custo |
|---|---|---|
| **Cloudflare R2** + bucket público | tráfego alto, links permanentes | $0.015/GB armazenado, **egress de graça** |
| **Backblaze B2** | mesma coisa, alternativa | $0.006/GB armazenado, $0.01/GB egress |
| **MEGA / Mediafire / Drive** | começo rápido, sem cartão | grátis até X GB, links às vezes morrem |
| **Discord (canal #downloads)** | mais simples impossível | grátis, mas Discord limita tamanho de upload (25 MB free, 500 MB nitro) — não serve pra 2 GB |
| **Coolify** mesmo (volume) | já tá ali | sem CDN, vai consumir banda do VPS |

**Recomendação:** Cloudflare R2. ~$0.03/mês pra 2 GB, sem custo de download. Liga ao DNS `download.seudominio.com` e linka na página de cadastro.

---

## Pré-edição do play.bat antes de distribuir

Se quiser poupar o player de editar o `.bat`, edita você mesmo o `play.bat` deste diretório antes de rodar a CI:

```diff
-SET SERVER=seu-dominio.com
+SET SERVER=mu.porcaria.gg
```

Commit, push, dispara CI de novo. O zip já sai com o IP correto.

## Quando o build quebrar

MuMain está em desenvolvimento ativo — `main` pode não compilar num dado dia. O que fazer:

1. **Pinha um commit conhecido** que funciona: dispara o workflow passando `mumain_ref=<sha>`.
2. **Olha os logs do step "Build (Release)"** — geralmente é dependência faltando ou erro de C++ recém-introduzido.
3. **Reporta upstream**: <https://github.com/sven-n/MuMain/issues>

## Custos

- Repos públicos no GitHub: Actions Windows são **grátis** (com limite mensal generoso).
- Repo privado: Windows runner gasta minutos **2x mais rápido** que Linux (1 min real = 2 min de quota).
