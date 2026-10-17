-- Doodle Warriors: Wallflower's Summon Warrior mechanic (see scripts/screens/
-- wallflowersummonscreen.lua for the picker UI, and the "SummonWarrior" mod RPC handler in
-- modmain.lua for the entry point that calls into this module).
--
-- Rather than new prefab files for the 9 basic replicas, each one IS the real vanilla creature
-- (SpawnPrefab), converted into a Wallflower-owned combat ally at spawn time: swap its "hostile"
-- tag for "companion", give it the shared follow-and-fight brain (see
-- brains/wallflower_doodlebrain.lua) in place of its usual AI, and set Wallflower as its follower
-- leader. The three achievement warriors (Treevor/Berrtha/Bouuldozer) go through the same
-- conversion but on top of borrowed Treeguard/Gobbler/Clockwork Rook assets (real prefab names
-- "leif"/"perd"/"rook" -- "Treeguard" and "Gobbler" are just their in-game display names) with
-- their own custom stats/name/lifetime layered on top -- see ACHIEVEMENT_STATS below. All of this
-- is placeholder art per the mod's own conventions until the user has real Doodle Warrior art to
-- swap in.

local DoodleBrain = require "brains/wallflower_doodlebrain"

local M = {}

-- Bee/frog/penguin summon in small swarms (still counts as a single "unit" for cap-tracking --
-- see IsAtCap below), matching the user's own answer on how these should work.
local REPLICA_BATCH_SIZE = { bee = 5, frog = 3, penguin = 5 }

M.REPLICA_KINDS = {
    "bee", "pigman", "frog", "merm", "beefalo", "bunnyman", "catcoon", "penguin", "lightninggoat",
}

local REPLICA_SET = {}
for _, kind in ipairs(M.REPLICA_KINDS) do
    REPLICA_SET[kind] = true
end

M.ACHIEVEMENT_KINDS = { "treevor", "berrtha", "bouuldozer" }

-- Inspiration cost per summon -- placeholder numbers in the same spirit as the Conjure Item cost
-- table in components/inspiration.lua: meant to be tuned by playtesting, not exact on the first
-- pass. Basic replicas are cheap, repeatable utility; achievement warriors are a bigger spend for
-- a much stronger, capped, timed payoff.
M.SUMMON_COST = {
    bee = 10, pigman = 15, frog = 10, merm = 15, beefalo = 25,
    bunnyman = 15, catcoon = 15, penguin = 10, lightninggoat = 20,
    treevor = 30, berrtha = 20, bouuldozer = 45,
}

-- Per the user's explicit answer: 2 Treevors/15s, 3 Berrthas/30s, 1 Bouuldozer/10s. Basic
-- replicas have no entry here -- they're capped at "1 unit of this type" instead (see IsAtCap).
local WARRIOR_CAP = { treevor = 2, berrtha = 3, bouuldozer = 1 }
local WARRIOR_LIFETIME = { treevor = 15, berrtha = 30, bouuldozer = 10 }

local ACHIEVEMENT_PREFAB = { treevor = "leif", berrtha = "perd", bouuldozer = "rook" }

-- Stats deliberately don't reuse the borrowed creature's own defaults (unlike the 9 basic
-- replicas, which the user explicitly wants at normal-variant stats) -- these three are
-- purpose-built combat allies using the user's own numbers.
local ACHIEVEMENT_STATS = {
    treevor = { health = 300, damage = 50 },
    berrtha = { health = 100, damage = 20 },
    bouuldozer = { health = 500, damage = 60, attackperiod = 4 }, -- slower attack rate than default
}

local BERRTHA_AURA_RADIUS = 12
local BERRTHA_AURA_CHECK_PERIOD = 2
local BERRTHA_REGEN_AMOUNT = 1
local BERRTHA_REGEN_PERIOD = 2
local BERRTHA_REGEN_SOURCE = "wallflower_berrtha"

--------------------------------------------------------------------------------------------
-- Active-summon bookkeeping: server-only, per-owner, runtime-only (not persisted). A Doodle
-- Warrior that survives a save/reload would come back as a plain, un-owned creature next
-- session, orphaned from cap tracking -- an acceptable simplification for a combat-only summon
-- that's only ever meant to last a single play session at most.
--------------------------------------------------------------------------------------------

