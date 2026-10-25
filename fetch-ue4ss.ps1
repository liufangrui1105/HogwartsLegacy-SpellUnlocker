# =============================================================================
#  下载官方 UE4SS（experimental 构建）到 UE4SS\
#  - 只从 UE4SS 官方 GitHub Releases 下载，不修改二进制
#  - 目的：仓库里不携带 23 MB 的第三方 DLL，安装时按需获取
# =============================================================================
param(
    [string]$Dest = (Join-Path $PSScriptRoot 'UE4SS'),
    [string]$ZipUrl = 'https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/UE4SS_v3.0.1-201-g7cd4e3f.zip'
)

$ErrorActionPreference = 'Stop'

function Say($m) { Write-Host "[ue4ss] $m" }
function Bad($m) { Write-Host "[ue4ss] $m" -ForegroundColor Red }

if ((Test-Path (Join-Path $Dest 'dwmapi.dll')) -and (Test-Path (Join-Path $Dest 'ue4ss\UE4SS.dll'))) {
    Say 'UE4SS 已存在，跳过下载'
    exit 0
}

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$tmp = Join-Path $env:TEMP ('ue4ss_' + [guid]::NewGuid().ToString('N') + '.zip')
Say "下载: $ZipUrl"
try {
    Invoke-WebRequest -Uri $ZipUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 120
} catch {
    Bad "下载失败: $($_.Exception.Message)"
    Bad '可以手动下载后解压到 UE4SS\ 目录（详见 README「手动安装」）。'
    exit 3
}

try {
    if (Test-Path $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
    Expand-Archive -LiteralPath $tmp -DestinationPath $Dest -Force
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path (Join-Path $Dest 'dwmapi.dll'))) {
    Bad '下载包布局异常：缺少 dwmapi.dll。请改用手动安装。'
    exit 4
}
if (-not (Test-Path (Join-Path $Dest 'ue4ss\UE4SS.dll'))) {
    Bad '下载包布局异常：缺少 ue4ss\UE4SS.dll。请改用手动安装。'
    exit 4
}
Say 'UE4SS 已就绪'
exit 0