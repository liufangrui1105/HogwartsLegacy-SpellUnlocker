--[[ ==========================================================================
  SpellUnlocker  ——  Hogwarts Legacy spell restriction unlocker
  Runtime: UE4SS 3.x Lua (Phoenix / UE 4.27.2)

  v1.7.0  (crash fix #2 — level-transition crashes)
    Evidence: 3 minidumps (18:57:01, 18:59:52, 19:16:27 UTC) all fault at
    the SAME address  UE4SS.dll + 0x6C328F  with 0xC0000005 reading a wild
    pointer. All three happened during a level transition / world load.
    v1.6 removed every FName->string conversion and still crashed, so the
    remaining trigger is this:

      * LoopAsync / ExecuteWithDelay run on a NON-game thread.
      * From those threads the mod called FindFirstOf("Biped_Player") and
        StaticFindObject(...) -> UE4SS walks GUObjectArray / the name tables
        while the game thread is swapping levels -> use-after-free inside
        UE4SS.dll -> ACCESS_VIOLATION.

    Fixes:
      1. ALL periodic native calls removed. No timers call game APIs anymore.
      2. Work runs only inside game-thread hook callbacks:
           - NotifyOnNewObject("/Script/Phoenix.Biped_Player")  (pawn spawn)
           - SpellManagerBPInterface:IsUnlocked  (first hit / every 500 hits,
             used only as a game-thread "tick" to capture the pawn)
      3. getPlayer() never searches the object array; it only returns the
         already-captured valid pawn.
      4. Hooks still only override return values (no param reads, no strings).
      5. Heartbeat ticker kept but it only touches Lua variables + print.

  Behaviour (see config.lua):
    UnlockAllSpells / ZeroCooldown / ForceSpellAvailable, per-pawn apply.
========================================================================== ]]

local MOD = "SpellUnlocker"
local VER = "1.7.0"

------------------------------------------------------------------------------
-- 0. logging
------------------------------------------------------------------------------
local logFile = nil
do
    local ok, f = pcall(io.open, "SpellUnlocker.log", "a")
    if ok and f then logFile = f end
end

local function nowStr()
    local ok, s = pcall(os.date, "%Y-%m-%d %H:%M:%S")
    return ok and s or "?"
end

local function log(tag, msg)
    local line = string.format("[%s] %s %s", MOD, tag, tostring(msg))
    print(line .. "\n")
    if logFile then
        pcall(function()
            logFile:write(string.format("%s %s\n", nowStr(), line))
            logFile:flush()
        end)
    end
end

local function info(m) log("INFO ", m) end
local function warn(m) log("WARN ", m) end

local function safe(label, fn, ...)
    local ok, a = pcall(fn, ...)
    if not ok then
        warn(string.format("%s failed: %s", label, tostring(a)))
        return nil
    end
    return a
end

info(string.format("v%s loading ...", VER))
do
    local ok, maj, min, hot = pcall(function() return UE4SS.GetVersion() end)
    if ok then info(string.format("UE4SS version: %s.%s.%s", tostring(maj), tostring(min), tostring(hot))) end
end

------------------------------------------------------------------------------
-- 1. config
------------------------------------------------------------------------------
local DEFAULTS = {
    Enabled = true,
    Features = {
        UnlockAllSpells     = true,
        CompleteKnowledge   = false,
        ZeroCooldown        = true,
        ForceSpellAvailable = true,
        ExpandSpellSlots    = false,
        UnlockAllPerks      = false,
    },
    SlotsPerLoadout          = 8,
    NumLoadouts              = 3,
    CooldownRateScale        = 1000.0,
    ProbeDump                = true,
    ToggleHotkey             = "F8",
    ImmediateCast            = true,
    HardClearCooldowns       = false,
    ClearCooldownsByCategory = false,
    CaptureOnIsUnlocked      = true,   -- 用 IsUnlocked 命中作为"游戏线程 tick"捕获 Pawn
}

local cfg
do
    local ok, loaded = pcall(require, "config")
    if ok and type(loaded) == "table" then
        cfg = loaded
        info("config.lua loaded")
    else
        cfg = {}
        warn("config.lua load failed, using defaults: " .. tostring(loaded))
    end
    for k, v in pairs(DEFAULTS) do
        if cfg[k] == nil then cfg[k] = v end
    end
    if type(cfg.Features) ~= "table" then cfg.Features = {} end
    for k, v in pairs(DEFAULTS.Features) do
        if cfg.Features[k] == nil then cfg.Features[k] = v end
    end
end

local function feature(name)
    return cfg.Enabled ~= false and cfg.Features[name] == true
end

------------------------------------------------------------------------------
-- 2. state
------------------------------------------------------------------------------
local state = {
    player         = nil,
    appliedFor     = nil,
    firstApplyDone = false,
    hits           = { IsUnlocked = 0, CooldownPct = 0, SpellAvailable = 0, Cast = 0, Restart = 0, Apply = 0 },
    heartbeats     = 0,
}

------------------------------------------------------------------------------
-- 3. tiny helpers (no object-array searching here!)
------------------------------------------------------------------------------
local function valid(obj)
    if obj == nil then return false end
    local ok, v = pcall(function() return obj:IsValid() end)
    return ok and v == true
end

local function fullName(obj)
    local ok, s = pcall(function() return obj:GetFullName() end)
    return ok and s or "<invalid>"
end

local function findCDO(className)
    local ok, obj = pcall(StaticFindObject, "/Script/Phoenix.Default__" .. className)
    if ok and valid(obj) then return obj end
    return nil
end

------------------------------------------------------------------------------
-- 4. spell interface
------------------------------------------------------------------------------
local spellIface = nil

local function getSpellIface()
    if valid(spellIface) then return spellIface end
    spellIface = findCDO("SpellManagerBPInterface")
    if spellIface then
        info("SpellManagerBPInterface found")
    else
        warn("SpellManagerBPInterface not found")
    end
    return spellIface
end

local function spellCounts()
    local iface = getSpellIface()
    if not iface then return nil end
    return {
        all       = safe("GetAvailableSpellCount(true)",  function() return iface:GetAvailableSpellCount(true)  end),
        unlocked  = safe("GetAvailableSpellCount(false)", function() return iface:GetAvailableSpellCount(false) end),
        perLoadout= safe("read SpellsPerLoadout", function() return iface.SpellsPerLoadout end),
        loadouts  = safe("read NumLoadouts",      function() return iface.NumLoadouts end),
    }
end

------------------------------------------------------------------------------
-- 5. apply (called ONLY from game-thread callbacks)
------------------------------------------------------------------------------
local function pawnKey(player)
    local ok, addr = pcall(function() return player:GetAddress() end)
    if ok and addr then return tostring(addr) end
    return fullName(player)
end

local function probeCounts()
    info("---- probe (counts only) ----")
    info(string.format("hook hits: IsUnlocked=%d CooldownPct=%d SpellAvailable=%d Cast=%d restarts=%d apply=%d",
        state.hits.IsUnlocked, state.hits.CooldownPct, state.hits.SpellAvailable,
        state.hits.Cast, state.hits.Restart, state.hits.Apply))
    local c = spellCounts()
    if c then
        info(string.format("spells: all=%s unlocked=%s / perLoadout=%s loadouts=%s",
            tostring(c.all), tostring(c.unlocked), tostring(c.perLoadout), tostring(c.loadouts)))
    end
    info("---- probe end ----")
end

local function expandSpellSlots()
    if not feature("ExpandSpellSlots") then return end
    local iface = getSpellIface()
    if not iface then return end
    safe("set SpellsPerLoadout", function() iface.SpellsPerLoadout = cfg.SlotsPerLoadout end)
    safe("set NumLoadouts",     function() iface.NumLoadouts     = cfg.NumLoadouts end)
    info("spell slots expanded (experimental)")
end

local function completeKnowledge()
    if not feature("CompleteKnowledge") then return end
    local km = findCDO("KnowledgeManager")
    if not km then warn("KnowledgeManager not found"); return end
    local real = safe("KnowledgeManager.Get", function() return km:Get() end)
    if valid(real) then km = real end
    safe("CompleteAllKnowledgeCards", function() km:CompleteAllKnowledgeCards() end)
    info("CompleteAllKnowledgeCards() called")
end

local function unlockAllPerks()
    if not feature("UnlockAllPerks") then return end
    local pt = findCDO("PerksTree")
    if not pt then warn("PerksTree not found"); return end
    local real = safe("PerksTree.Get", function() return pt:Get() end)
    if valid(real) then pt = real end
    safe("UpdatePerkPoints", function() pt:UpdatePerkPoints(999) end)
    safe("PerkActivateAll",  function() pt:PerkActivateAll() end)
    info("perks unlocked (experimental)")
end

-- 只在游戏线程调用（hook 回调 / NotifyOnNewObject / 控制台）
local function applyPawn(player)
    if not player or not valid(player) then return end
    local key = pawnKey(player)
    if state.appliedFor == key then return end
    local firstTime = not state.firstApplyDone
    state.appliedFor = key
    state.hits.Apply = state.hits.Apply + 1
    info(string.format("apply to pawn %s (%s)", key, firstTime and "first" or "re-apply"))

    if feature("ZeroCooldown") then
        local ok, e = pcall(function() player:SetCooldownRateScale(cfg.CooldownRateScale) end)
        if ok then
            info(string.format("SetCooldownRateScale(%.1f) applied", cfg.CooldownRateScale))
        else
            warn("SetCooldownRateScale failed: " .. tostring(e))
        end
    end

    if firstTime then
        state.firstApplyDone = true
        info("=========== first apply ===========")
        pcall(probeCounts)
        pcall(expandSpellSlots)
        pcall(completeKnowledge)
        pcall(unlockAllPerks)
        info("=========== first apply done ===========")
    end
end

-- 只在游戏线程调用：捕获 Pawn（用 FindFirstOf 也安全，因为这里是游戏线程）
local function capturePlayer()
    if valid(state.player) then return state.player end
    local ok, p = pcall(FindFirstOf, "Biped_Player")
    if ok and valid(p) then
        state.player = p
        info("player captured -> " .. fullName(p))
    end
    return state.player
end

local function gameThreadTick()
    local p = capturePlayer()
    if p then
        local ok = pcall(applyPawn, p)
        if not ok then warn("applyPawn failed") end
    end
end

------------------------------------------------------------------------------
-- 6. hooks —— 只覆盖返回值；IsUnlocked 顺带当作游戏线程 tick
------------------------------------------------------------------------------
local function hookUF(label, path, pre)
    local ok, e = pcall(RegisterHook, path, pre)
    if ok then
        info("hook " .. label .. " registered")
        return true
    end
    warn(string.format("hook %s failed: %s", label, tostring(e)))
    return false
end

if feature("UnlockAllSpells") then
    hookUF("IsUnlocked", "/Script/Phoenix.SpellManagerBPInterface:IsUnlocked",
        function(self, a, b)
            state.hits.IsUnlocked = state.hits.IsUnlocked + 1
            if cfg.CaptureOnIsUnlocked then
                local n = state.hits.IsUnlocked
                if n == 1 or n == 50 or (n % 500 == 0) then
                    pcall(gameThreadTick)   -- 游戏线程，安全
                end
            end
            return true
        end)
end

if feature("ZeroCooldown") then
    hookUF("GetCooldownPercent", "/Script/Phoenix.Biped_Player:GetCooldownPercent",
        function(self, a, b)
            state.hits.CooldownPct = state.hits.CooldownPct + 1
            return 0.0
        end)
    hookUF("GetCooldownPercentByName", "/Script/Phoenix.Biped_Player:GetCooldownPercentByName",
        function(self, a, b)
            state.hits.CooldownPct = state.hits.CooldownPct + 1
            return 0.0
        end)
end

if feature("ForceSpellAvailable") then
    hookUF("IsSpellToolAvailable", "/Script/Phoenix.WandTool:IsSpellToolAvailable",
        function(self, a, b)
            state.hits.SpellAvailable = state.hits.SpellAvailable + 1
            return true
        end)
    hookUF("ActivateSpellTool", "/Script/Phoenix.WandTool:ActivateSpellTool",
        function(self, record, bImmediate)
            state.hits.Cast = state.hits.Cast + 1
            if cfg.ImmediateCast and bImmediate ~= nil then
                pcall(function() bImmediate:set(true) end)
            end
            return nil
        end)
end

-- 玩家控制器重启：只记日志（不在这里做任何原生调用/不排定时器）
pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self, newPawn)
        state.hits.Restart = state.hits.Restart + 1
        info(string.format("ClientRestart #%d", state.hits.Restart))
        -- 换角色/换图时旧的 Pawn 可能已被销毁：先丢掉引用，避免对悬空对象做 IsValid
        state.player = nil
        pcall(gameThreadTick)
    end)
