# build-pack.ps1
#
# Monta o client final do MU Porcaria juntando:
#   - Assets do MU S6 EP3 1.04D English (que você tem localmente)
#   - Binários do MuMain (compilados pela CI ou local)
#   - play.bat com o IP do teu servidor já preenchido
#   - LEIA-ME.txt pro player
#
# Uso típico:
#
#   # 1) baixa o build mais recente do MuMain (precisa do gh CLI logado)
#   gh release download --repo gian0205/openmucoolify -p "MuPorcaria-Client-*.zip" -D .\mumain-bin
#   Expand-Archive .\mumain-bin\*.zip -DestinationPath .\mumain-bin\unpacked
#
#   # 2) monta o pack
#   .\client-pack\build-pack.ps1 `
#       -AssetsPath  "D:\Games\MU-S6EP3" `
#       -MuMainPath  ".\mumain-bin\unpacked" `
#       -ServerHost  "mu.seudominio.com" `
#       -Version     "1.0"
#
# Saída:  .\dist\MuPorcaria-Client-v1.0.zip

[CmdletBinding()]
param(
    # Pasta com os assets do MU original (Data/, Music/, Sound/, etc.)
    # Default: a própria pasta deste script (client-pack/) — útil quando
    # você dropa o Data/ dentro de client-pack/ depois de rodar
    # purge-webzen.ps1.
    [string]$AssetsPath = $PSScriptRoot,

    # Pasta com main.exe + dlls do MuMain (output do CI ou build local).
    # Se omitido, usa o gh CLI pra baixar a Release mais recente do repo
    # gian0205/openmucoolify automaticamente.
    [string]$MuMainPath,

    # Domínio (ou IP) do teu ConnectServer
    [Parameter(Mandatory)] [string]$ServerHost,

    # Versão pra tag do zip
    [string]$Version = (Get-Date -Format "yyyyMMdd"),

    # Porta do ConnectServer (44406 = MuMain default no OpenMU)
    [int]$Port = 44406,

    # Onde cuspir o zip
    [string]$OutputDir = (Join-Path $PWD "dist"),

    # Nome base do pacote
    [string]$PackName = "MuPorcaria-Client",

    # Mantém a pasta de staging depois de gerar o zip (útil pra debug)
    [switch]$KeepStaging
)

$ErrorActionPreference = "Stop"

function Step($msg)  { Write-Host "── $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "   ✓ $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "   ! $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "   ✗ $msg" -ForegroundColor Red; exit 1 }

# ── Validações ─────────────────────────────────────────────────────────
Step "Validando entradas"

if (-not (Test-Path $AssetsPath -PathType Container)) {
    Fail "AssetsPath '$AssetsPath' não existe ou não é uma pasta."
}

$expectedAssetDirs = @("Data", "Object", "Player")  # tem que ter pelo menos um
$foundAny = $false
foreach ($d in $expectedAssetDirs) {
    if (Test-Path (Join-Path $AssetsPath $d)) { $foundAny = $true; break }
}
if (-not $foundAny) {
    Warn "AssetsPath não tem Data/, Object/ ou Player/ no nível raiz."
    Warn "Confere se você apontou pra raiz do MU (não pra um zip ou subpasta)."
    $resp = Read-Host "Continuar mesmo assim? (s/N)"
    if ($resp -ne "s") { exit 1 }
}

# Auto-download do MuMain via gh CLI quando -MuMainPath foi omitido
if (-not $MuMainPath) {
    Step "MuMainPath não informado — baixando Release mais recente via gh CLI"
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Fail "gh CLI não encontrado. Instale (https://cli.github.com) ou passe -MuMainPath manualmente."
    }
    $dlDir = Join-Path $OutputDir "mumain-bin"
    if (-not (Test-Path $dlDir)) { New-Item -ItemType Directory -Path $dlDir -Force | Out-Null }
    & gh release download --repo gian0205/openmucoolify --pattern "MuPorcaria-Client-*.zip" --dir $dlDir --clobber
    if ($LASTEXITCODE -ne 0) {
        Fail "Falhou ao baixar MuMain. Garanta que existe pelo menos uma Release no repo gian0205/openmucoolify (dispara a CI manualmente em Actions → Build MuMain Client)."
    }
    $zip = Get-ChildItem $dlDir -Filter "MuPorcaria-Client-*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $unpack = Join-Path $dlDir "unpacked"
    if (Test-Path $unpack) { Remove-Item $unpack -Recurse -Force }
    Expand-Archive -Path $zip.FullName -DestinationPath $unpack -Force
    $MuMainPath = $unpack
    Ok "MuMain baixado e descompactado em $MuMainPath"
}

