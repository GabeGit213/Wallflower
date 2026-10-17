-- Studying (formerly "Analyze") no longer locks a class permanently -- it just can't be
-- repeated within the same day (analyzed_today, cleared on "cycleschanged"). Instead, studying
-- something for the first time EVER permanently unlocks it for the Conjure Item menu (if it's a
-- real item/recipe or a natural resource's drop) or the Doodle Warrior system (if it's one of
-- the nine "replica" animals, or contributes to the Treevor/Berrtha/Bouuldozer tree/berrybush/
-- boulder tallies). Inspiration itself is now spent per-conjure/summon rather than reset to 0
-- on a single "cast".

-- Inspiration cost tiers for Conjure Item, keyed by recipe.level's tech trees (see
-- scripts/constants.lua's TECH table for how e.g. TECH.MAGIC_TWO/THREE map to Prestihatitator/
-- Shadow Manipulator). Placeholder numbers -- meant to be tuned by playtesting, not exact on
-- the first pass.
local TECH_TIER_COST =
{
    SCIENCE = { [1] = 10, [2] = 20, [3] = 30 },
    MAGIC = { [2] = 35, [3] = 50 },
    ANCIENT = { [2] = 60, [3] = 75, [4] = 90 },
    CELESTIAL = { [1] = 65, [3] = 90 },
    SHADOWFORGING = { [1] = 65, [2] = 90 },
    LUNARFORGING = { [1] = 65, [2] = 90 },
    SHADOW = { [3] = 90 },
}
-- 10, not 5 -- exactly 2 Studies (5 Inspiration each) per natural-resource conjure.
local BASE_INSPIRATION_COST = 10
local MAX_INSPIRATION_COST = 90

-- Natural resources (logs, rocks, twigs, berries, ...) have no Recipe object at all, so this
-- also has to work with recipe == nil (falls back to the flat base cost).
local function GetInspirationCost(recipe)
    if recipe == nil then
        return BASE_INSPIRATION_COST
    end

    local cost = BASE_INSPIRATION_COST
    for tree, tiers in pairs(TECH_TIER_COST) do
        local level = recipe.level[tree]
        if level ~= nil and level > 0 then
            local tiercost = tiers[level]
            if tiercost == nil then
                -- A level higher than anything we've tabulated for this tree: use our highest
                -- known tier for it rather than silently treating it as free.
                local maxlevel, maxcost = 0, BASE_INSPIRATION_COST
                for lvl, c in pairs(tiers) do
                    if lvl > maxlevel then
                        maxlevel, maxcost = lvl, c
                    end
                end
                tiercost = maxcost
            end
            cost = math.max(cost, tiercost)
        end
    end

    return math.min(cost, MAX_INSPIRATION_COST)
end

