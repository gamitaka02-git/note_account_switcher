$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $compiler)) {
    throw '.NET Framework C# compilerが見つかりません。'
}

$icon = Join-Path (Split-Path -Parent $root) 'mac\icon.ico'
$arguments = @(
    '/nologo', '/target:winexe', '/optimize+',
    '/reference:System.dll', '/reference:System.Core.dll',
    '/reference:System.Drawing.dll', '/reference:System.Windows.Forms.dll',
    '/reference:System.Runtime.Serialization.dll',
    ('/out:' + (Join-Path $root 'noteアカウントスイッチャー.exe')),
    ('/win32icon:' + $icon),
    (Join-Path $root 'NoteAccountSwitcher.cs')
)
& $compiler $arguments
if ($LASTEXITCODE -ne 0) { throw 'ビルドに失敗しました。' }
Write-Host ('Built: ' + (Join-Path $root 'noteアカウントスイッチャー.exe'))
