# purge-webzen.ps1
#
# Apaga os binários proprietários da Webzen do client-pack/, deixando só
# os assets (Data/, Music/, Sound/, etc.) e os helpers (build-pack.ps1,
# play.bat, README*.*).
#
# Uso:
#   .\client-pack\purge-webzen.ps1                # mostra o que vai apagar
#   .\client-pack\purge-webzen.ps1 -Confirm       # apaga de fato
#   .\client-pack\purge-webzen.ps1 -Path D:\algum\client -Confirm

[CmdletBinding()]
param(
    # Pasta-alvo. Default: a própria pasta deste script (client-pack/).
    [string]$Path = $PSScriptRoot,

    # Sem isso, é dry-run (mostra o que faria, não apaga).
    [switch]$Confirm
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Path -PathType Container)) {
    Write-Host "✗ Path '$Path' não existe ou não é uma pasta." -ForegroundColor Red
    exit 1
}

# Padrões a apagar (Webzen + anti-cheat + custom launcher Brazucas):
$patterns = @(
    "Main.exe", "Mu.exe", "Uninstal.exe", "Patcher.exe",
    "Launcher.exe", "Update.exe", "Updater.exe", "MUUpdater.exe",
    "*.dll",
    "*.emu",
    "*.des",
    "Settings.ini", "version.dat",
    "Screen", "replays", "GameGuard", "Webzen",
    "*.log"
)

# Helpers que NUNCA devem ser tocados, mesmo se baterem nos padrões acima:
$keep = @(
    "build-pack.ps1",
    "purge-webzen.ps1",
    "play.bat",
    "README.md",
    "README.player.txt",
    "Data", "Music", "Sound", "Object", "Player", "Lang",
    "Tile", "Effect", "Item", "Skill", "Interface", "Mob", "DropItem"
)
# (Data e amigos estão no keep só pra defesa em depth — assets não casam
# com os padrões acima de qualquer jeito.)

$victims = @()
foreach ($p in $patterns) {
    Get-ChildItem -Path $Path -Filter $p -Force -ErrorAction SilentlyContinue |
        Where-Object { $keep -notcontains $_.Name } |
        ForEach-Object { $victims += $_ }
}
$victims = $victims | Sort-Object FullName -Unique

if (-not $victims) {
    Write-Host "✓ Nada pra apagar — pasta já está limpa." -ForegroundColor Green
    exit 0
}

$totalSize = ($victims | Measure-Object Length -Sum).Sum
Write-Host ""
Write-Host "Vai apagar $($victims.Count) item(s), totalizando $([math]::Round($totalSize/1MB, 1)) MB:" -ForegroundColor Yellow
Write-Host ""
foreach ($v in $victims) {
    $size = if ($v.PSIsContainer) { "<dir>" } else { "{0,8:N0}" -f $v.Length }
    Write-Host ("  {0}  {1}" -f $size, $v.Name)
}
Write-Host ""

if (-not $Confirm) {
    Write-Host "Esse foi um DRY-RUN. Pra apagar de fato, rode novamente com -Confirm:" -ForegroundColor Cyan
    Write-Host "  .\client-pack\purge-webzen.ps1 -Confirm" -ForegroundColor Cyan
    exit 0
}

foreach ($v in $victims) {
    try {
        Remove-Item -LiteralPath $v.FullName -Recurse -Force
        Write-Host "  ✓ removido: $($v.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ falha em $($v.Name): $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Pronto. Pasta limpa." -ForegroundColor Green