-- Lazily built once AllRecipes is fully populated (by the time anyone actually studies
-- something, well after every mod's recipes have loaded), mapping a product prefab name to the
-- first eligible recipe that produces it.
--
-- Besides the usual survivor-lock/deconstruction exclusions, this also excludes recipes with a
-- custom actionstr or limitedamount set -- both are markers Klei uses for special shop/offering
-- recipes (Wandering Trader, Hermit Crab Shop, Rabbit King, pet-taming offerings, etc), which
-- exist as real Recipe objects but aren't meant to be normally built. Some of these use
-- TECH.LOST ({MAGIC=10, SCIENCE=10, ANCIENT=10}) as a "not gated by a normal tech tier at all"
-- marker, which without this exclusion made GetInspirationCost treat them as absurdly
-- high-tier (e.g. wanderingtradershop_twigs, product "twigs", was making plain sapling-picked
-- twigs cost 90 Inspiration instead of the base 5 -- the real twigs-yielding entity is the
-- sapling, resolved via Pickable.product elsewhere, not this recipe).
local product_to_recipe = nil
local function GetRecipeForProduct(product)
    if product_to_recipe == nil then
        product_to_recipe = {}
        for _, recipe in pairs(AllRecipes) do
            if recipe.builder_tag == nil and recipe.builder_skill == nil and not recipe.is_deconstruction_recipe
                and recipe.actionstr == nil and not recipe.limitedamount then
                if product_to_recipe[recipe.product] == nil then
                    product_to_recipe[recipe.product] = recipe
                end
            end
        end
    end
    return product_to_recipe[product]
end

local BASIC_REPLICA_PREFABS =
{
    bee = true,
    pigman = true,
    frog = true,
    merm = true,
    beefalo = true,
    bunnyman = true,
    catcoon = true,
    penguin = true,
    lightninggoat = true,
}

local Inspiration = Class(function(self, inst)
    self.inst = inst

    self.current = 0
    self.max = TUNING.WALLFLOWER_INSPIRATION_MAX or 100

    -- Cleared every day (see the "cycleschanged" listener below) -- the "must study a different
    -- thing" rule, no longer a permanent lock.
    self.analyzed_today = {}
    self.analyzed_today_day = nil

    -- Permanent, persisted, never cleared.
    self.unlocked_conjure_items = {}
    self.unlocked_replicas = {}
    self.analyzed_tree_count = 0
    self.analyzed_berrybush_count = 0
    self.analyzed_boulder_count = 0
    self.unlocked_treevor = false
    self.unlocked_berrtha = false
    self.unlocked_bouuldozer = false

    self.hasbuff = false

    self:_PushNetVar()
    self:_PushUnlockedItems()
    self:_PushUnlockedWarriors()
    self:_PushWarriorProgress()
    self:_PushAnalyzedToday()

    -- TheWorld.state.cycles (what the daily reset is keyed on) only updates one tick after
    -- "ms_cyclecomplete" fires, via the separate "cycleschanged" event -- see worldstate.lua's
    -- OnCyclesChanged. Listening on the wrong one previously got this stuck reading a stale day.
    self.inst:ListenForEvent("cycleschanged", function()
        self:_CheckNewDay()
    end, TheWorld)
end)

function Inspiration:_PushNetVar()
    if self.inst.inspiration ~= nil then
        self.inst.inspiration:set(self.current)
    end
end

-- Mirrors the unlocked-items set to the client so WallflowerSpellScreen can render it --
-- unlocked_conjure_items itself is server-only component state, same reasoning as
-- _PushAnalyzedToday below.
function Inspiration:_PushUnlockedItems()
    if self.inst.wallflower_unlockeditems == nil then
        return
    end

    local names = {}
    for name in pairs(self.unlocked_conjure_items) do
        table.insert(names, name)
    end
    table.sort(names)

    self.inst.wallflower_unlockeditems:set(table.concat(names, "\n"))
end

-- Mirrors the unlocked-warrior set (9 basic replicas + the 3 achievement warriors) to the client
-- so WallflowerSummonScreen can render it -- same reasoning as _PushUnlockedItems above.
function Inspiration:_PushUnlockedWarriors()
    if self.inst.wallflower_unlockedwarriors == nil then
        return
    end

    local names = {}
    for name in pairs(self.unlocked_replicas) do
        table.insert(names, name)
    end
    if self.unlocked_treevor then
        table.insert(names, "treevor")
    end
    if self.unlocked_berrtha then
        table.insert(names, "berrtha")
    end
    if self.unlocked_bouuldozer then
        table.insert(names, "bouuldozer")
    end
    table.sort(names)

    self.inst.wallflower_unlockedwarriors:set(table.concat(names, "\n"))
end

-- Mirrors the 3 achievement-warrior tallies to the client so WallflowerSummonScreen can show
-- progress (e.g. "7/10 trees studied") on the still-locked slots, instead of giving no feedback
-- at all until the moment they unlock.
function Inspiration:_PushWarriorProgress()
    if self.inst.wallflower_treecount ~= nil then
        self.inst.wallflower_treecount:set(self.analyzed_tree_count)
    end
    if self.inst.wallflower_berrybushcount ~= nil then
        self.inst.wallflower_berrybushcount:set(self.analyzed_berrybush_count)
    end
    if self.inst.wallflower_bouldercount ~= nil then
        self.inst.wallflower_bouldercount:set(self.analyzed_boulder_count)
    end
end

-- Mirrors today's already-studied classes to the client so the SCENE gate in modmain.lua can
-- hide Study on things already done today, instead of only finding out (and no-oping with a
-- spoken line) after the player tries it server-side.
function Inspiration:_PushAnalyzedToday()
    if self.inst.wallflower_analyzedtoday == nil then
        return
    end

    local classes = {}
    for class in pairs(self.analyzed_today) do
        table.insert(classes, class)
    end

    self.inst.wallflower_analyzedtoday:set(table.concat(classes, "\n"))
end

function Inspiration:_CheckNewDay()
    if self.analyzed_today_day ~= TheWorld.state.cycles then
        self.analyzed_today = {}
        self.analyzed_today_day = TheWorld.state.cycles
        self:_PushAnalyzedToday()
    end
end

function Inspiration:GetPercent()
    return self.current / self.max
end

function Inspiration:DoDelta(amount)
    self:SetCurrent(self.current + amount)
end

-- Absolute setter (0 to self.max), clamped. Used by DoDelta/SpendInspiration and by the
-- c_setwallflowerinspiration debug console command.
function Inspiration:SetCurrent(value)
    local old = self.current
    self.current = math.clamp(value, 0, self.max)

    if self.current == old then
        return
    end

    self:_PushNetVar()
    self.inst:PushEvent("inspirationdelta", { oldpercent = old / self.max, newpercent = self.current / self.max })

    self:_AnnounceThresholds(old, self.current)
    self:_UpdateBuff()
end

-- Spends Inspiration on a Conjure Item purchase or a Doodle Warrior summon. Returns false
-- without changing anything if the player can't afford it -- callers must check affordability
-- themselves before doing anything else irreversible (spawning items, etc).
function Inspiration:SpendInspiration(amount)
    if amount == nil or amount <= 0 or self.current < amount then
        return false
    end

    self:SetCurrent(self.current - amount)
    return true
end

-- Speaks a placeholder line the first time Inspiration crosses the 50 (sanity-immunity) or 100
-- (meter full) thresholds upward (not on every delta while already past them, and not on the
-- downward drop from spending).
function Inspiration:_AnnounceThresholds(old, new)
    if self.inst.components.talker == nil then
        return
    end

    local buffthreshold = TUNING.WALLFLOWER_INSPIRATION_BUFF_THRESHOLD or 50
    if old < buffthreshold and new >= buffthreshold then
        self.inst.components.talker:Say(STRINGS.CHARACTERS.WALLFLOWER.ANNOUNCE_INSPIRATION_50)
    end

    if old < self.max and new >= self.max then
        self.inst.components.talker:Say(STRINGS.CHARACTERS.WALLFLOWER.ANNOUNCE_INSPIRATION_100)
    end
end

-- Disables passive sanity drain from the environment/darkness at the buff threshold, without
-- touching monster-aura or moisture drain. Composes safely with other sources (Pumpkin Hat,
-- Walter) since Sanity:SetLightDrainImmune is backed by a SourceModifierList (boolean OR).
function Inspiration:_UpdateBuff()
    local shouldhavebuff = self.current >= (TUNING.WALLFLOWER_INSPIRATION_BUFF_THRESHOLD or 50)
    if shouldhavebuff ~= self.hasbuff then
        self.hasbuff = shouldhavebuff
        if self.inst.components.sanity ~= nil then
            self.inst.components.sanity:SetLightDrainImmune(shouldhavebuff, self)
        end
    end
end

-- Groups reskin/variant prefabs of the same "kind" (e.g. evergreen/lumpy -> "tree") while
-- keeping distinct creature species (rabbit vs butterfly) as separate classes.
function Inspiration:GetEntityClass(target)
    if target:HasTag("tree") then
        return "tree"
    elseif target:HasTag("boulder") then
        return "boulder"
    end
    return target.prefab
end

-- Server-side authorization check for the "SummonWarrior" RPC handler in modmain.lua -- never
-- trust the client-picked warrior kind blindly, same discipline as unlocked_conjure_items.
function Inspiration:IsWarriorUnlocked(kind)
    if kind == "treevor" then
        return self.unlocked_treevor
    elseif kind == "berrtha" then
        return self.unlocked_berrtha
    elseif kind == "bouuldozer" then
        return self.unlocked_bouuldozer
    end
    return self.unlocked_replicas[kind] == true
end

function Inspiration:HasAnalyzedToday(class)
    return self.analyzed_today[class] == true
end

function Inspiration:CanAnalyze(target)
    if target == nil or target == self.inst then
        return false
    end

    -- Some "inspectable" entities (e.g. the dirt mound a mole leaves behind) have no real
    -- prefab identity of their own -- GetEntityClass falls through to nil for those. Nothing
    -- meaningful to Study/Conjure there, so just reject it (mirrors the client-side SCENE gate
    -- in modmain.lua, which hides Study on these entirely for the same reason).
    if self:GetEntityClass(target) == nil then
        return false
    end

    self:_CheckNewDay()
    return not self:HasAnalyzedToday(self:GetEntityClass(target))
end

-- Everything studying this target would permanently unlock in the Conjure Item menu (a set,
-- since one target can plausibly unlock several things at once):
--   - Every possible drop from its lootdropper, if it has one -- this is what actually fixes
--     "trees/boulders only unlocked one drop" -- LootDropper:GetAllPossibleLoot already knows
--     the true (possibly randomized/tool-specific) full loot table per prefab, including
--     special variants like moonrock or gold-bearing boulders each having their own distinct
--     loot, so there's no need to hand-maintain a per-resource-type table ourselves.
--   - Its Pickable product, if it has one (grass -> cutgrass, sapling -> twigs, berrybush ->
--     berries, ...).
--   - Its own prefab, if it's currently a genuine portable item (dropped or in inventory) --
--     covers both recipe-backed items AND found-not-crafted resources like marble, which have
--     no Recipe object at all but should still become conjurable once studied.
--   - Its own prefab, if it's a normally-craftable structure/item (i.e. GetRecipeForProduct
--     resolves it) -- this is what makes studying a built structure (a campfire, a science
--     machine, a sculpture, ...) unlock that structure itself, rather than nothing at all (a
--     placed structure isn't a lootdropper/pickable/portable inventoryitem, so none of the
--     checks above would ever catch it). GetRecipeForProduct already excludes survivor-locked
--     and skill-tree recipes (builder_tag/builder_skill), so this can't unlock those.
function Inspiration:GetConjureUnlocks(target)
    local unlocks = {}

    if target.components.lootdropper ~= nil then
        for prefab in pairs(target.components.lootdropper:GetAllPossibleLoot(true)) do
            unlocks[prefab] = true
        end
    end

    if target.components.pickable ~= nil and target.components.pickable.product ~= nil then
        unlocks[target.components.pickable.product] = true
    end

    if target.components.inventoryitem ~= nil and target.components.inventoryitem.canbepickedup then
        unlocks[target.prefab] = true
    end

    if GetRecipeForProduct(target.prefab) ~= nil then
        unlocks[target.prefab] = true
    end

    return unlocks