if (-not (Test-Path $MuMainPath -PathType Container)) {
    Fail "MuMainPath '$MuMainPath' não existe ou não é uma pasta."
}

$mumainBins = Get-ChildItem $MuMainPath -Filter "main.exe" -Recurse -ErrorAction SilentlyContinue
if (-not $mumainBins) {
    Fail "Não achei main.exe em '$MuMainPath'. Confere se descompactou o zip do MuMain certo."
}
$mumainRoot = $mumainBins[0].DirectoryName
Ok "MuMain root: $mumainRoot"

# ── Staging ────────────────────────────────────────────────────────────
$stage = Join-Path $OutputDir "staging\$PackName-v$Version"
if (Test-Path $stage) {
    Step "Limpando staging anterior"
    Remove-Item $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Ok "Staging em: $stage"

# ── Copia assets ───────────────────────────────────────────────────────
Step "Copiando assets do MU (pode demorar 30s–2min, dependendo do tamanho)"
# Usa robocopy: rápido, com progresso. /XJ ignora junctions, /R:0 não
# retenta erro, /NFL/NDL/NP/NJH = log limpo.
# /XF e /XD excluem os helpers DESTE script — assim você pode usar
# client-pack/ tanto como pasta de helpers quanto como AssetsPath sem
# o script copiar a si mesmo pro pacote.
$rcArgs = @(
    "`"$AssetsPath`"", "`"$stage`"",
    "/E", "/XJ", "/R:0", "/W:0",
    "/NFL", "/NDL", "/NP", "/NJH",
    "/XF", "build-pack.ps1", "purge-webzen.ps1", "play.bat",
           "README.md", "README.player.txt", ".gitkeep",
    "/XD", "dist", "mumain-bin", "staging", ".git"
)
$rcOut = & robocopy @rcArgs
# robocopy retorna 0–7 como sucesso, 8+ erro
if ($LASTEXITCODE -ge 8) {
    Fail "robocopy falhou com código $LASTEXITCODE"
}
$assetSize = (Get-ChildItem $stage -Recurse -File | Measure-Object Length -Sum).Sum
Ok ("Assets copiados: {0:N0} arquivos, {1:N1} GB" -f `
    (Get-ChildItem $stage -Recurse -File).Count, ($assetSize/1GB))

# ── Limpa lixo do client Webzen ────────────────────────────────────────
Step "Removendo arquivos da Webzen que o MuMain não usa"

# Pastas/arquivos conhecidos do launcher e anti-cheat oficial.
# Whitelist conservadora — se faltar algo, dá pra adicionar depois.
$junkPatterns = @(
    "GameGuard",      # pasta inteira do GameGuard (anti-cheat)
    "GameMon.des",
    "npggNT.des",
    "npsc.des",
    "OnePunch.dll",
    "CSAuth*.dll",
    "Webzen",         # pasta da Webzen
    "Patcher.exe",
    "Launcher.exe",   # se vier o launcher da Webzen, troca
    "Update.exe",
    "Updater.exe",
    "MUUpdater.exe",
    "*.log",
    "Screen",         # screenshots do install antigo
    "replays",        # replays do install antigo
    "Settings.ini",   # config do install antigo (será regerado)
    "version.dat"
)
$removed = 0
foreach ($p in $junkPatterns) {
    Get-ChildItem -Path $stage -Filter $p -Force -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Remove-Item $_.FullName -Recurse -Force
                $removed++
            } catch {
                Warn "Não consegui remover: $($_.FullName)"
            }
        }
}
Ok "Removidos: $removed itens (anti-cheat / launcher antigo)"

# ── Aplica binários do MuMain (substitui main.exe e DLLs) ──────────────
Step "Aplicando binários do MuMain por cima"
$mumainFiles = Get-ChildItem $mumainRoot -File | Where-Object { $_.Extension -in ".exe", ".dll" }
foreach ($f in $mumainFiles) {
    Copy-Item $f.FullName -Destination (Join-Path $stage $f.Name) -Force
}
Ok "Aplicados: $($mumainFiles.Count) binário(s) do MuMain"

# ── Gera play.bat com o IP do servidor ─────────────────────────────────
Step "Gerando play.bat com SERVER=$ServerHost PORT=$Port"
$playBat = @"
@echo off
REM ────────────────────────────────────────────────────────────────────
REM  MU PORCARIA — launcher do client MuMain
REM  Versão do pack: v$Version
REM ────────────────────────────────────────────────────────────────────

SET SERVER=$ServerHost
SET PORT=$Port

cd /d "%~dp0"
main.exe connect /u%SERVER% /p%PORT%
"@
# Sem BOM, line ending CRLF (.bat exige)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText(
    (Join-Path $stage "play.bat"),
    ($playBat -replace "(?<!`r)`n", "`r`n"),
    $utf8NoBom)
Ok "play.bat escrito"

# ── Copia LEIA-ME.txt do template ──────────────────────────────────────
Step "Copiando LEIA-ME.txt"
$templateReadme = Join-Path $PSScriptRoot "README.player.txt"
if (Test-Path $templateReadme) {
    Copy-Item $templateReadme -Destination (Join-Path $stage "LEIA-ME.txt") -Force
    # Substitui o placeholder do domínio na cópia
    $content = Get-Content (Join-Path $stage "LEIA-ME.txt") -Raw
    $content = $content -replace "seu-dominio\.com", $ServerHost
    [System.IO.File]::WriteAllText((Join-Path $stage "LEIA-ME.txt"), $content, $utf8NoBom)
    Ok "LEIA-ME.txt escrito (com $ServerHost preenchido)"
} else {
    Warn "Template README.player.txt não encontrado em $PSScriptRoot — pulei."
}

# ── Compacta zip ───────────────────────────────────────────────────────
Step "Compactando zip (pode demorar bastante — 1–10 min dependendo do tamanho)"
$zipPath = Join-Path $OutputDir "$PackName-v$Version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

# Compress-Archive é lento pra GBs. Tenta usar 7-Zip se estiver no PATH.
$sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue
if ($sevenZip) {
    Write-Host "   usando 7-Zip ($($sevenZip.Source))" -ForegroundColor Gray
    & $sevenZip a -tzip -mx=5 "$zipPath" "$stage\*" | Out-Null
} else {
    Write-Host "   usando Compress-Archive (instala 7-Zip pra ser muito mais rápido)" -ForegroundColor Gray
    Compress-Archive -Path "$stage\*" -DestinationPath $zipPath -CompressionLevel Optimal
}

if (-not (Test-Path $zipPath)) { Fail "Zip não foi gerado." }
$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
$sha = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()

# ── Limpeza opcional ───────────────────────────────────────────────────
if (-not $KeepStaging) {
    Step "Limpando staging"
    Remove-Item (Join-Path $OutputDir "staging") -Recurse -Force
}

# ── Resumo ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  PACK PRONTO" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Arquivo:  $zipPath"
Write-Host "  Tamanho:  $zipSize MB"
Write-Host "  SHA-256:  $sha"
Write-Host "  Servidor: $ServerHost`:$Port"
Write-Host ""
Write-Host "  Próximo passo: sobe esse zip num bucket / Discord / R2 e"
Write-Host "  linka na página de cadastro." -ForegroundColor Gray
