# =============================================================================
#  SpellUnlocker v1.7.0 安装脚本（面向用户，双击 INSTALL.bat 即可）
#  做的事：
#    1. 自动定位 Steam / Epic 版《霍格沃茨之遗》（找不到时可手动输入路径）
#    2. 备份原有 UE4SS / dwmapi.dll（如果有）
#    3. 安装 UE4SS（dwmapi.dll 代理 + ue4ss\ 子目录）
#    4. 写入 HL 专用 UE4SS-settings.ini 关键项
#    5. 安装 SpellUnlocker mod 并登记到 mods.txt / mods.json
#  ★ 只新增/覆盖 Mod 运行所需文件，绝不修改 HogwartsLegacy.exe 及游戏原始 dll
# =============================================================================
param(
    [string]$Game = ''
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ModVersion = '1.7.0'

function Say($m)  { Write-Host "[安装] $m" }
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

    # 1) Steam 注册表 + libraryfolders.vdf
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

    # 2) Epic 启动器安装清单
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

    # 3) 常见目录兜底
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

function Set-IniValue {
    param([string[]]$Lines, [string]$Section, [string]$Key, [string]$Value)
    $secIdx = -1; $endIdx = $Lines.Count
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i].Trim() -eq "[$Section]") { $secIdx = $i; break } }
    if ($secIdx -lt 0) { return @($Lines + '', "[$Section]", "$Key = $Value") }
    for ($i = $secIdx + 1; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^\s*\[') { $endIdx = $i; break } }
    for ($i = $secIdx + 1; $i -lt $endIdx; $i++) {
        if ($Lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") { $Lines[$i] = "$Key = $Value"; return $Lines }
    }
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -le $secIdx; $i++) { $out.Add($Lines[$i]) }
    $out.Add("$Key = $Value")
    for ($i = $secIdx + 1; $i -lt $Lines.Count; $i++) { $out.Add($Lines[$i]) }
    return $out.ToArray()
}

function Enable-ModInTxt([string]$Path) {
    $lines = @()
    if (Test-Path -LiteralPath $Path) { $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8) }
    $out = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*SpellUnlocker\s*:') { $out.Add('SpellUnlocker : 1'); $found = $true }
        else { $out.Add($line) }
    }
    if (-not $found) {
        $idx = $out.Count
        for ($i = 0; $i -lt $out.Count; $i++) { if ($out[$i] -match 'Built-in keybinds') { $idx = $i; break } }
        $out.Insert($idx, 'SpellUnlocker : 1')
    }
    [System.IO.File]::WriteAllText($Path, (($out -join "`r`n") + "`r`n"), $utf8NoBom)
}

function Enable-ModInJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $obj = $raw | ConvertFrom-Json
        $list = New-Object System.Collections.Generic.List[object]
        $found = $false
        foreach ($e in @($obj)) {
            $name = [string]$e.mod_name
            $enabled = [bool]$e.mod_enabled
            if ($name -eq 'SpellUnlocker') { $enabled = $true; $found = $true }
            $list.Add([pscustomobject]@{ mod_name = $name; mod_enabled = $enabled })
        }
        if (-not $found) { $list.Add([pscustomobject]@{ mod_name = 'SpellUnlocker'; mod_enabled = $true }) }
        [System.IO.File]::WriteAllText($Path, ((ConvertTo-Json -InputObject @($list.ToArray()) -Depth 5) + "`r`n"), $utf8NoBom)
        Say 'mods.json 已更新'
    } catch {
        Warn "mods.json 解析失败，已跳过（mods.txt 仍然有效）: $($_.Exception.Message)"
    }
}