end)

-- 新 Pawn 生成（游戏线程）：这是最主要的应用时机
pcall(function()
    NotifyOnNewObject("/Script/Phoenix.Biped_Player", function(obj)
        if valid(obj) then
            state.player = obj
            info("pawn spawned -> " .. fullName(obj))
            pcall(applyPawn, obj)
        end
    end)
end)

-- 地图加载日志（只记日志 + 丢弃旧 Pawn 引用，无其他副作用）
pcall(function()
    RegisterLoadMapPostHook(function(engine, worldContext, url, pendingNetGame, error)
        state.hits.Restart = state.hits.Restart + 1
        state.player = nil          -- 旧关卡对象可能已销毁
        info(string.format("LoadMapPost hook #%d (player ref cleared)", state.hits.Restart))
    end)
end)

------------------------------------------------------------------------------
-- 7. heartbeat：只动 Lua 变量 + 打日志，不调用任何游戏 API
------------------------------------------------------------------------------
local okLoop = pcall(function()
    LoopAsync(5000, function()
        state.heartbeats = state.heartbeats + 1
        if state.heartbeats <= 3 or state.heartbeats % 60 == 0 then
            info(string.format("heartbeat #%d appliedFor=%s player=%s firstApplyDone=%s",
                state.heartbeats, tostring(state.appliedFor), tostring(valid(state.player)),
                tostring(state.firstApplyDone)))
        end
        return false
    end)
end)
if okLoop then info("heartbeat started (Lua only, no game API)") else warn("LoopAsync unavailable") end

