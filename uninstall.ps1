# =============================================================================
#  SpellUnlocker v1.7.0 卸载脚本
#  - 删除本 Mod 与本次安装的 UE4SS（若由本安装包安装）
#  - 恢复安装前备份的 dwmapi.dll / ue4ss\
#  - 绝不触碰 HogwartsLegacy.exe 和游戏原始 dll
# =============================================================================
param(
    [string]$Game = '',
    [switch]$KeepUE4SS
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ModVersion = '1.7.0'

function Say($m)  { Write-Host "[卸载] $m" }
function Warn($m) { Write-Host "[提示] $m" -ForegroundColor Yellow }
function Bad($m)  { Write-Host "[失败] $m" -ForegroundColor Red }

function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Test-Writable([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return $false }
    $probe = Join-Path $Dir ('.spellunlocker_write_test_' + [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($probe, 'ok')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

function Find-Game {
    $candidates = New-Object System.Collections.Generic.List[string]

    $steam = $null
    try { $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam) {
        try { $steam = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch { }
    }
    if ($steam) {
        try {
            $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                $txt = Get-Content -LiteralPath $vdf -Raw
                foreach ($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')) {
                    $lib = $m.Groups[1].Value -replace '\\\\', '\'
                    $candidates.Add((Join-Path $lib 'steamapps\common\Hogwarts Legacy'))
                }
            }
        } catch { }
        $candidates.Add((Join-Path $steam 'steamapps\common\Hogwarts Legacy'))
    }

    if ($env:ProgramData) {
        try {
            $epicDat = Join-Path $env:ProgramData 'Epic\UnrealEngineLauncher\LauncherInstalled.dat'
            if (Test-Path -LiteralPath $epicDat) {
                $epic = Get-Content -LiteralPath $epicDat -Raw | ConvertFrom-Json
                foreach ($i in @($epic.InstallationList)) {
                    if ($i.InstallLocation) { $candidates.Add([string]$i.InstallLocation) }
                }
            }
        } catch { }
    }

    foreach ($d in 'C','D','E','F','G','H') {
        $candidates.Add("${d}:\SteamLibrary\steamapps\common\Hogwarts Legacy")
        $candidates.Add("${d}:\Program Files (x86)\Steam\steamapps\common\Hogwarts Legacy")
        $candidates.Add("${d}:\Program Files\Steam\steamapps\common\Hogwarts Legacy")
        $candidates.Add("${d}:\Epic Games\Hogwarts Legacy")
        $candidates.Add("${d}:\Program Files\Epic Games\Hogwarts Legacy")
        $candidates.Add("${d}:\Games\Hogwarts Legacy")
    }

    foreach ($c in ($candidates | Select-Object -Unique)) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'Phoenix\Binaries\Win64\HogwartsLegacy.exe'))) { return $c }
    }
    return $null
}

function Remove-ModFromTxt([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    $new = @($lines | Where-Object { $_ -notmatch '^\s*SpellUnlocker\s*:' })
    if ($new.Count -ne $lines.Count) {
        [System.IO.File]::WriteAllText($Path, (($new -join "`r`n") + "`r`n"), $utf8NoBom)
        Say '已从 mods.txt 移除登记'
    }
}

function Remove-ModFromJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $obj = $raw | ConvertFrom-Json
        $kept = New-Object System.Collections.Generic.List[object]
        $removed = $false
        foreach ($e in @($obj)) {
            if ([string]$e.mod_name -eq 'SpellUnlocker') { $removed = $true; continue }
            $kept.Add([pscustomobject]@{ mod_name = [string]$e.mod_name; mod_enabled = [bool]$e.mod_enabled })
        }
        if ($removed) {
            [System.IO.File]::WriteAllText($Path, ((ConvertTo-Json -InputObject @($kept.ToArray()) -Depth 5) + "`r`n"), $utf8NoBom)
            Say '已从 mods.json 移除登记'
        }
    } catch {
        Warn "mods.json 清理失败，已跳过: $($_.Exception.Message)"
    }
}

