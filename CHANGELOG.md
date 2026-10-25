# 更新日志

## v1.7.0 — 2026-10-26

**稳定性重构：修复两次导致游戏 `Fatal Error` 崩溃的问题（功能不变）**

- **崩溃根因 1（v1.4）**：hook 回调里把游戏 `FName` 转字符串。UE4SS 的该转换会抛 C++ 异常，且 Lua 的 `pcall` 无法捕获，异常穿过 hook trampoline 破坏栈，最终表现为 `UE4SS.dll+0x6C328F` 的 `0xC0000005`（3 个 minidump 同一地址）。→ 现已移除全部 FName/FString 转换，诊断只输出整数计数。
- **崩溃根因 2（v1.5 / v1.6）**：`LoopAsync` / `ExecuteWithDelay` 回调运行在**非游戏线程**，其中调用 `FindFirstOf` / `StaticFindObject` / `IsValid`；换图时与游戏线程重建对象表竞争，造成 use-after-free（崩溃线程栈全在 UE4SS.dll，无游戏帧）。
- **v1.7 修复**：删除定时器内所有游戏 API 调用；应用逻辑全部移入游戏线程回调（`NotifyOnNewObject(Biped_Player)`、`IsUnlocked` 命中、`ClientRestart`、`LoadMapPost`、控制台命令）。
- 换图时主动丢弃旧 Pawn 引用，避免对悬空对象判活。
- 心跳循环改为纯 Lua（不触碰任何游戏对象）。
- 验证要点：世界 ↔ 地下城反复进出不再崩溃；`SpellUnlocker.log` 可见 `LoadMapPost hook #n (player ref cleared)` 与 `apply to pawn ... (re-apply)`。

## v1.4.0 — 2026-10-24

**游戏内验证通过：全部咒语解锁、冷却不再阻挡连放。**

- `ForceSpellAvailable` 默认改为开启，并新增对 `WandTool::ActivateSpellTool` 的 `bImmediate` 改写，绕过冷却门禁。
- 修复按 Pawn 应用逻辑：菜单预览 Pawn 与真实角色 Pawn 分别应用，换场景 / 读档后自动重新应用。
- 修复 `SetCooldownRateScale` 空返回值的日志问题。
- 日志确认：`spells identified = 23`、`SetCooldownRateScale(1000.0) applied`、`ForceSpellAvailable ACTIVE`、`heartbeat #120` 无崩溃。

## v1.3.0 — 2026-10-24

- **移除默认路径中的逐咒语 `AdjustCooldown` 调用**。该调用在本游戏版本上触发 UE `Fatal Error`（launch4 实测）。
- 冷却改用已验证安全的组合：
  - `Biped_Player:SetCooldownRateScale(1000)`；
  - `GetCooldownPercent` / `GetCooldownPercentByName` 钩子返回 `0.0`；
  - 可选 `WandTool::IsSpellToolAvailable` 恒 `true`。
- 所有危险原生调用改为调用前先写日志、调用后写结果，崩溃时可定位。
- `CooldownRateScale` 默认从 50 提高到 1000。

## v1.2.0 — 2026-10-24

- 修复 `LoopAsync` 回调返回值：必须 `return false` 才继续循环（`return true` 会停止）。
- 新增 `ExecuteWithDelay` 自调度 ticker，作为第二心跳。
- 新增应用触发：`ClientRestart` 钩子、`NotifyOnNewObject`、多次延迟重试。
- 修复 `RegisterHook` 参数解析：`RemoteUnrealParam` 需要 `:get()` 取真实值。

## v1.1.0 — 2026-10-24

- 首个可运行版本：心跳、`ClientRestart` 注册、`SpellManagerBPInterface` 定位成功。
- 修复 `asString` 对 `FName` 包装类型的转换报错。

## v1.0.0 — 2026-10-24

- 初始版本：UE4SS Lua Mod 骨架、咒语解锁 / 冷却 / 知识卡 / 天赋 / 槽位功能开关。

---

## 发布包整理 — 2026-10-26

Mod 逻辑仍为 **v1.4.0**，未改动 `main.lua` 的游戏行为；本次只做发布打包与安装器加固：

- 新增中文 / 英文 README、快速说明、版本历史、第三方授权、MIT 许可、SHA256 校验值。
- 安装器：
  - 支持 Steam + Epic 自动定位，失败时可手动粘贴路径；
  - 游戏运行中时阻止安装 / 卸载；
  - 无写入权限时明确提示“以管理员身份运行”；
  - 覆盖升级时保留用户 `config.lua`；
  - **保留已有 `mods.txt` / `mods.json`，不会冲掉其他 UE4SS Mod 的登记**；
  - 重装时会把 `SpellUnlocker : 0` 自动改回 `: 1`。
- 卸载器：
  - 缺少安装标记时只移除本 Mod，**不会误删** 已有 `ue4ss\` / `dwmapi.dll`；
  - 同步清理 `mods.txt` / `mods.json`；
  - 安装前已有 UE4SS 时保留当前目录，避免误删其他 Mod，并提示备份位置；
  - 支持 `-KeepUE4SS`。
- 沙盒回归：首次安装、覆盖升级、保留配置、其他 UE4SS Mod 共存、无标记卸载、`-KeepUE4SS`、权限不足退出码，全部通过。
