param(
    [string]$RuntimeDir = 'D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PhantomGladiator\Runtime',
    [ValidateRange(1, 65535)][int]$Port = 8765,
    [string]$PythonPath = ''
)
$ErrorActionPreference = 'Stop'
if (-not $PythonPath) {
    $panelPythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($panelPythonCommand) {
        $PythonPath = $panelPythonCommand.Source
    } else {
        $PythonPath = 'D:\DevTools\Python\cpython-3.11-windows-x86_64-none\python.exe'
    }
}
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
    throw 'Python 3.11+ 未找到，请用 -PythonPath 指定解释器路径。'
}
& $PythonPath -I (Join-Path $PSScriptRoot 'backend.py') --runtime-dir $RuntimeDir --port $Port --static-dir (Join-Path $PSScriptRoot 'static')
exit $LASTEXITCODE
