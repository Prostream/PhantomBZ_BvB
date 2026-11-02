param([string]$GameDir='', [ValidateRange(1024,65535)][int]$Port=8766)
$ErrorActionPreference='Stop'
if (-not $GameDir) {
    $receiptPath=Join-Path $PSScriptRoot 'installation.json'
    if (-not (Test-Path -LiteralPath $receiptPath)) { throw 'Run Install-BvB.ps1 first, or supply -GameDir.' }
    $GameDir=([IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json).game_dir
}
$bvbRuntime=Join-Path $GameDir 'platform\steam\ue4ss\Mods\PhantomBZ_BvB\Runtime'
if (-not (Test-Path -LiteralPath $bvbRuntime)) { throw 'PhantomBZ_BvB Runtime is missing. Install the mod first.' }
$python=(Get-Command python -ErrorAction Stop).Source
Write-Output "Open http://127.0.0.1:$Port/bvb.html"
& $python -X utf8 -u (Join-Path $PSScriptRoot 'panel\backend.py') --runtime-dir $bvbRuntime --static-dir (Join-Path $PSScriptRoot 'panel\static') --port $Port
exit $LASTEXITCODE