local function GetActiveTable(owner)
    if owner.wallflower_activewarriors == nil then
        owner.wallflower_activewarriors = {}
    end
    return owner.wallflower_activewarriors
end

local function PruneAndCount(owner, kind)
    local list = GetActiveTable(owner)[kind]
    if list == nil then
        return 0
    end

    for i = #list, 1, -1 do
        if not list[i]:IsValid() then
            table.remove(list, i)
        end
    end

    return #list
end

function M.IsAtCap(owner, kind)
    local count = PruneAndCount(owner, kind)
    local cap = WARRIOR_CAP[kind]
    if cap ~= nil then
        return count >= cap
    end
    return count > 0 -- Basic replicas: one "unit" (i.e. one summon's worth) active at a time.
end

--------------------------------------------------------------------------------------------
-- Berrtha's non-stacking passive regen aura: "while nearby" has to be re-evaluated continuously
-- (a Berrtha can wander off and come back), so this is a periodic proximity check rather than a
-- one-shot flag -- started lazily the first time a Berrtha is summoned, and self-cancels once no
-- Berrthas remain (bounded anyway by Berrtha's own 30s lifetime).
--------------------------------------------------------------------------------------------

function M._CheckBerrthaAura(owner)
    if owner.components.health == nil then
        return
    end

    local list = GetActiveTable(owner).berrtha
    local nearby = false
    if list ~= nil then
        for _, inst in ipairs(list) do
            if inst:IsValid() and inst:IsNear(owner, BERRTHA_AURA_RADIUS) then
                nearby = true
                break
            end
        end
    end

    if nearby then
        owner.components.health:AddRegenSource(BERRTHA_REGEN_SOURCE, BERRTHA_REGEN_AMOUNT, BERRTHA_REGEN_PERIOD)
    else
        owner.components.health:RemoveRegenSource(BERRTHA_REGEN_SOURCE)

        if PruneAndCount(owner, "berrtha") == 0 and owner._wallflower_berrthaauratask ~= nil then
            owner._wallflower_berrthaauratask:Cancel()
            owner._wallflower_berrthaauratask = nil
        end
    end
end

local function StartBerrthaAuraTask(owner)
    if owner._wallflower_berrthaauratask == nil then
        owner._wallflower_berrthaauratask = owner:DoPeriodicTask(BERRTHA_AURA_CHECK_PERIOD, M._CheckBerrthaAura)
    end
end

--------------------------------------------------------------------------------------------
-- Shared conversion: turn a freshly-spawned vanilla creature into a Wallflower-owned ally.
--------------------------------------------------------------------------------------------

local function RegisterWarrior(owner, kind, inst)
    local active = GetActiveTable(owner)
    if active[kind] == nil then
        active[kind] = {}
    end
    table.insert(active[kind], inst)

    inst:ListenForEvent("onremove", function()
        PruneAndCount(owner, kind)
        if kind == "berrtha" then
            M._CheckBerrthaAura(owner)
        end
    end)
end

-- inst.nameoverride is a plain Lua field -- server-only by default, since ConvertToDoodleWarrior
-- only ever runs from server-side code (the SummonWarrior RPC handler, or the save/load restore
-- path below). That's invisible to any OTHER client's own copy of the entity (a remote player,
-- not the host) unless it's mirrored over a real net var -- see the "wallflower.doodlename" net_string
-- declared unconditionally (both sides) in M.SetupPersistence below. This is the only place that
-- should ever assign inst.nameoverride for a warrior, so the net var and the field can't drift.
local function SetWarriorName(inst, value)
    inst.nameoverride = value
    if inst._wallflower_doodlename ~= nil then
        inst._wallflower_doodlename:set(value)
    end
end

local function ConvertToDoodleWarrior(inst, owner, kind)
    inst:AddTag("wallflower_doodlewarrior")
    inst:AddTag("companion")
    if inst:HasTag("hostile") then
        inst:RemoveTag("hostile")
    end

    -- Never drop the borrowed creature's own normal loot (frog legs, meat, pelts, gears, ...) --
    -- a summoned ally dying shouldn't hand out farmable resources. Covers every way a creature
    -- might have configured its drops (guaranteed loot, a shared chance-loot table by name, or a
    -- custom setup function), not just the common one.
    if inst.components.lootdropper ~= nil then
        inst.components.lootdropper:SetLoot({})
        inst.components.lootdropper:SetChanceLootTable(nil)
        inst.components.lootdropper:SetLootSetupFn(nil)
    end

    if inst.components.follower == nil then
        inst:AddComponent("follower")
    end
    inst.components.follower:SetLeader(owner)
    -- Same protection Abigail uses: without this, an accidental AOE hit from Wallflower herself
    -- would make her own warrior drop her as its leader mid-fight.
    inst.components.follower:KeepLeaderOnAttacked()

    inst:SetBrain(DoodleBrain)
    -- Cancels any movement the creature's own original brain might have already queued into the
    -- locomotor in the instant before it existed as a Doodle Warrior (e.g. a borrowed creature's
    -- own skittish/flee behavior), so it never takes a stray step away from Wallflower on spawn.
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:Stop()
    end

    -- Many borrowed creature prefabs wire their OWN "attacked" listener straight to
    -- combat:SetTarget(attacker), completely independent of the brain and with no ally-awareness
    -- at all (confirmed directly in pigman.lua's OnAttacked, merm.lua's equivalent, etc.) --
    -- replacing the brain above does nothing to stop that, and it's how a Pigman Doodle and a
    -- Merm Doodle sharing the same owner would still end up fighting each other over incidental
    -- splash/cleave damage despite the IsAlly checks already in OnOwnerCombatEvent/FindHostile
    -- below. Confirmed via combat.lua that self.target is only ever mutated inside SetTarget's
    -- own DropTarget/EngageTarget calls, so wrapping SetTarget itself -- on just this instance,
    -- not the shared Combat class -- is the one choke point every targeting path funnels
    -- through, vanilla's own listeners included.
    local orig_settarget = inst.components.combat.SetTarget
    inst.components.combat.SetTarget = function(self, target, ...)
        if target ~= nil and self:IsAlly(target) then
            return
        end
        return orig_settarget(self, target, ...)
    end

    -- Aggro whatever Wallflower hits, or whatever hits Wallflower, or whatever hits the warrior
    -- itself (self-defense) -- plus actual monsters on sight (see FindHostile in
    -- wallflower_doodlebrain.lua) -- and nothing else.
    --
    -- IMPORTANT: EntityScript:PushEvent_Internal always calls the listener as fn(source, data) --
    -- the event's SOURCE entity, never the listening entity (confirmed straight from
    -- entityscript.lua). For the two owner-sourced listens below that means the callback's first
    -- argument would be Wallflower herself, not this warrior -- so this closure captures "inst"
    -- (the warrior) directly from the enclosing scope instead of trying to read it off the
    -- callback arguments, and ignores whichever entity actually fired the event.
    local function OnOwnerCombatEvent(_, data)
        local target = data ~= nil and (data.attacker or data.target) or nil
        if target ~= nil and target:IsValid() and inst.components.combat ~= nil
            and inst.components.combat:CanTarget(target)
            -- True for any two entities sharing a leader (see combat_replica.lua's CanBeAlly) --
            -- stops incidental splash/cleave damage between two of Wallflower's own warriors
            -- (e.g. a Pigman Doodle and a Merm Doodle both piling onto the same enemy) from
            -- turning into permanent warrior-on-warrior retaliation. CanTarget alone does NOT
            -- exclude allies, only genuinely invalid targets (dead, invisible, etc).
            and not inst.components.combat:IsAlly(target) then
            inst.components.combat:SetTarget(target)
        end
    end

    inst:ListenForEvent("attacked", OnOwnerCombatEvent, owner)
    inst:ListenForEvent("onattackother", OnOwnerCombatEvent, owner)
    inst:ListenForEvent("attacked", OnOwnerCombatEvent) -- self-defense: source defaults to inst

    -- STRINGS.NAMES.WALLFLOWER_DOODLE_<KIND> is set in modmain.lua. Achievement warriors
    -- (Treevor/Berrtha/Bouuldozer) overwrite this with their own plain name right after this
    -- function returns -- see SummonAchievement below.
    SetWarriorName(inst, "wallflower_doodle_" .. kind)

    inst.wallflower_summonkind = kind
    inst.wallflower_owner = owner

    RegisterWarrior(owner, kind, inst)
end

local function SpawnNear(prefab, owner, index)
    local inst = SpawnPrefab(prefab)
    if inst == nil then
        return nil
    end

    local x, y, z = owner.Transform:GetWorldPosition()
    local angle = math.random() * 2 * PI
    local offset = FindWalkableOffset(Vector3(x, y, z), angle, 2 + (index or 1), 8, true)
    if offset ~= nil then
        inst.Transform:SetPosition(x + offset.x, y, z + offset.z)
    else
        inst.Transform:SetPosition(x, y, z)
    end

    return inst
end

--------------------------------------------------------------------------------------------
-- Public entry points, called from the "SummonWarrior" RPC handler in modmain.lua. Neither one
-- re-checks unlock/cost/cap -- the RPC handler validates all of that server-side first, same
-- discipline as the existing "CastSpell" handler for Conjure Item.
--------------------------------------------------------------------------------------------

local function SummonReplica(owner, kind)
    local count = REPLICA_BATCH_SIZE[kind] or 1
    for i = 1, count do
        local inst = SpawnNear(kind, owner, i)
        if inst ~= nil then
            ConvertToDoodleWarrior(inst, owner, kind)
            inst.components.follower.neverexpire = true
        end
    end
end

-- Everything about an achievement warrior beyond the shared ConvertToDoodleWarrior treatment --
-- factored out so the save/load restore path (below) can redo exactly the same setup on a
-- reloaded entity, not just a freshly-summoned one. lifetime_override, when given (the restore
-- path), is however many seconds were left rather than the full duration.
local function SetupAchievementExtras(inst, owner, kind, lifetime_override)
    -- Berrtha should only borrow the Gobbler's assets (see the big comment at the top of this
    -- file), not the rest of what makes a Gobbler a Gobbler -- Perd's own eater/homeseeker/
    -- sleeper components drive its normal wandering-off-to-eat-and-nest-and-sleep routine
    -- independently of the brain (which is already fully replaced by ConvertToDoodleWarrior),
    -- and were making her act like a wild bird instead of a standing combat ally.
    if kind == "berrtha" then
        if inst.components.eater ~= nil then
            inst:RemoveComponent("eater")
        end
        if inst.components.homeseeker ~= nil then
            inst:RemoveComponent("homeseeker")
        end
        if inst.components.sleeper ~= nil then
            inst:RemoveComponent("sleeper")
        end
    end

    local stats = ACHIEVEMENT_STATS[kind]
    if stats ~= nil then
        -- Preserve current health% across the max-health override -- SetMaxHealth also resets
        -- currenthealth to the new max, which is correct for a brand new summon (percent is
        -- already 1) but would otherwise silently full-heal a reloaded warrior back to max,
        -- discarding whatever damage it had taken before the save.
        local percent = inst.components.health ~= nil and inst.components.health:GetPercent() or 1
        if stats.health ~= nil and inst.components.health ~= nil then
            inst.components.health:SetMaxHealth(stats.health)
            inst.components.health:SetPercent(percent)
        end
        if stats.damage ~= nil and inst.components.combat ~= nil then
            inst.components.combat:SetDefaultDamage(stats.damage)
        end
        if stats.attackperiod ~= nil and inst.components.combat ~= nil then
            inst.components.combat:SetAttackPeriod(stats.attackperiod)
        end
    end

    -- STRINGS.NAMES.WALLFLOWER_TREEVOR/BERRTHA/BOUULDOZER are set in modmain.lua.
    SetWarriorName(inst, "wallflower_" .. kind)

    local lifetime = lifetime_override or WARRIOR_LIFETIME[kind]
    if lifetime ~= nil then
        -- Session-local deadline used only to compute remaining time if this gets saved again
        -- (see SaveDoodleWarrior below) -- GetTime() itself doesn't carry meaning across a
        -- server restart, only differences taken within the same session do.
        inst.wallflower_expiretime = GetTime() + lifetime
        inst:DoTaskInTime(math.max(0, lifetime), function()
            if inst:IsValid() then
                inst:Remove()
            end
        end)
    end

    if kind == "berrtha" then
        StartBerrthaAuraTask(owner)
        M._CheckBerrthaAura(owner)
    end
end

local function SummonAchievement(owner, kind)
    local prefab = ACHIEVEMENT_PREFAB[kind]
    local inst = prefab ~= nil and SpawnNear(prefab, owner, 1) or nil
    if inst == nil then
        return
    end

    ConvertToDoodleWarrior(inst, owner, kind)
    SetupAchievementExtras(inst, owner, kind, nil)
end

function M.Summon(owner, kind)
    if REPLICA_SET[kind] then
        SummonReplica(owner, kind)
    elseif ACHIEVEMENT_PREFAB[kind] ~= nil then
        SummonAchievement(owner, kind)
    end
end

-- The "despawn when I no longer need them" feature -- removes every currently-active Doodle
-- Warrior of every kind. Snapshots each kind's list before removing anything: inst:Remove()
-- synchronously fires the "onremove" listener registered in RegisterWarrior, which prunes that
-- same live list -- iterating the live list directly here would mutate it out from under itself.
function M.DismissAll(owner)
    for _, list in pairs(GetActiveTable(owner)) do
        local snapshot = {}
        for _, inst in ipairs(list) do
            table.insert(snapshot, inst)
        end

        for _, inst in ipairs(snapshot) do
            if inst:IsValid() then
                inst:Remove()
            end
        end
    end
end

--------------------------------------------------------------------------------------------
-- Save/load persistence. Reusing a vanilla creature prefab wholesale (rather than a new prefab
-- of our own) means none of the runtime-only conversion above -- tags, brain, follower leader,
-- combat listeners, cleared loot, nameoverride -- is remembered across a save/reload on its own:
-- the entity just reconstructs as a plain, unowned, attackable wild creature again (this is
-- exactly the bug the user reported: warriors "turning into their normal counterparts" after
-- restarting the server). M.SetupPersistence is hooked onto each of the 12 borrowed prefabs via
-- AddPrefabPostInit in modmain.lua, and:
--   - on save, if the entity is currently a Doodle Warrior, remembers its kind and its owner's
--     USERID (not GUID -- see below) plus, for the timed achievement warriors, how much of
--     their lifetime was left;
--   - on load, once the owning player is actually back in the world, redoes the full
--     conversion from scratch.
--
-- USERID rather than GUID specifically because this can't safely lean on the usual
-- OnLoadPostPass + newents GUID-remapping pattern (the one perd.lua itself already uses for
-- linking back to its home bush) -- that only reliably resolves entities loaded in the same
-- world-entity pass, and a reconnecting PLAYER's entity comes back via a separate session-resume
-- flow, not guaranteed to be present in newents yet. userid is stable across reconnects/restarts
-- regardless of load ordering, and is exactly what the "follower" component's own built-in
-- player-reconnect support (CachePlayerLeader/OnPlayerJoined) is built on.
--------------------------------------------------------------------------------------------

local function FindPlayerByUserid(userid)
    for _, player in ipairs(AllPlayers) do
        if player.userid == userid then
            return player
        end
    end
    return nil
end

local function RestoreWarrior(inst, owner, kind, lifetimeremaining)
    if not inst:IsValid() or owner == nil or not owner:IsValid() then
        return
    end

    ConvertToDoodleWarrior(inst, owner, kind)

    if REPLICA_SET[kind] then
        inst.components.follower.neverexpire = true
    elseif ACHIEVEMENT_PREFAB[kind] ~= nil then
        SetupAchievementExtras(inst, owner, kind, lifetimeremaining)
    end
end

-- The owning player hasn't rejoined yet (or hasn't finished spawning in) -- wait for them,
-- mirroring the same "ms_playerjoined"/"ms_newplayerspawned" pattern follower.lua itself uses
-- for reconnecting a saved leader relationship.
local function WaitForOwnerThenRestore(inst, userid, kind, lifetimeremaining)
    local OnPlayerAvailable
    OnPlayerAvailable = function(world, player)
        if player.userid == userid then
            inst:RemoveEventCallback("ms_playerjoined", OnPlayerAvailable, TheWorld)
            inst:RemoveEventCallback("ms_newplayerspawned", OnPlayerAvailable, TheWorld)
            RestoreWarrior(inst, player, kind, lifetimeremaining)
        end
    end

    inst:ListenForEvent("ms_playerjoined", OnPlayerAvailable, TheWorld)
    inst:ListenForEvent("ms_newplayerspawned", OnPlayerAvailable, TheWorld)