# ---------- 定位游戏 ----------
if ($Game) {
    $Game = $Game.Trim().Trim('"').TrimEnd('\')
    if (Test-Path -LiteralPath (Join-Path $Game 'Phoenix\Binaries\Win64\HogwartsLegacy.exe')) {
        $gameDir = $Game
    } else {
        Bad "指定的游戏目录无效（找不到 Phoenix\Binaries\Win64\HogwartsLegacy.exe）: $Game"
        exit 1
    }
} else {
    Say '正在定位 Steam / Epic 版《霍格沃茨之遗》...'
    $gameDir = Find-Game
}

if (-not $gameDir) {
    Warn '没有自动找到游戏目录。'
    for ($i = 1; $i -le 3; $i++) {
        $input = Read-Host '请把游戏根目录（包含 Phoenix 文件夹）粘贴到这里，直接回车退出'
        if ([string]::IsNullOrWhiteSpace($input)) { break }
        $input = $input.Trim().Trim('"').TrimEnd('\')
        if (Test-Path -LiteralPath (Join-Path $input 'Phoenix\Binaries\Win64\HogwartsLegacy.exe')) {
            $gameDir = $input
            break
        }
        Bad '这个路径下没有 Phoenix\Binaries\Win64\HogwartsLegacy.exe，请重试。'
    }
}

if (-not $gameDir) { Bad '没找到游戏目录，无法卸载。'; exit 1 }

$win64  = Join-Path $gameDir 'Phoenix\Binaries\Win64'
$ue4ss  = Join-Path $win64 'ue4ss'
$mod    = Join-Path $ue4ss 'Mods\SpellUnlocker'
$marker = Join-Path $ue4ss '.spell_unlocker_marker.json'
Say "游戏目录: $gameDir"

if (Get-Process -Name 'HogwartsLegacy' -ErrorAction SilentlyContinue) {
    Bad '检测到《霍格沃茨之遗》正在运行。请先完全退出游戏，再重新运行卸载器。'
    exit 1
}

if (-not (Test-Writable $win64)) {
    if (Test-Admin) {
        Bad "即使以管理员身份运行，也无法写入目录: $win64"
        exit 1
    }
    Bad '当前用户没有写入游戏目录的权限。'
    Write-Host '  请右键 UNINSTALL.bat，选择“以管理员身份运行”。'
    exit 5
}

# ---------- 读取安装标记 ----------
$info = $null
if (Test-Path -LiteralPath $marker) {
    try { $info = [System.IO.File]::ReadAllText($marker, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $info = $null }
}

$createdDwmapi = $false
$createdUe4ss  = $false
$backupDir     = ''
if ($info) {
    if ($null -ne $info.created_dwmapi) { $createdDwmapi = [bool]$info.created_dwmapi }
    if ($null -ne $info.created_ue4ss)  { $createdUe4ss  = [bool]$info.created_ue4ss }
    if ($info.backup_dir) {
        $candidate = [string]$info.backup_dir
        if (Test-Path -LiteralPath $candidate) { $backupDir = $candidate }
    }
} else {
    Warn '未找到安装标记。为安全起见，本次只移除 SpellUnlocker，不会删除 ue4ss\ 或 dwmapi.dll。'
}

try {
    # 1) 删 Mod
    if (Test-Path -LiteralPath $mod) {
        Remove-Item -LiteralPath $mod -Recurse -Force
        Say '已删除 Mods\SpellUnlocker'
    } else {
        Say 'Mods\SpellUnlocker 不存在，跳过'
    }

    # 2) 取消 mods.txt / mods.json 登记
    Remove-ModFromTxt (Join-Path $ue4ss 'Mods\mods.txt')
    Remove-ModFromJson (Join-Path $ue4ss 'Mods\mods.json')

    if ($KeepUE4SS) {
        Say '已保留 UE4SS 和其他 UE4SS Mod（仅移除 SpellUnlocker）'
        Say '如果想彻底删除 UE4SS：手动删除 Win64\ue4ss\ 和 Win64\dwmapi.dll。'
    } else {
        # 3) dwmapi.dll：优先恢复安装前备份，否则仅删除本安装包创建的
        $backupDwmapi = ''
        $backupUe4ss  = ''
        if ($backupDir) {
            $backupDwmapi = Join-Path $backupDir 'dwmapi.dll'
            $backupUe4ss  = Join-Path $backupDir 'ue4ss'
        }

        if ($backupDwmapi -and (Test-Path -LiteralPath $backupDwmapi)) {
            Copy-Item -LiteralPath $backupDwmapi -Destination (Join-Path $win64 'dwmapi.dll') -Force
            Say '已恢复安装前的 dwmapi.dll'
        } elseif ($createdDwmapi -and (Test-Path -LiteralPath (Join-Path $win64 'dwmapi.dll'))) {
            Remove-Item -LiteralPath (Join-Path $win64 'dwmapi.dll') -Force
            Say '已删除本安装包放置的 dwmapi.dll'
        } elseif (Test-Path -LiteralPath (Join-Path $win64 'dwmapi.dll')) {
            Say 'dwmapi.dll 不是本安装包创建的，已保留'
        }

        # 4) ue4ss\：只有确认由本安装包创建时才删除
        if ($backupUe4ss -and (Test-Path -LiteralPath $backupUe4ss)) {
            if ($createdUe4ss) {
                if (Test-Path -LiteralPath $ue4ss) { Remove-Item -LiteralPath $ue4ss -Recurse -Force }
                Copy-Item -LiteralPath $backupUe4ss -Destination $ue4ss -Recurse -Force
                Say '已恢复安装前的 ue4ss\'
            } else {
                Say '安装前已存在 ue4ss\，为避免覆盖其他 UE4SS Mod，当前目录已保留。'
                Say "安装前备份仍保留在: $backupUe4ss"
            }
        } elseif ($createdUe4ss -and (Test-Path -LiteralPath $ue4ss)) {
            Remove-Item -LiteralPath $ue4ss -Recurse -Force
            Say '已删除本安装包创建的 ue4ss\ 目录'
        } elseif (Test-Path -LiteralPath $ue4ss) {
            Say 'ue4ss\ 不是本安装包创建的，已保留'
        }
    }

    # 5) 删除安装标记
    if (Test-Path -LiteralPath $marker) {
        Remove-Item -LiteralPath $marker -Force
        Say '已删除安装标记'
    }

    Say ''
    Say "卸载完成。SpellUnlocker v$ModVersion 已移除。"
    Say '游戏原始文件（HogwartsLegacy.exe 等）未被修改。'
    if ($backupDir -and (Test-Path -LiteralPath $backupDir)) {
        Say "安装前备份仍保留: $backupDir（确认无误后可手动删除）"
    }
    Say '如果 Steam 提示文件校验，让它校验一次即可。'
    exit 0
} catch {
    Bad "卸载过程中出错：$($_.Exception.Message)"
    if ($backupDir) { Warn "安装前备份位于: $backupDir" }
    Warn '如果游戏目录仍有残留，可先用 Steam 校验文件，再联系作者。'
    exit 1
}