------------------------------------------------------------------------------
-- 8. hotkey
------------------------------------------------------------------------------
if cfg.ToggleHotkey and cfg.ToggleHotkey ~= "" then
    pcall(function()
        local keyEnum = Key and Key[cfg.ToggleHotkey]
        if keyEnum == nil then
            warn("hotkey " .. tostring(cfg.ToggleHotkey) .. " unresolved")
            return
        end
        RegisterKeyBind(keyEnum, function()
            cfg.Enabled = not cfg.Enabled
            info("hotkey toggle: master switch = " .. tostring(cfg.Enabled))
        end)
        info("hotkey " .. cfg.ToggleHotkey .. " -> toggle master switch")
    end)
end

------------------------------------------------------------------------------
-- 9. console command
------------------------------------------------------------------------------
local function toggle(name)
    cfg.Features[name] = not cfg.Features[name]
    info(string.format("toggle %s = %s", name, tostring(cfg.Features[name])))
end

pcall(function()
    RegisterConsoleCommandHandler("spellunlock", function(Cmd, Params, Ar)
        local sub = "status"
        if type(Params) == "table" then
            for i = 1, #Params do
                if type(Params[i]) == "string" and Params[i]:lower() ~= "spellunlock" then
                    sub = Params[i]:lower()
                    break
                end
            end
        end

        if sub == "on" then
            cfg.Enabled = true;  info("master switch = true")
        elseif sub == "off" then
            cfg.Enabled = false; info("master switch = false")
        elseif sub == "apply" then
            state.appliedFor = nil
            gameThreadTick()
        elseif sub == "unlock" then
            toggle("UnlockAllSpells")
        elseif sub == "cooldown" then
            toggle("ZeroCooldown")
        elseif sub == "knowledge" then
            cfg.Features.CompleteKnowledge = true
            completeKnowledge()
        elseif sub == "slots" then
            cfg.Features.ExpandSpellSlots = true
            expandSpellSlots()
        elseif sub == "perks" then
            cfg.Features.UnlockAllPerks = true
            unlockAllPerks()
        elseif sub == "dump" then
            probeCounts()
        else
            info("---- SpellUnlocker status ----")
            info("master=" .. tostring(cfg.Enabled) .. " firstApplyDone=" .. tostring(state.firstApplyDone))
            for k, v in pairs(cfg.Features) do info("  " .. k .. " = " .. tostring(v)) end
            info(string.format("hook hits: IsUnlocked=%d CooldownPct=%d SpellAvailable=%d Cast=%d restarts=%d apply=%d",
                state.hits.IsUnlocked, state.hits.CooldownPct, state.hits.SpellAvailable,
                state.hits.Cast, state.hits.Restart, state.hits.Apply))
            info("usage: spellunlock on|off|apply|unlock|cooldown|knowledge|slots|perks|dump")
        end
        return true
    end)
    info("console command spellunlock registered")
end)

info(string.format("v%s loaded", VER))