end

function Inspiration:DoAnalyze(target)
    if not self:CanAnalyze(target) then
        return false
    end

    local class = self:GetEntityClass(target)
    self.analyzed_today[class] = true
    self:_PushAnalyzedToday()

    local addedunlock = false
    for name in pairs(self:GetConjureUnlocks(target)) do
        if not self.unlocked_conjure_items[name] then
            self.unlocked_conjure_items[name] = true
            addedunlock = true
        end
    end
    if addedunlock then
        self:_PushUnlockedItems()
    end

    local addedwarriorunlock = false

    if BASIC_REPLICA_PREFABS[target.prefab] and not self.unlocked_replicas[target.prefab] then
        self.unlocked_replicas[target.prefab] = true
        addedwarriorunlock = true
    end

    if target:HasTag("tree") then
        self.analyzed_tree_count = math.min(self.analyzed_tree_count + 1, 10)
        if self.analyzed_tree_count >= 10 and not self.unlocked_treevor then
            self.unlocked_treevor = true
            addedwarriorunlock = true
        end
    elseif target:HasTag("boulder") then
        self.analyzed_boulder_count = math.min(self.analyzed_boulder_count + 1, 10)
        if self.analyzed_boulder_count >= 10 and not self.unlocked_bouuldozer then
            self.unlocked_bouuldozer = true
            addedwarriorunlock = true
        end
    elseif target.prefab == "berrybush" or target.prefab == "berrybush2" then
        self.analyzed_berrybush_count = math.min(self.analyzed_berrybush_count + 1, 10)
        if self.analyzed_berrybush_count >= 10 and not self.unlocked_berrtha then
            self.unlocked_berrtha = true
            addedwarriorunlock = true
        end
    end

    if addedwarriorunlock then
        self:_PushUnlockedWarriors()
    end
    self:_PushWarriorProgress()

    self:DoDelta(TUNING.WALLFLOWER_INSPIRATION_PER_ANALYZE or 5)

    return true
