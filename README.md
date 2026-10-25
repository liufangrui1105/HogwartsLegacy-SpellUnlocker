# SpellUnlocker — Hogwarts Legacy 咒语解锁 / 冷却解除 Mod

> 非官方同人 Mod，与 Warner Bros. Games / Avalanche Software 无隶属关系。仓库内**不含任何游戏资源**。
> 基于 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) 3.x Lua 运行时注入：**不改 exe、不改 pak、可一键卸载**。

| 项 | 说明 |
|---|---|
| 版本 | v1.7.0 |
| 适用 | 《霍格沃茨之遗》Steam / Epic 版，Windows 10/11 x64，UE 4.27.2（Phoenix） |
| 实测 | Steam 版 appid `990080` / buildid `20773316`（含 Denuvo），功能与稳定性均已实测 |
| 许可 | 本项目代码 MIT；第三方组件见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) |

---

## 功能

| 功能 | 效果 | 默认 |
|---|---|:---:|
| **UnlockAllSpells** | 全部咒语直接解锁，无需上课 / 任务 / 知识卡即可装备施放 | ✅ 开 |
| **ZeroCooldown** | 冷却高速恢复 + 冷却读数归零 | ✅ 开 |
| **ForceSpellAvailable** | 强制「该咒语现在可用」，并走「立即施法」通道，冷却不再阻挡连放 | ✅ 开 |
| **CompleteKnowledge** | 一次性补满全部知识卡（约 386 张，副作用较大，会写存档） | ❌ 关 |
| **ExpandSpellSlots** | 每个法组 4 槽 → 8 槽（实验性；UI 仍只画 4 槽） | ❌ 关 |
| **UnlockAllPerks** | 激活全部天赋并补天赋点（会写存档） | ❌ 关 |

> 「咒语解锁」与「冷却解除」是两条独立链路：前者覆盖 `IsUnlocked` 判定，后者覆盖
> `WandTool::IsSpellToolAvailable` + `ActivateSpellTool(bImmediate)` 的施法门禁。默认三项全开即为完整效果。

---

## 安装

### 方式一：一键安装（推荐）

1. 下载本仓库（`Code` → `Download ZIP`）并**解压到任意目录**（不要在压缩包里直接运行）。
2. 双击 **`INSTALL.bat`**：
   - 首次运行会自动从 UE4SS 官方 Release 下载运行时（约 8 MB，需要联网）；
   - 自动定位 Steam / Epic 版游戏目录（找不到会让你粘贴游戏根目录，即包含 `Phoenix` 文件夹的那层）；
   - 自动备份已有的 `dwmapi.dll` / `ue4ss\`，完成后可直接卸载还原。
3. 从 **Steam / Epic** 启动游戏（Denuvo 需要走平台启动，不要直接双击 exe）。

> 游戏装在 `C:\Program Files` 等受保护目录时，右键 `INSTALL.bat` → **以管理员身份运行**。

### 方式二：手动安装

1. 从 <https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental> 下载
   `UE4SS_v3.0.1-201-g7cd4e3f.zip` 并解压。
2. 把里面的 `dwmapi.dll` 和 `ue4ss\` 目录复制到
   `<游戏目录>\Phoenix\Binaries\Win64\`（**子目录布局，不要平铺**）。
3. 用仓库里的 `fetch-ue4ss.ps1` 或手动调整 `ue4ss\UE4SS-settings.ini`：
   `EngineVersionOverride 4/27`、`bUseUObjectArrayCache = false`、
   `HookLocalPlayerExec = 1`、`FExecVTableOffsetInLocalPlayer = 0x28`、`ConsoleEnabled = 1`。
4. 把 `Mods\SpellUnlocker\` 复制到 `Win64\ue4ss\Mods\SpellUnlocker\`，
   并在 `Win64\ue4ss\Mods\mods.txt` 加一行 `SpellUnlocker : 1`。

---

## 使用

- 进游戏后 1~2 秒自动生效；**换图 / 读档 / 进地下城会自动重新应用**。
- **F8**：临时开关整个 Mod。
- 控制台（`F10` 或 `` ` ``）：

| 命令 | 作用 |
|---|---|
| `spellunlock` | 查看状态与 hook 命中数 |
| `spellunlock on` / `off` | 总开关 |
| `spellunlock apply` | 立即重新应用 |
| `spellunlock unlock` / `cooldown` | 切换对应功能 |
| `spellunlock knowledge` / `slots` / `perks` | 立即执行对应功能（有副作用） |
| `spellunlock dump` | 输出计数类诊断 |