end

local function SaveDoodleWarrior(inst, data)
    if inst.wallflower_summonkind == nil or inst.wallflower_owner == nil
        or not inst.wallflower_owner:IsValid() or inst.wallflower_owner.userid == nil then
        return
    end

    data.wallflower_summonkind = inst.wallflower_summonkind
    data.wallflower_summonowner_userid = inst.wallflower_owner.userid

    if inst.wallflower_expiretime ~= nil then
        data.wallflower_lifetimeremaining = math.max(0, inst.wallflower_expiretime - GetTime())
    end
end

local function LoadDoodleWarrior(inst, data)
    if data == nil or data.wallflower_summonkind == nil or data.wallflower_summonowner_userid == nil then
        return
    end

    local owner = FindPlayerByUserid(data.wallflower_summonowner_userid)
    if owner ~= nil then
        RestoreWarrior(inst, owner, data.wallflower_summonkind, data.wallflower_lifetimeremaining)
    else
        WaitForOwnerThenRestore(inst, data.wallflower_summonowner_userid, data.wallflower_summonkind, data.wallflower_lifetimeremaining)
    end
end

-- Every prefab name that might need this: the 9 replicas (kind == prefab name for those) plus
-- the 3 borrowed achievement-warrior prefabs. modmain.lua loops over this to wire up
-- AddPrefabPostInit(prefab, DoodleWarriors.SetupPersistence) for each one.
M.ALL_PREFABS = { "leif", "perd", "rook" }
for _, kind in ipairs(M.REPLICA_KINDS) do
    table.insert(M.ALL_PREFABS, kind)