# ---------- 检查安装包完整性 ----------
$payload = Join-Path $here 'UE4SS'
$modSrc  = Join-Path $here 'Mods\SpellUnlocker'
$required = @(
    (Join-Path $payload 'dwmapi.dll'),
    (Join-Path $payload 'ue4ss\UE4SS.dll'),
    (Join-Path $payload 'ue4ss\UE4SS-settings.ini'),
    (Join-Path $modSrc 'Scripts\main.lua'),
    (Join-Path $modSrc 'Scripts\config.lua'),
    (Join-Path $modSrc 'enabled.txt')
)
foreach ($need in $required) {
    if (-not (Test-Path -LiteralPath $need)) { Bad "安装包不完整，缺少: $need"; exit 1 }
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

if (-not $gameDir) {
    Bad '没找到游戏目录。可手动指定，例如：'
    Write-Host '  powershell -ExecutionPolicy Bypass -File install.ps1 -Game "D:\SteamLibrary\steamapps\common\Hogwarts Legacy"'
    exit 1
}

$win64 = Join-Path $gameDir 'Phoenix\Binaries\Win64'
Say "游戏目录: $gameDir"
Say "Mod 版本: v$ModVersion"

# ---------- 游戏必须已退出 ----------
if (Get-Process -Name 'HogwartsLegacy' -ErrorAction SilentlyContinue) {
    Bad '检测到《霍格沃茨之遗》正在运行。请先完全退出游戏，再重新运行安装器。'
    exit 1
}

# ---------- 写入权限 ----------
if (-not (Test-Writable $win64)) {
    if (Test-Admin) {
        Bad "即使以管理员身份运行，也无法写入目录: $win64"
        exit 1
    }
    Bad '当前用户没有写入游戏目录的权限。'
    Write-Host '  请右键 INSTALL.bat，选择“以管理员身份运行”。'
    exit 5
}

# ---------- 识别是否为覆盖升级 ----------
$markerPath = Join-Path $win64 'ue4ss\.spell_unlocker_marker.json'
$oldMarker = $null
if (Test-Path -LiteralPath $markerPath) {
    try { $oldMarker = [System.IO.File]::ReadAllText($markerPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $oldMarker = $null }
}

$createdDwmapi = $true
$createdUe4ss  = $true
$backupDir     = ''
if ($oldMarker) {
    Say '检测到已安装的 SpellUnlocker，将执行覆盖升级（保留原有 config.lua）'
    $createdDwmapi = $false
    $createdUe4ss  = $false
    if ($null -ne $oldMarker.created_dwmapi) { $createdDwmapi = [bool]$oldMarker.created_dwmapi }
    if ($null -ne $oldMarker.created_ue4ss)  { $createdUe4ss  = [bool]$oldMarker.created_ue4ss }
    if ($oldMarker.backup_dir) {
        $candidate = [string]$oldMarker.backup_dir
        if (Test-Path -LiteralPath $candidate) { $backupDir = $candidate }
    }
}

# ---------- 备份 ----------
if (-not $oldMarker) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupCandidate = Join-Path $win64 ("_SpellUnlocker_backup_" + $stamp)
    $needBackup = (Test-Path -LiteralPath (Join-Path $win64 'dwmapi.dll')) -or (Test-Path -LiteralPath (Join-Path $win64 'ue4ss'))
    if ($needBackup) {
        New-Item -ItemType Directory -Force -Path $backupCandidate | Out-Null
        if (Test-Path -LiteralPath (Join-Path $win64 'dwmapi.dll')) {
            Copy-Item -LiteralPath (Join-Path $win64 'dwmapi.dll') -Destination (Join-Path $backupCandidate 'dwmapi.dll') -Force
            $createdDwmapi = $false
            Say "已备份原有 dwmapi.dll -> $backupCandidate"
        }
        if (Test-Path -LiteralPath (Join-Path $win64 'ue4ss')) {
            Copy-Item -LiteralPath (Join-Path $win64 'ue4ss') -Destination (Join-Path $backupCandidate 'ue4ss') -Recurse -Force
            $createdUe4ss = $false
            Say "已备份原有 ue4ss\ -> $backupCandidate"
        }
        $backupDir = $backupCandidate
    }
}

# ---------- 暂存用户配置 ----------
$modDst = Join-Path $win64 'ue4ss\Mods\SpellUnlocker'
$configTemp = ''
$configPreserved = $false
$oldConfig = Join-Path $modDst 'Scripts\config.lua'
if (Test-Path -LiteralPath $oldConfig) {
    $configTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('SpellUnlocker-config-' + [guid]::NewGuid().ToString('N') + '.lua')
    Copy-Item -LiteralPath $oldConfig -Destination $configTemp -Force
    $configPreserved = $true
    Say '已暂存现有 config.lua'
}

# 暂存已有的 mods.txt / mods.json，避免覆盖安装时冲掉其他 UE4SS Mod 的登记
$modsTxtPath  = Join-Path $win64 'ue4ss\Mods\mods.txt'
$modsJsonPath = Join-Path $win64 'ue4ss\Mods\mods.json'
$savedModsTxt = ''
$savedModsJson = ''
if (Test-Path -LiteralPath $modsTxtPath) {
    $savedModsTxt = Join-Path ([System.IO.Path]::GetTempPath()) ('SpellUnlocker-mods-' + [guid]::NewGuid().ToString('N') + '.txt')
    Copy-Item -LiteralPath $modsTxtPath -Destination $savedModsTxt -Force
}
if (Test-Path -LiteralPath $modsJsonPath) {
    $savedModsJson = Join-Path ([System.IO.Path]::GetTempPath()) ('SpellUnlocker-mods-' + [guid]::NewGuid().ToString('N') + '.json')
    Copy-Item -LiteralPath $modsJsonPath -Destination $savedModsJson -Force
}

try {
    # ---------- 安装 UE4SS ----------
    Copy-Item -LiteralPath (Join-Path $payload 'dwmapi.dll') -Destination (Join-Path $win64 'dwmapi.dll') -Force
    Say 'dwmapi.dll 已放置（UE4SS 注入代理）'

    # 复制整个 ue4ss 目录：源目录 -> 目标目录下同名子目录；已存在则合并覆盖。
    # 注意：不能用 -LiteralPath "...\ue4ss\*"（LiteralPath 不展开通配符，会静默什么都不复制）。
    Copy-Item -LiteralPath (Join-Path $payload 'ue4ss') -Destination $win64 -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $win64 'ue4ss\UE4SS.dll'))) {
        throw 'UE4SS.dll 未就位，安装包可能不完整（应位于 UE4SS\ue4ss\UE4SS.dll）'
    }
    if ($savedModsTxt) {
        Copy-Item -LiteralPath $savedModsTxt -Destination $modsTxtPath -Force
        Say '已保留原有 mods.txt（其他 UE4SS Mod 的登记不会丢失）'
    }
    if ($savedModsJson) {
        Copy-Item -LiteralPath $savedModsJson -Destination $modsJsonPath -Force
        Say '已保留原有 mods.json（其他 UE4SS Mod 的登记不会丢失）'
    }
    Say 'ue4ss\ 已安装（UE4SS.dll 与 Mods 目录就绪）'

    # ---------- 写 HL 专用 ini ----------
    $iniPath = Join-Path $win64 'ue4ss\UE4SS-settings.ini'
    if (-not (Test-Path -LiteralPath $iniPath)) { [System.IO.File]::WriteAllText($iniPath, "", $utf8NoBom) }
    $lines = [System.IO.File]::ReadAllLines($iniPath, [System.Text.Encoding]::UTF8)

    $lines = Set-IniValue $lines 'EngineVersionOverride' 'MajorVersion' '4'
    $lines = Set-IniValue $lines 'EngineVersionOverride' 'MinorVersion' '27'
    $lines = Set-IniValue $lines 'General' 'bUseUObjectArrayCache' 'false'
    $lines = Set-IniValue $lines 'Hooks' 'HookLocalPlayerExec' '1'
    $lines = Set-IniValue $lines 'Hooks' 'FExecVTableOffsetInLocalPlayer' '0x28'
    $lines = Set-IniValue $lines 'Debug' 'ConsoleEnabled' '1'
    $lines = Set-IniValue $lines 'Debug' 'GuiConsoleEnabled' '1'
    $lines = Set-IniValue $lines 'Debug' 'GuiConsoleVisible' '0'
    [System.IO.File]::WriteAllText($iniPath, (($lines -join "`r`n") + "`r`n"), $utf8NoBom)
    Say 'UE4SS 配置已按霍格沃茨之遗要求写入（UTF-8 无 BOM）'

    # ---------- 安装 Mod ----------
    if (Test-Path -LiteralPath $modDst) { Remove-Item -LiteralPath $modDst -Recurse -Force }
    Copy-Item -LiteralPath $modSrc -Destination $modDst -Recurse -Force
    if ($configTemp -and (Test-Path -LiteralPath $configTemp)) {
        Copy-Item -LiteralPath $configTemp -Destination (Join-Path $modDst 'Scripts\config.lua') -Force
        Remove-Item -LiteralPath $configTemp -Force -ErrorAction SilentlyContinue
        Say '已保留原有 config.lua'
    }
    Say "SpellUnlocker -> $modDst"

    # ---------- 登记到 mods.txt / mods.json ----------
    Enable-ModInTxt (Join-Path $win64 'ue4ss\Mods\mods.txt')
    Say 'mods.txt 已启用 SpellUnlocker'
    Enable-ModInJson (Join-Path $win64 'ue4ss\Mods\mods.json')

    # ---------- 写安装标记（供卸载脚本精确回滚） ----------
    $marker = [ordered]@{
        mod             = 'SpellUnlocker'
        version         = $ModVersion
        installed_at    = (Get-Date).ToString('s')
        game            = $gameDir
        created_dwmapi  = $createdDwmapi
        created_ue4ss   = $createdUe4ss
        backup_dir      = $backupDir
        config_preserved = $configPreserved
    }
    [System.IO.File]::WriteAllText($markerPath, (ConvertTo-Json $marker -Depth 3), $utf8NoBom)

    Say ''
    Say "安装完成！SpellUnlocker v$ModVersion"
    Say '  1) 从 Steam 或 Epic 启动《霍格沃茨之遗》（不要直接双击 exe）'
    Say '  2) 进游戏后查看 Phoenix\Binaries\Win64\SpellUnlocker.log'
    Say '     正常应出现 applying to pawn / apply begin / apply end'
    Say '  3) F8 临时开关整个 Mod；控制台输入 spellunlock 查看状态'
    Say '  4) 卸载：双击 UNINSTALL.bat'
    if ($backupDir) { Say "  安装前备份：$backupDir" }
    if ($configPreserved) { Say '  已保留你原来的 config.lua；想恢复默认请删除它后重装。' }
    exit 0
} catch {
    Bad "安装过程中出错：$($_.Exception.Message)"
    if ($backupDir) { Warn "安装前备份保留在: $backupDir" }
    Warn '可双击 UNINSTALL.bat 尝试回滚，或把上面的错误信息发给作者。'
    exit 1
} finally {
    if ($configTemp -and (Test-Path -LiteralPath $configTemp)) {
        Remove-Item -LiteralPath $configTemp -Force -ErrorAction SilentlyContinue
    }
    if ($savedModsTxt -and (Test-Path -LiteralPath $savedModsTxt)) {
        Remove-Item -LiteralPath $savedModsTxt -Force -ErrorAction SilentlyContinue
    }
    if ($savedModsJson -and (Test-Path -LiteralPath $savedModsJson)) {
        Remove-Item -LiteralPath $savedModsJson -Force -ErrorAction SilentlyContinue
    }
}
