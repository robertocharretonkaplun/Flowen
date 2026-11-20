<#
.SYNOPSIS
Compila el instalador de Flowen (dist\Flowen-<versión>-Setup-x64.exe) con Inno Setup 7 o 6.

.DESCRIPTION
Usa FlowenInnoSetup.iss, en la raíz del repositorio, sobre dist\Flowen-x64 (o la carpeta de
-Dist). Ejecuta antes packaging\windows.ps1 para armar esa carpeta. Busca ISCC.exe en Program Files y en el PATH;
-Iscc indica otra ruta. Escribe la ruta del instalador creado.
#>
[CmdletBinding()]
param(
    [string]$Iscc,
    # La carpeta armada por packaging\windows.ps1; por omisión, dist\Flowen-x64.
    [string]$Dist
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repo 'FlowenInnoSetup.iss'
if (-not $Dist) { $Dist = Join-Path $repo 'dist\Flowen-x64' }
$Dist = [IO.Path]::GetFullPath($Dist)
if (-not (Test-Path -LiteralPath (Join-Path $Dist 'flowen.exe'))) {
    throw "Falta flowen.exe en $Dist. Ejecuta antes packaging\windows.ps1."
}
if (-not $Iscc) {
    $candidates = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if ($base -and (Test-Path -LiteralPath $base)) {
            $candidates += Get-ChildItem -LiteralPath $base -Directory -Filter 'Inno Setup *' -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'ISCC.exe' }
        }
    }
    $onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    $Iscc = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Iscc) { throw 'No se encontró Inno Setup. Instálalo desde https://jrsoftware.org/isdl.php o indica -Iscc.' }

& $Iscc /Q "/DDistDir=$Dist" $script
if ($LASTEXITCODE -ne 0) { throw "Inno Setup no pudo compilar el instalador (código $LASTEXITCODE)." }
Get-ChildItem -LiteralPath (Join-Path $repo 'dist') -Filter 'Flowen-*-Setup-x64.exe' |
    Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { $_.FullName }
