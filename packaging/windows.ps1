[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildDir,
    [Parameter(Mandatory)][string]$QtDir,
    [string]$CrtDir,
    [string]$OutputDir = (Join-Path $PSScriptRoot '../dist/Lunqio-x64')
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$build = (Resolve-Path $BuildDir).Path
$qt = (Resolve-Path $QtDir).Path
$target = [IO.Path]::GetFullPath($OutputDir)
$archive = "$target.zip"
if ((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath $archive)) {
    throw 'Elige una carpeta de salida nueva con -OutputDir.'
}
if (-not $CrtDir) {
    $CrtDir = (Get-ChildItem (Join-Path $env:VCToolsRedistDir 'x64') -Directory -Filter '*.CRT' | Select-Object -First 1).FullName
}
if (-not (Test-Path (Join-Path $CrtDir 'msvcp140.dll'))) {
    throw 'Indica con -CrtDir la carpeta x64 Microsoft.VC*.CRT redistribuible de Visual Studio.'
}
$stage = Join-Path (Split-Path $target) ('.stage-' + [guid]::NewGuid().ToString('N'))
$out = Join-Path $stage (Split-Path $target -Leaf)
New-Item -ItemType Directory -Path $out -Force | Out-Null
foreach ($exe in @('lunqio.exe','notas-mcp.exe')) {
    Copy-Item -LiteralPath (Join-Path $build $exe) -Destination $out
}
$deploy = Join-Path $qt 'bin/windeployqt.exe'
$previousPath = $env:PATH
try {
    $env:PATH = (Join-Path $qt 'bin') + ';' + $previousPath
    & $deploy --release --qmldir (Join-Path $repo 'qml') --no-translations --no-compiler-runtime --exclude-plugins qsqlmimer,qsqlodbc,qsqlpsql (Join-Path $out 'lunqio.exe') (Join-Path $out 'notas-mcp.exe')
    if ($LASTEXITCODE -ne 0) { throw 'windeployqt falló.' }
} finally {
    $env:PATH = $previousPath
}
if (-not (Test-Path -LiteralPath (Join-Path $out 'sqldrivers/qsqlite.dll'))) {
    throw 'Falta el controlador SQLite en el paquete.'
}
Copy-Item (Join-Path $CrtDir '*.dll') -Destination $out
Set-Content -LiteralPath (Join-Path $out 'qt.conf') -Encoding ascii -Value @('[Paths]','Prefix=.','Plugins=.','QmlImports=qml')
Copy-Item -LiteralPath (Join-Path $repo 'README.md') -Destination $out
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'licenses') -Destination $out -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AVISOS.md') -Destination $out
Copy-Item (Join-Path $qt 'sbom/*.spdx') -Destination (Join-Path $out 'licenses')
$stagedZip = "$out.zip"
& tar.exe -a -cf $stagedZip -C $stage (Split-Path $target -Leaf)
if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el ZIP.' }
[IO.Directory]::Move($out,$target)
[IO.File]::Move($stagedZip,$archive)
[IO.Directory]::Delete($stage)
Write-Output $archive