### 配置

编辑 `Win64\ue4ss\Mods\SpellUnlocker\Scripts\config.lua`，改完重启游戏（或游戏内 `Ctrl+R` 热重载）。
所有功能互相独立，可只开你想要的。

---

## 卸载

双击 `UNINSTALL.bat`：移除 Mod 与本次安装的 UE4SS / `dwmapi.dll`，并恢复安装前备份；
**不会修改** `HogwartsLegacy.exe` 及游戏原始 dll。

只想关闭 Mod 而保留 UE4SS：把 `mods.txt` 里的 `SpellUnlocker : 1` 改成 `: 0`。

---

## 排查

| 文件 | 位置 |
|---|---|
| `SpellUnlocker.log` | `Win64\SpellUnlocker.log`（UTF-8） |
| `UE4SS.log` | `Win64\ue4ss\UE4SS.log` |

正常日志应包含：`v1.7.0 loading` → `hook ... registered` → `pawn spawned` → `apply to pawn ...` →
`SetCooldownRateScale(1000.0) applied`，换图时出现 `LoadMapPost hook #n`。

常见问题：

- **游戏没变化**：先看 `UE4SS.log` 里有没有 `SpellUnlocker` 加载行；没有说明 UE4SS 没注入（检查 `dwmapi.dll` 与 `ue4ss\` 位置）。
- **游戏更新后失效**：UE4SS 的 AOB 签名可能失效，换 `experimental` 通道同版本 UE4SS 即可，Mod 本身不用改。
- **出现 Fatal Error**：请把游戏目录 `Win64\ue4ss\crash_*.dmp` 保留并提供 —— 可用 `tools/parse_minidump.py` 自行解析出出错模块与偏移。

---

## 稳定性说明（v1.7.0）

v1.4 → v1.6 期间曾出现 `Fatal Error` 崩溃，根因已定位并修复（详见 [docs/崩溃分析与修复-2026-10-25.md](docs/崩溃分析与修复-2026-10-25.md)）：

1. **hook 内把游戏 `FName` 转字符串** → UE4SS 抛 C++ 异常，`pcall` 无法捕获，穿过 hook trampoline 破坏栈。
   → 已移除所有 FName/FString 转换。
2. **在定时器线程（非游戏线程）调用 `FindFirstOf` / `StaticFindObject` / `IsValid`**，换图时与游戏线程重建对象表竞争 → use-after-free。
   → v1.7 删除定时器内全部游戏 API 调用，应用逻辑只在游戏线程回调中执行。

验证：世界 ↔ 地下城反复进出、读档、战斗连放均无崩溃。

---

## 已知限制

- 仅支持 Steam / Epic 版；**Game Pass / Microsoft Store 版不支持**（打包与注入方式不同）。
- 技能槽仍是 UI 硬限制（4 槽/组），`ExpandSpellSlots` 属实验性。
- `ForceSpellAvailable` 会放开部分过场/剧情的「不可施法」限制，属预期副作用，可 F8 临时关闭。
- `config.lua` 里的 `HardClearCooldowns` / `ClearCooldownsByCategory` **默认关闭且不建议打开**（在本游戏版本上会触发 Fatal Error）。
- `DumpSpellNames` 默认关闭（FName 转换是历史崩溃原因）。
- 请自行备份存档：`%LOCALAPPDATA%\Hogwarts Legacy\Saved\SaveGames\`。

---

## 目录结构

```
Mods/SpellUnlocker/          Mod 本体（enabled.txt + Scripts/main.lua + config.lua）
install.ps1 / uninstall.ps1 / INSTALL.bat / UNINSTALL.bat / fetch-ue4ss.ps1   一键安装与卸载（自动下载官方 UE4SS）
docs/                        崩溃分析、实测记录
tools/parse_minidump.py      崩溃转储解析工具（纯 Python）
```

## 许可

本项目代码（Lua、PowerShell、文档、工具）采用 **MIT License**，见 [LICENSE](LICENSE)。
UE4SS 为独立 MIT 项目，见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
游戏商标与素材归 Warner Bros. Games / Avalanche Software 所有。

English: [README_EN.md](README_EN.md)