end

function Inspiration:OnSave()
    local analyzed_today = {}
    for class in pairs(self.analyzed_today) do
        table.insert(analyzed_today, class)
    end

    local unlocked_conjure_items = {}
    for name in pairs(self.unlocked_conjure_items) do
        table.insert(unlocked_conjure_items, name)
    end

    local unlocked_replicas = {}
    for name in pairs(self.unlocked_replicas) do
        table.insert(unlocked_replicas, name)
    end

    return {
        current = self.current,
        analyzed_today = analyzed_today,
        analyzed_today_day = self.analyzed_today_day,
        unlocked_conjure_items = unlocked_conjure_items,
        unlocked_replicas = unlocked_replicas,
        analyzed_tree_count = self.analyzed_tree_count,
        analyzed_berrybush_count = self.analyzed_berrybush_count,
        analyzed_boulder_count = self.analyzed_boulder_count,
        unlocked_treevor = self.unlocked_treevor,
        unlocked_berrtha = self.unlocked_berrtha,
        unlocked_bouuldozer = self.unlocked_bouuldozer,
    }
end

function Inspiration:OnLoad(data)
    if data == nil then
        return
    end

    self.current = data.current or 0
    self.analyzed_today_day = data.analyzed_today_day

    self.analyzed_today = {}
    if data.analyzed_today ~= nil then
        for _, class in ipairs(data.analyzed_today) do
            self.analyzed_today[class] = true
        end
    end

    self.unlocked_conjure_items = {}
    if data.unlocked_conjure_items ~= nil then
        for _, name in ipairs(data.unlocked_conjure_items) do
            self.unlocked_conjure_items[name] = true
        end
    end

    self.unlocked_replicas = {}
    if data.unlocked_replicas ~= nil then
        for _, name in ipairs(data.unlocked_replicas) do
            self.unlocked_replicas[name] = true
        end
    end

    self.analyzed_tree_count = data.analyzed_tree_count or 0
    self.analyzed_berrybush_count = data.analyzed_berrybush_count or 0
    self.analyzed_boulder_count = data.analyzed_boulder_count or 0
    self.unlocked_treevor = data.unlocked_treevor or false
    self.unlocked_berrtha = data.unlocked_berrtha or false
    self.unlocked_bouuldozer = data.unlocked_bouuldozer or false

    self:_PushNetVar()
    self:_PushUnlockedItems()
    self:_PushUnlockedWarriors()
    self:_PushWarriorProgress()
    self:_PushAnalyzedToday()
    self:_UpdateBuff()
end

Inspiration.GetInspirationCost = GetInspirationCost
Inspiration.GetRecipeForProduct = GetRecipeForProduct

return Inspiration
