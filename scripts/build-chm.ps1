param([string]$Compiler = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$helpRoot = Join-Path $projectRoot 'docs\help'
$projectFile = Join-Path $helpRoot 'RBMI.hhp'
if (-not $Compiler) {
  $candidates = @('C:\Program Files (x86)\HTML Help Workshop\hhc.exe','C:\Program Files\HTML Help Workshop\hhc.exe')
  $Compiler = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Compiler -or -not (Test-Path -LiteralPath $Compiler)) { throw 'Install Microsoft HTML Help Workshop, then pass -Compiler with the full path to hhc.exe. Printable docs\help\printable.html is available without a compiler.' }
if ([IO.Path]::GetFileName($Compiler) -ne 'hhc.exe') { throw 'Compiler must be hhc.exe.' }
$startedAt = Get-Date
Push-Location $helpRoot
try { & $Compiler $projectFile; $compilerExitCode = $LASTEXITCODE } finally { Pop-Location }
$outputFile = Join-Path $helpRoot 'RBMI.chm'
if (-not (Test-Path -LiteralPath $outputFile) -or (Get-Item -LiteralPath $outputFile).LastWriteTime -lt $startedAt -or (Get-Item -LiteralPath $outputFile).Length -eq 0) { throw "CHM compilation did not create a current output. Compiler exit code: $compilerExitCode. Review compiler messages." }
# HTML Help compiler may use exit code 1 for successful compilation; verify the actual output.
Write-Host "Compiled: $outputFile"
