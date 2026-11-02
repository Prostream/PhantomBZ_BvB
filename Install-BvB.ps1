param([Parameter(Mandatory=$true)][string]$GameDir)
$ErrorActionPreference = 'Stop'
$bvbGameRoot = (Resolve-Path -LiteralPath $GameDir).Path
$bvbPlatform = Join-Path $bvbGameRoot 'platform\steam'
if (-not (Test-Path -LiteralPath (Join-Path $bvbPlatform 'PBZ.exe'))) { throw 'Not a PBZ installation: platform\steam\PBZ.exe is missing.' }
if (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'PBZ*' }).Count) { throw 'Close PBZ before installing. No game process is stopped by this script.' }
$bvbLoader = Join-Path $bvbPlatform 'ue4ss'
foreach ($required in @('UE4SS.dll','MemberVariableLayout.ini','UE4SS_Signatures\GNatives.lua','UE4SS_Signatures\GUObjectArray.lua')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bvbLoader $required))) { throw "Existing PBZ-compatible UE4SS required: $required" }
}
$bvbMods = Join-Path $bvbLoader 'Mods'
$bvbList = Join-Path $bvbMods 'mods.txt'
$bvbListText = if (Test-Path -LiteralPath $bvbList) { [IO.File]::ReadAllText($bvbList) } else { '' }
if ($bvbListText -match '(?m)^\s*PhantomGladiator\s*:\s*1\s*$' -or (Test-Path -LiteralPath (Join-Path $bvbMods 'PhantomGladiator\enabled.txt'))) {
    throw 'Disable PhantomGladiator before installing this independent derivative. Other mods have not been changed.'
}
$bvbDestination = [IO.Path]::GetFullPath((Join-Path $bvbMods 'PhantomBZ_BvB'))
if (-not $bvbDestination.StartsWith($bvbMods + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid installation target.' }
if (Test-Path -LiteralPath $bvbDestination) {
    if ((Get-Item -LiteralPath $bvbDestination).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing a redirected mod directory.' }
}
$bvbBackup = Join-Path $bvbPlatform ('PhantomBZ_BvB-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $bvbBackup -Force | Out-Null
if (Test-Path -LiteralPath $bvbList) { Copy-Item -LiteralPath $bvbList -Destination (Join-Path $bvbBackup 'mods.txt') }
if (Test-Path -LiteralPath $bvbDestination) { Copy-Item -LiteralPath $bvbDestination -Destination (Join-Path $bvbBackup 'PhantomBZ_BvB') -Recurse }
$bvbScripts = Join-Path $bvbDestination 'Scripts'
$bvbRuntime = Join-Path $bvbDestination 'Runtime'
New-Item -ItemType Directory -Path $bvbScripts,$bvbRuntime -Force | Out-Null
$bvbHashes = @{}
foreach ($source in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Mods\PhantomGladiator\Scripts') -Filter '*.lua' -File) {
    $target = Join-Path $bvbScripts $source.Name
    Copy-Item -LiteralPath $source.FullName -Destination $target -Force
    if ($source.Name -eq 'config.lua') {
        $config = [IO.File]::ReadAllText($target)
        $runtimeLiteral = ConvertTo-Json -InputObject $bvbRuntime.Replace('\','/') -Compress
        $config = [regex]::Replace($config, '(?m)^Config\.RuntimePath\s*=.*$', ('Config.RuntimePath = ' + $runtimeLiteral))
        [IO.File]::WriteAllText($target,$config,[Text.UTF8Encoding]::new($false))
    } elseif ((Get-FileHash -LiteralPath $source.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "Copy verification failed: $target" }
    $bvbHashes[$source.Name] = (Get-FileHash -LiteralPath $target).Hash
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LICENSE') -Destination (Join-Path $bvbDestination 'LICENSE') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'UPSTREAM.md') -Destination (Join-Path $bvbDestination 'UPSTREAM.md') -Force
# Change only our entry; preserve every other mod's configuration.
$bvbListText = [regex]::Replace($bvbListText,'(?m)^\s*PhantomBZ_BvB\s*:\s*[01]\s*$','PhantomBZ_BvB : 1')
if ($bvbListText -notmatch '(?m)^PhantomBZ_BvB : 1\s*$') { $bvbListText = $bvbListText.TrimEnd() + "`r`nPhantomBZ_BvB : 1`r`n" }
[IO.File]::WriteAllText($bvbList,$bvbListText,[Text.UTF8Encoding]::new($false))
$receipt = @{ game_dir=$bvbGameRoot; runtime=$bvbRuntime; backup=$bvbBackup; installed_at=(Get-Date).ToString('o'); build='0.1.0-dev'; hashes=$bvbHashes }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'installation.json'),($receipt | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
Write-Output "Installed PhantomBZ_BvB. Existing UE4SS and other mods preserved."
Write-Output "Runtime: $bvbRuntime"
Write-Output "Backup: $bvbBackup"
Write-Output 'Start the game yourself, load a first-playthrough save, and select Hard / 逆天者.'
