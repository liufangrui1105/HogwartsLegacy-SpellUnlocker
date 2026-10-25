# SpellUnlocker — Hogwarts Legacy spell unlock & cooldown removal

> Unofficial fan mod. Not affiliated with Warner Bros. Games / Avalanche Software.
> This repository contains **no game assets**. MIT licensed (see [LICENSE](LICENSE)).

Runtime: [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) 3.x Lua. No exe/pak edits, one-click uninstall.

| | |
|---|---|
| Version | v1.7.0 |
| Works with | Hogwarts Legacy (Steam / Epic), Windows 10/11 x64, UE 4.27.2 |
| Tested on | Steam appid `990080`, buildid `20773316` (Denuvo) |

## Features

| Feature | Effect | Default |
|---|---|:---:|
| **UnlockAllSpells** | Every spell unlocked; no lessons / quests / knowledge cards required | on |
| **ZeroCooldown** | Cooldowns recover ~1000x faster, cooldown readouts clamped to 0 | on |
| **ForceSpellAvailable** | `WandTool::IsSpellToolAvailable` -> true, casting goes through the "immediate" path | on |
| **CompleteKnowledge** | Completes all ~386 knowledge cards (heavy side effects, writes save) | off |
| **ExpandSpellSlots** | 4 -> 8 spell slots per loadout (experimental, UI still draws 4) | off |
| **UnlockAllPerks** | Activates all talents + grants perk points (writes save) | off |

## Install

1. Download this repo (`Code` -> `Download ZIP`) and extract it.
2. Run `INSTALL.bat`:
   - it downloads the official UE4SS build on first run (~8 MB, needs internet);
   - it auto-detects Steam / Epic install paths (or asks for the game root);
   - it backs up any existing `dwmapi.dll` / `ue4ss\`.
3. Start the game **through Steam / Epic** (Denuvo).

Manual install and troubleshooting: see [README.md](README.md) (Chinese, full detail).

## Usage

Works automatically 1-2 s after loading, and re-applies on every level change / save load.
**F8** toggles the whole mod. Console (`F10` or `` ` ``): `spellunlock`, `spellunlock off`, `spellunlock dump`, ...

Edit `Win64\ue4ss\Mods\SpellUnlocker\Scripts\config.lua` to toggle individual features, then restart or press `Ctrl+R`.

## Stability

v1.7.0 fixes two crash causes found via minidump analysis (details in
[docs/崩溃分析与修复-2026-10-25.md](docs/崩溃分析与修复-2026-10-25.md)):

1. `FName` -> string conversion inside hook callbacks: UE4SS throws a C++ exception that Lua `pcall`
   cannot catch, unwinding through the hook trampoline and corrupting the stack.
2. Game-API calls (`FindFirstOf` / `StaticFindObject` / `IsValid`) from timer threads racing the
   game thread during level transitions (use-after-free inside UE4SS).

v1.7 runs all game-API work on game-thread callbacks only. Verified: repeated world <-> dungeon
transitions, save loads and combat casting without crashes.

## License

MIT for this project. UE4SS is a separate MIT project (see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)).
Game trademarks and assets belong to Warner Bros. Games / Avalanche Software.