end

-- Wraps (rather than overwrites) OnSave/OnLoad, since these are common vanilla creature prefabs
-- -- e.g. perd.lua sets its own OnSave/OnLoadPostPass during the Year of the Gobbler event, and
-- every wild instance of these 12 prefabs in the world (not just our own summoned warriors)
-- passes through here too. SaveDoodleWarrior/LoadDoodleWarrior no-op immediately for anything
-- that was never a Doodle Warrior in the first place (wallflower_summonkind == nil), so the
-- added cost for the thousands of ordinary wild bees/pigs/etc in a world is one field check.
function M.SetupPersistence(inst)
    -- Display name has to reach every client, including remote players who never run any of the
    -- server-only conversion code (the SummonWarrior RPC handler, or the load-restore path)
    -- that decides a Doodle Warrior's name in the first place -- see SetWarriorName above. This
    -- net_string is declared unconditionally so every machine's own copy of the entity has one;
    -- only the server ever calls :set() on it (inside SetWarriorName), same discipline as every
    -- other server-authoritative net var in this mod. Ordinary wild instances of these 12
    -- prefabs (the overwhelming majority) never get SetWarriorName called on them at all, so
    -- their net_string just stays at its default "" and this listener never fires.
    inst._wallflower_doodlename = net_string(inst.GUID, "wallflower.doodlename", "wallflowerdoodlenamedirty")
    inst:ListenForEvent("wallflowerdoodlenamedirty", function()
        local value = inst._wallflower_doodlename:value()
        if value ~= "" then
            inst.nameoverride = value
        end
    end)

    if not TheWorld.ismastersim then
        return
    end

    local orig_onsave = inst.OnSave
    inst.OnSave = function(inst2, data)
        local refs = orig_onsave ~= nil and orig_onsave(inst2, data) or nil
        SaveDoodleWarrior(inst2, data)
        return refs
    end

    local orig_onload = inst.OnLoad
    inst.OnLoad = function(inst2, data)
        if orig_onload ~= nil then
            orig_onload(inst2, data)
        end
        LoadDoodleWarrior(inst2, data)
    end
end

return M
