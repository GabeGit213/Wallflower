PrefabFiles = {
	"wallflower",
	"wallflower_none",
	"monocle_wallflower",
	"brush_wallflower",
}

Assets = {
    Asset( "IMAGE", "images/saveslot_portraits/wallflower.tex" ),
    Asset( "ATLAS", "images/saveslot_portraits/wallflower.xml" ),

    Asset( "IMAGE", "images/selectscreen_portraits/wallflower.tex" ),
    Asset( "ATLAS", "images/selectscreen_portraits/wallflower.xml" ),
	
    Asset( "IMAGE", "images/selectscreen_portraits/wallflower_silho.tex" ),
    Asset( "ATLAS", "images/selectscreen_portraits/wallflower_silho.xml" ),

    Asset( "IMAGE", "bigportraits/wallflower.tex" ),
    Asset( "ATLAS", "bigportraits/wallflower.xml" ),
	
	Asset( "IMAGE", "images/map_icons/wallflower.tex" ),
	Asset( "ATLAS", "images/map_icons/wallflower.xml" ),
	
	Asset( "IMAGE", "images/avatars/avatar_wallflower.tex" ),
    Asset( "ATLAS", "images/avatars/avatar_wallflower.xml" ),
	
	Asset( "IMAGE", "images/avatars/avatar_ghost_wallflower.tex" ),
    Asset( "ATLAS", "images/avatars/avatar_ghost_wallflower.xml" ),
	
	Asset( "IMAGE", "images/avatars/self_inspect_wallflower.tex" ),
    Asset( "ATLAS", "images/avatars/self_inspect_wallflower.xml" ),
	
	Asset( "IMAGE", "images/names_wallflower.tex" ),
    Asset( "ATLAS", "images/names_wallflower.xml" ),
	
	Asset( "IMAGE", "images/names_gold_wallflower.tex" ),
    Asset( "ATLAS", "images/names_gold_wallflower.xml" ),

	-- Note: the Monocle/Brush's vanilla-art Asset() declarations (hat_plantregistry.zip,
	-- spear.zip, swap_spear.zip) intentionally live only in monocle_wallflower.lua and
	-- brush_wallflower.lua's own per-prefab assets tables, not here. Declaring the same
	-- shared vanilla path a second time at this mod-global level broke asset resolution
	-- for those paths entirely (including for the vanilla spear prefab itself) -- see
	-- client_log.txt: "Could not find an asset matching anim/spear.zip in any of the
	-- search paths" while loading prefabs/spear.lua.
}

AddMinimapAtlas("images/map_icons/wallflower.xml")

local require = GLOBAL.require
local STRINGS = GLOBAL.STRINGS
local TUNING = GLOBAL.TUNING
local net_byte = GLOBAL.net_byte
local net_string = GLOBAL.net_string
local EQUIPSLOTS = GLOBAL.EQUIPSLOTS
local ACTIONS = GLOBAL.ACTIONS
local AllRecipes = GLOBAL.AllRecipes
local SpawnPrefab = GLOBAL.SpawnPrefab
local ActionHandler = GLOBAL.ActionHandler
local TECH = GLOBAL.TECH
local State = GLOBAL.State
local EventHandler = GLOBAL.EventHandler
local GetRandomItem = GLOBAL.GetRandomItem
local GetInventoryItemAtlas = GLOBAL.GetInventoryItemAtlas

local Inspiration = require "components/inspiration"

-- Inspiration meter tuning
TUNING.WALLFLOWER_INSPIRATION_MAX = 100
TUNING.WALLFLOWER_INSPIRATION_PER_ANALYZE = 5
TUNING.WALLFLOWER_INSPIRATION_BUFF_THRESHOLD = 50
TUNING.WALLFLOWER_BRUSH_DAMAGE = 25

--------------------------------------------------------------------------------------------
-- Recipes: Artist's Monocle / Visionary's Brush
--------------------------------------------------------------------------------------------

-- Placeholder recipes (1 flint each) -- these are just enough to make the items obtainable
-- through the normal crafting menu; real recipes are the user's own to design later.
-- builder_tag = "wallflower" restricts them to the Wallflower character, via the tag added
-- in wallflower.lua's common_postinit.
--
-- Recipe icons default to "<product>.tex" with no atlas set (Recipe's own GetInventoryItemAtlas
-- fallback is disabled in the base game's recipe.lua), which resolves to nothing since our
-- prefabs deliberately don't register their own inventoryimages (they reuse vanilla art) --
-- that's what showed up as stale axe/pickaxe icons (leftover textures in the recycled crafting
-- menu widgets) instead of a real icon. Pointing atlas/image at the actual reused vanilla icons
-- (resolved dynamically via GetInventoryItemAtlas, same as the items' own SetImage calls) fixes
-- this the same way the items' own inventory icons were fixed.
AddCharacterRecipe("monocle_wallflower", { Ingredient("flint", 1) }, TECH.NONE, {
    builder_tag = "wallflower",
    atlas = GetInventoryItemAtlas("plantregistryhat.tex"),
    image = "plantregistryhat.tex",
    description = "placeholder",
})
AddCharacterRecipe("brush_wallflower", { Ingredient("flint", 1) }, TECH.NONE, {
    builder_tag = "wallflower",
    atlas = GetInventoryItemAtlas("spear.tex"),
    image = "spear.tex",
    description = "placeholder",
})

-- Attach the Inspiration net var + component to the Wallflower player prefab specifically
-- (this is a character-exclusive stat, not a general player component).
--
-- wallflower_unlockeditems mirrors the set of permanently-unlocked Conjure Item names so
-- WallflowerSpellScreen can render the menu at all; wallflower_analyzedtoday mirrors today's
-- already-studied classes so the SCENE gate below can hide Study on them (instead of only the
-- old "show it, then no-op with a spoken line" approach).
AddPrefabPostInit("wallflower", function(inst)
    inst.inspiration = net_byte(inst.GUID, "wallflower.inspiration", "wallflowerinspirationdirty")
    inst.wallflower_unlockeditems = net_string(inst.GUID, "wallflower.unlockeditems", "wallflowerunlockeditemsdirty")
    inst.wallflower_unlockedwarriors = net_string(inst.GUID, "wallflower.unlockedwarriors", "wallflowerunlockedwarriorsdirty")
    inst.wallflower_analyzedtoday = net_string(inst.GUID, "wallflower.analyzedtoday", "wallfloweranalyzedtodaydirty")

    -- Progress toward the 3 achievement warriors (0-10 each) -- mirrored to the client purely so
    -- WallflowerSummonScreen can show "7/10 trees studied"-style progress on locked slots.
    inst.wallflower_treecount = net_byte(inst.GUID, "wallflower.treecount", "wallflowertreecountdirty")
    inst.wallflower_berrybushcount = net_byte(inst.GUID, "wallflower.berrybushcount", "wallflowerberrybushcountdirty")
    inst.wallflower_bouldercount = net_byte(inst.GUID, "wallflower.bouldercount", "wallflowerbouldercountdirty")

    if not GLOBAL.TheWorld.ismastersim then
        return
    end

    inst:AddComponent("inspiration")
end)

-- Debug console command: set Wallflower's Inspiration directly, e.g. c_setwallflowerinspiration(50).
-- NOTE: named distinctly from vanilla's own c_setinspiration -- that one is Wigfrid's bard/song
-- inspiration (player.components.singinginspiration), a completely different system that just
-- happens to share the name. Takes raw points (0-100), not a 0-1 percent like most vanilla
-- c_set* commands, since the mod's own thresholds (50/100) are specified in points.
function GLOBAL.c_setwallflowerinspiration(n)
    local player = GLOBAL.ConsoleCommandPlayer()
    if player ~= nil and player.components.inspiration ~= nil then
        player.components.inspiration:SetCurrent(n)
    end
end

-- Inspiration HUD badge
-- NOTE: filename is "wallflower_inspirationbadge", not "inspirationbadge" -- vanilla already
-- ships scripts/widgets/inspirationbadge.lua (Wigfrid's bard/song-inspiration HUD badge).
-- Using the same path shadows it for everyone and crashes vanilla's own statusdisplays.lua
-- (which calls owner:GetInspiration(), a method our class doesn't have).
--
-- Also: the field/callback names below are deliberately prefixed "wallflower" rather than
-- plain "inspirationbadge"/"oninspirationdirty" -- StatusDisplays is a single shared widget
-- instance, and vanilla uses those exact field names itself (self.inspirationbadge,
-- checked in OnSetPlayerMode) for Wigfrid's bard badge. Reusing them silently tricked
-- vanilla's own code into thinking any Wallflower player has the bard system, crashing on
-- owner:GetInspiration() the moment the player fully spawns in.
local InspirationBadge = require "widgets/wallflower_inspirationbadge"

-- Combined Status (a very common HUD-layout mod) already knows how to make room for a "4th"
-- badge -- but only by name: it wraps StatusDisplays:AddInspiration/AddMightiness and looks
-- specifically for self.inspirationbadge/self.mightybadge/self.pethealthbadge, repositioning
-- whichever one it finds to (-62,-52) alongside its own tightened health/hunger/sanity cluster.
-- We deliberately don't use "self.inspirationbadge" ourselves (see the big comment below --
-- that exact name collides with Wigfrid's own real bard badge on this shared widget and crashes
-- vanilla's own code), so Combined Status has no idea our badge exists and never moves it,
-- leaving it stranded at the vanilla-layout position underneath Combined Status's
-- repositioned/condensed meters instead of alongside them. Detecting it and mirroring its own
-- target slot keeps the two mods visually in sync.
local COMBINED_STATUS_MOD_ID = "workshop-376333686"
local HasCombinedStatus = GLOBAL.KnownModIndex ~= nil and GLOBAL.KnownModIndex:IsModEnabled(COMBINED_STATUS_MOD_ID)

AddClassPostConstruct("widgets/statusdisplays", function(self)
    if self.owner.inspiration == nil then
        return
    end

    self.wallflower_inspirationbadge = self:AddChild(InspirationBadge(self.owner))

    -- Without an explicit position this defaults to (0,0), landing right on top of the sanity
    -- badge instead of alongside it.
    if HasCombinedStatus then
        self.wallflower_inspirationbadge:SetPosition(-62, -52, 0)
    else
        -- Vanilla's own answer to "add a 4th meter" (see StatusDisplays:AddInspiration, used
        -- for Wigfrid's real bard/song inspiration badge) is to drop the new badge into the
        -- center column just below the other three, and slide the moisture meter (which
        -- normally sits in that exact spot) out to the side to make room -- mirroring that here
        -- keeps the same spacing/look players already know from vanilla. Left untouched under
        -- Combined Status since it already repositions the moisture meter itself.
        self.wallflower_inspirationbadge:SetPosition(self.column3, -130, 0)
        self.moisturemeter:SetPosition(self.column1, -130, 0)
    end

    self.onwallflowerinspirationdirty = function(owner)
        self.wallflower_inspirationbadge:SetInspirationPercent(owner.inspiration:value() / TUNING.WALLFLOWER_INSPIRATION_MAX)
    end
    self.inst:ListenForEvent("wallflowerinspirationdirty", self.onwallflowerinspirationdirty, self.owner)
    self.onwallflowerinspirationdirty(self.owner)

    -- Hide/show alongside the rest of the HUD on death/resurrection. Vanilla's own
    -- StatusDisplays:SetGhostMode hides heart/stomach/brain/moisture/Wigfrid's bard badge/etc
    -- when the owner becomes a ghost, but has no idea our badge exists, so it never got included
    -- in that list -- it just stayed on screen through death. Listening for the same events
    -- vanilla uses (also what wallflower.lua's own onbecameghost/onbecamehuman listen for)
    -- keeps it in sync independently, without needing to touch that shared method.
    if self.owner:HasTag("playerghost") then
        self.wallflower_inspirationbadge:Hide()
    end
    self.inst:ListenForEvent("ms_becameghost", function() self.wallflower_inspirationbadge:Hide() end, self.owner)
    self.inst:ListenForEvent("ms_respawnedfromghost", function() self.wallflower_inspirationbadge:Show() end, self.owner)
end)

--------------------------------------------------------------------------------------------
-- Artist's Monocle: "Study" action (internal id stays ANALYZE -- purely a display-string
-- rename, see point 8 of the rework: same behavior, just different hover text)
--------------------------------------------------------------------------------------------

-- Runs server-side only. Re-validates everything rather than trusting the client-side gate
-- below (which is intentionally a looser approximation -- per-day/per-class state isn't
-- replicated to the client, see scripts/components/inspiration.lua).
AddAction("ANALYZE", "Study", function(act)
    local doer = act.doer
    local target = act.target
    if doer == nil or target == nil or doer.components.inspiration == nil then
        return false
    end

    local inventory = doer.replica.inventory
    local hat = inventory ~= nil and inventory:GetEquippedItem(EQUIPSLOTS.HEAD) or nil
    if hat == nil or not hat:HasTag("wallflower_monocle") then
        return false
    end

    local inspiration = doer.components.inspiration
    -- Same-day-duplicate state isn't replicated to the client (see the SCENE gate below), so
    -- Study can still be attempted on something already studied today -- give feedback instead
    -- of just silently no-oping.
    if inspiration:HasAnalyzedToday(inspiration:GetEntityClass(target)) then
        if doer.components.talker ~= nil then
            doer.components.talker:Say(STRINGS.CHARACTERS.WALLFLOWER.ANNOUNCE_ANALYZE_FAIL)
        end
        return false
    end

    if not inspiration:DoAnalyze(target) then
        return false
    end

    if doer.components.talker ~= nil then
        doer.components.talker:Say(GetRandomItem(STRINGS.CHARACTERS.WALLFLOWER.ANNOUNCE_ANALYZE))
    end

    return true
end)

-- Right-click action resolution (for mouse/keyboard, not the controller radial menu) always
-- executes whichever candidate action has the highest .priority -- see
-- PlayerActionPicker:SortActionList/GetSceneActions. ACTIONS.PICK defaults to priority 0 (see
-- actions.lua), and pickable's own SCENE handler doesn't check left/right at all, so it's also
-- always a right-click candidate on any ripe/harvestable resource (grass, saplings, berry
-- bushes). With ANALYZE at the same default priority (0), PICK was consistently winning the
-- tie, so right-clicking an unpicked resource always harvested it instead of studying it --
-- Study only ever "worked" on already-picked/barren entities, where PICK isn't a candidate
-- at all. Bumping this above PICK's priority fixes that; left-click harvesting is completely
-- unaffected since Study never appears as a left-click candidate (gated on "right" above).
ACTIONS.ANALYZE.priority = 1

-- Duplicates Inspiration:GetEntityClass -- kept in sync manually rather than requiring the
-- component here, since this runs client-side (including for remote, non-mastersim clients)
-- where components/inspiration.lua's own instance methods aren't reachable, but the underlying
-- logic (checking tags/prefab on the hovered target) needs nothing server-only.
local function GetEntityClass(target)
    if target:HasTag("tree") then
        return "tree"
    elseif target:HasTag("boulder") then
        return "boulder"
    end
    return target.prefab
end

-- Cheap "is this newline-joined list currently tracking this key" check (boundary-padded so a
-- class name can't false-match as a substring of a different, longer class name), used instead
-- of parsing the whole net_string into a table every time this gate runs (i.e. every frame the
-- cursor hovers something interactable).
local function StringSetContains(str, key)
    return string.find("\n" .. str .. "\n", "\n" .. key .. "\n", 1, true) ~= nil
end

AddComponentAction("SCENE", "inspectable", function(inst, doer, actions, right)
    -- Note: DST does not auto-tag a player with their own prefab name (only generic tags
    -- like "player"/"character"), so this has to check .prefab directly.
    if not right or doer.prefab ~= "wallflower" then
        return
    end

    if inst == doer then
        return -- Players are also "inspectable" (for the vanilla "Examine myself" action).
    end

    local inventory = doer.replica.inventory
    local hat = inventory ~= nil and inventory:GetEquippedItem(EQUIPSLOTS.HEAD) or nil
    if hat == nil or not hat:HasTag("wallflower_monocle") then
        return
    end

    -- Some "inspectable" entities (e.g. the dirt mound a mole leaves behind) have no real
    -- prefab identity of their own to speak of -- GetEntityClass falls through to nil for
    -- those, which used to crash StringSetContains below. Nothing meaningful to Study/Conjure
    -- there anyway, so just skip offering Study entirely.
    local class = GetEntityClass(inst)
    if class == nil then
        return
    end

    -- Hide Study entirely on something already studied today, rather than showing it and only
    -- finding out (via a spoken "already did this" line) after trying it.
    if doer.wallflower_analyzedtoday ~= nil and StringSetContains(doer.wallflower_analyzedtoday:value(), class) then
        return
    end

    table.insert(actions, ACTIONS.ANALYZE)
end)

AddStategraphActionHandler("wilson", ActionHandler(ACTIONS.ANALYZE, "dolongaction"))

--------------------------------------------------------------------------------------------
-- Visionary's Brush: weapon + "Conjure Item" action
--------------------------------------------------------------------------------------------

local WallflowerSpellScreen = require "screens/wallflowerspellscreen"
local WallflowerSummonScreen = require "screens/wallflowersummonscreen"
local DoodleWarriors = require "util/wallflower_doodlewarriors"

-- Makes a Doodle Warrior remember it's one of Wallflower's own across a save/reload (and
-- reconnects it to its owner once they're back in the world) -- see M.SetupPersistence's own
-- big comment in util/wallflower_doodlewarriors.lua for why this has to hook every borrowed
-- creature prefab individually rather than something more central.
for _, prefab in ipairs(DoodleWarriors.ALL_PREFABS) do
    AddPrefabPostInit(prefab, DoodleWarriors.SetupPersistence)
end

-- NOTE: this action's id is "WALLFLOWER_CASTSPELL", NOT "CASTSPELL" -- the base game already
-- has a real ACTIONS.CASTSPELL (used by every spell-casting staff: Fire Staff, Ice Staff,
-- Telelocator Staff, etc.). AddAction does an unconditional ACTIONS[id] = action, so naming
-- ours "CASTSPELL" would have silently overwritten -- not added alongside -- that real action's
-- entire fn for every item in the game that uses it. Same reasoning applies to the stategraph
-- state name below (SGwilson already has a real "castspell" state tied to that same action).
--
-- No more Inspiration threshold to open this -- Conjure Item is available any time the Brush
-- is equipped; affordability is checked per-item, in the RPC handler below, at spend time.
AddAction("WALLFLOWER_CASTSPELL", "Conjure Item", function(act)
    local doer = act.doer
    if doer == nil or doer.inspiration == nil then
        return false
    end

    -- action.fn (this function) always runs authoritatively on the server -- BufferedAction:Do
    -- calls it unconditionally, with no client-side prediction path for arbitrary mod actions.
    -- On a listen server that "server" is the SAME process as the host's own client, which is
    -- exactly why "doer == ThePlayer" used to look like it worked: for the host casting, doer
    -- and ThePlayer really were the same entity in that one process. For a genuinely separate
    -- remote player casting, this code still only ever runs in the HOST's process, where
    -- ThePlayer is the HOST's own character -- so "doer == ThePlayer" was always false for
    -- anyone but the host, and the screen never opened on the caster's screen at all. Telling
    -- the specific casting client to open it via a targeted RPC (same pattern StartPlacement
    -- already uses below) is the correct fix, and works identically for host and remote alike.
    if GLOBAL.TheWorld.ismastersim and doer.userid ~= nil then
        SendModRPCToClient(GetClientModRPC("Wallflower", "OpenSpellScreen"), doer.userid)
    end

    return true
end)

AddClientModRPCHandler("Wallflower", "OpenSpellScreen", function()
    local player = GLOBAL.ThePlayer
    if player ~= nil then
        GLOBAL.TheFrontEnd:PushScreen(WallflowerSpellScreen(player))
    end
end)

-- Summon Warrior: same "open a picker screen on the caster's own client via a targeted RPC"
-- pattern as Conjure Item above -- see that action's own comment for why the naive
-- "doer == ThePlayer" check doesn't work for remote players.
AddAction("WALLFLOWER_SUMMONWARRIOR", "Summon Warrior", function(act)
    local doer = act.doer
    if doer == nil or doer.inspiration == nil then
        return false
    end

    if GLOBAL.TheWorld.ismastersim and doer.userid ~= nil then
        SendModRPCToClient(GetClientModRPC("Wallflower", "OpenSummonScreen"), doer.userid)
    end

    return true
end)

-- Without this, the default BufferedAction range logic (see Locomotor:PushAction) walks
-- Wallflower to within range of the clicked ground point before running the action at all --
-- since Summon Warrior should conjure the warrior wherever the cursor is without moving her,
-- this needs to fire immediately instead.
ACTIONS.WALLFLOWER_SUMMONWARRIOR.instant = true

AddClientModRPCHandler("Wallflower", "OpenSummonScreen", function()
    local player = GLOBAL.ThePlayer
    if player ~= nil then
        GLOBAL.TheFrontEnd:PushScreen(WallflowerSummonScreen(player))
    end
end)

-- Right-click behavior splits based on target: hovering Wallflower herself offers Conjure Item
-- (the existing menu); hovering anything else (another creature, a structure, an item on the
-- ground) offers nothing at all here, so Study and every other normal action on that entity
-- still shows up. Summon Warrior is terrain-only -- see the POINT handler below -- it has no
-- correlation to hovering entities.
AddComponentAction("EQUIPPED", "weapon", function(inst, doer, target, actions, right)
    if not right or not inst:HasTag("wallflower_brush") then
        return
    end

    if doer.inspiration == nil then
        return
    end

    if target == doer then
        table.insert(actions, ACTIONS.WALLFLOWER_CASTSPELL)
    end
end)

-- Empty-ground (or boat deck) counterpart to the EQUIPPED handler above -- the only place Summon
-- Warrior shows up, per the user's own correction to the original spec (it was originally meant
-- to also show on any non-self entity, but that suppressed Study/other entity actions entirely --
-- see PlayerActionPicker:GetRightClickActions, which never falls back to SCENE actions once
-- EQUIPPED returns anything for a real entity under the cursor).
AddComponentAction("POINT", "weapon", function(inst, doer, pos, actions, right, target)
    if not right or not inst:HasTag("wallflower_brush") then
        return
    end

    if doer.inspiration == nil then
        return
    end

    table.insert(actions, ACTIONS.WALLFLOWER_SUMMONWARRIOR)
end)

-- Placeholder Cast Spell animation: reuses the shared "book" reading animation (the same one
-- Wickerbottom plays when reading her books -- it's a generic action anim every character build
-- has, not something exclusive to her) until the user has custom Cast Spell art/animation.
AddStategraphState("wilson", State{
    name = "wallflower_castspell",
    -- No "busy" tag (unlike most SGwilson "doing" states) -- the mechanical effect (opening the
    -- screen / spending Inspiration) already happened synchronously in onenter below, so there's
    -- nothing left to protect by blocking new input. Leaving "busy" off lets SGwilson's own
    -- common handlers interrupt this the instant the player does anything else (walk, place a
    -- structure, ...) instead of forcing the book-flourish animation to finish playing out first.
    tags = { "doing", "nodangle" },

    onenter = function(inst)
        inst.components.locomotor:Stop()
        inst.AnimState:PlayAnimation("book")

        -- Quote, sound, AND the menu opening (via PerformBufferedAction -> the action's fn,
        -- which sends the OpenSpellScreen RPC) all fire together right here, in sync with the
        -- animation starting, rather than waiting for the animation to finish -- the anim just
        -- plays out as cosmetic follow-through afterward.
        if inst.components.talker ~= nil then
            inst.components.talker:Say(STRINGS.CHARACTERS.WALLFLOWER.ANNOUNCE_CASTSPELL)
        end
        if inst.SoundEmitter ~= nil then
            -- Placeholder cast sound -- this is the same generic "book_spell" sound SGwilson
            -- itself falls back to for any character casting any spellbook, matching the "book"
            -- placeholder animation.
            inst.SoundEmitter:PlaySound("dontstarve/common/book_spell")
        end

        inst:PerformBufferedAction()
    end,

    events =
    {
        EventHandler("animqueueover", function(inst)
            if inst.AnimState:AnimDone() then
                inst.sg:GoToState("idle")
            end
        end),
    },
})

AddStategraphActionHandler("wilson", ActionHandler(ACTIONS.WALLFLOWER_CASTSPELL, "wallflower_castspell"))

-- Same placeholder "book" animation/sound as wallflower_castspell above, just for the Summon
-- Warrior action instead -- kept as its own state (rather than branching one shared state on
-- act.action) so each action gets its own speech line and opens its own screen.
AddStategraphState("wilson", State{
    name = "wallflower_summonwarrior",
    -- No "busy" tag (unlike most SGwilson "doing" states) -- the mechanical effect (opening the
    -- screen / spending Inspiration) already happened synchronously in onenter below, so there's
    -- nothing left to protect by blocking new input. Leaving "busy" off lets SGwilson's own
    -- common handlers interrupt this the instant the player does anything else (walk, place a
    -- structure, ...) instead of forcing the book-flourish animation to finish playing out first.
    tags = { "doing", "nodangle" },

    onenter = function(inst)
        inst.components.locomotor:Stop()
        inst.AnimState:PlayAnimation("book")

        if inst.components.talker ~= nil then
            inst.components.talker:Say(STRINGS.CHARACTERS.WALLFLOWER.ANNOUNCE_SUMMONWARRIOR)
        end
        if inst.SoundEmitter ~= nil then
            inst.SoundEmitter:PlaySound("dontstarve/common/book_spell")
        end

        inst:PerformBufferedAction()
    end,

    events =
    {
        EventHandler("animqueueover", function(inst)
            if inst.AnimState:AnimDone() then
                inst.sg:GoToState("idle")
            end
        end),
    },
})

AddStategraphActionHandler("wilson", ActionHandler(ACTIONS.WALLFLOWER_SUMMONWARRIOR, "wallflower_summonwarrior"))

-- The actual grant + Inspiration spend happens here, server-side, after the client picks
-- something in WallflowerSpellScreen -- never trust the client-picked item blindly.
--
-- "itemname" is a permanently-unlocked Conjure Item entry -- either a real recipe's product
-- (something studied directly, e.g. an inventory item) or a natural resource's drop (something
-- a tree/boulder/pickable would yield, which has no Recipe object at all). GetRecipeForProduct
-- resolves the former and returns nil for the latter, which is also why we re-validate against
-- unlocked_conjure_items here rather than re-deriving eligibility from AllRecipes the way the
-- old any-recipe-in-the-game version did: that set IS the authorization now.
--
-- Recipes whose product is a structure (no inventoryitem component -- this is exactly the
-- same check Builder:MakeRecipe itself uses to decide "give as item" vs "place in world")
-- can't just be spawned and handed over: nothing GiveItem could do with them. For those, we
-- hand off to the real placement flow (PlayerController:StartBuildPlacementMode) instead of
-- reimplementing cursor-follow/placement-validity ourselves. That flow's confirm-click always
-- goes through Builder:MakeRecipeAtPoint, which requires both KnowsRecipe and (IsBuildBuffered
-- or HasIngredients) -- so conjuring a structure also permanently teaches the player that
-- recipe (a deliberate, user-approved tradeoff). We hand over the exact ingredients AND set the
-- buffered flag: the buffered flag is what actually keeps PlayerController's placement mode
-- alive frame-to-frame (see the comment below), but buffered builds skip real ingredient
-- consumption entirely in Builder:DoBuild -- so the granted ingredients are consumed manually
-- via the "buildstructure" event hook below instead, to make this behave like a real build
-- (materials spent) rather than a free buffered reward. If the player cancels placement
-- (right-click/ESC, which never tells the server), the ingredients are just harmlessly kept,
-- and the buffered flag auto-expires below to bound how long the recipe stays free-buildable.
AddModRPCHandler("Wallflower", "CastSpell", function(player, itemname)
    if player == nil or type(itemname) ~= "string" then
        return
    end

    local inspiration = player.components.inspiration
    if inspiration == nil or not inspiration.unlocked_conjure_items[itemname] then
        return
    end

    local recipe = Inspiration.GetRecipeForProduct(itemname)
    local cost = Inspiration.GetInspirationCost(recipe)
    if inspiration.current < cost then
        return
    end

    if recipe ~= nil and recipe.placer ~= nil then
        local builder = player.components.builder
        if builder == nil or player.components.inventory == nil then
            return
        end

        builder:AddRecipe(recipe.name)

        for _, ingredient in ipairs(recipe.ingredients) do
            for i = 1, math.ceil(ingredient.amount) do
                local ingredientitem = SpawnPrefab(ingredient.type)
                if ingredientitem ~= nil then
                    player.components.inventory:GiveItem(ingredientitem)
                end
            end
        end

        -- Confirmed via PlayerController:OnUpdate (line ~2877 in that file): placement mode
        -- isn't just gated on IsBuildBuffered at the final confirm-click -- it's re-checked
        -- EVERY FRAME the whole time the placer is up, and auto-cancels the instant it's
        -- false. So this has to be set, not just the real ingredients above. The risk this was
        -- originally avoiding (CancelPlacement, i.e. right-click/ESC, is purely client-side and
        -- never clears this server-side, which would otherwise leave the recipe permanently
        -- ingredient-free to build via the real crafting menu too) is handled by auto-expiring
        -- it below instead of never setting it at all.
        builder:SetBuildBuffered(recipe.name, true)

        -- Builder:DoBuild's non-inventoryitem (structure) branch skips RemoveIngredients
        -- entirely whenever the build is buffered ("if not is_buffered_build then
        -- self:RemoveIngredients(...)", see builder.lua) -- buffered builds are meant to be
        -- free rewards. Since we want the ingredients we just granted above to actually get
        -- consumed like a real build, do it ourselves the moment the structure goes down:
        -- Builder:DoBuild fires a "buildstructure" event on the player right after a successful
        -- structure placement, which is the exact hook for this.
        local function OnStructureBuilt(inst, data)
            if data.recipe ~= nil and data.recipe.name == recipe.name then
                for _, ingredient in ipairs(recipe.ingredients) do
                    player.components.inventory:ConsumeByName(ingredient.type, math.ceil(ingredient.amount))
                end
                player:RemoveEventCallback("buildstructure", OnStructureBuilt)
            end
        end
        player:ListenForEvent("buildstructure", OnStructureBuilt)

        player:DoTaskInTime(60, function()
            if builder.inst:IsValid() then
                if builder:IsBuildBuffered(recipe.name) then
                    builder:SetBuildBuffered(recipe.name, false)
                end
                player:RemoveEventCallback("buildstructure", OnStructureBuilt)
            end
        end)

        inspiration:SpendInspiration(cost)

        SendModRPCToClient(GetClientModRPC("Wallflower", "StartPlacement"), player.userid, recipe.name)
        return
    end

    -- Either a plain (non-placer) recipe's product, or a natural resource with no Recipe object
    -- at all (recipe == nil) -- both cases are just "spawn the item and give it to the player".
    local item = SpawnPrefab(recipe ~= nil and recipe.product or itemname)
    if item == nil then
        return
    end

    if player.components.inventory ~= nil then
        player.components.inventory:GiveItem(item)
    end

    inspiration:SpendInspiration(cost)
end)

-- Client-side: actually open the real placement UI for the structure the server just
-- prepared (see the "CastSpell" handler above for why this needs a server round-trip first).
AddClientModRPCHandler("Wallflower", "StartPlacement", function(recipename)
    local recipe = AllRecipes[recipename]
    local player = GLOBAL.ThePlayer
    if recipe == nil or player == nil or player.components.playercontroller == nil then
        return
    end

    player.components.playercontroller:StartBuildPlacementMode(recipe)
end)

-- The actual grant + Inspiration spend happens here, server-side, after the client picks
-- something in WallflowerSummonScreen -- never trust the client-picked warrior kind blindly,
-- same discipline as "CastSpell" above. Re-validates unlock, cap, AND cost, in that order, since
-- each is a separate reason to reject that's cheap to check before touching Inspiration at all.
AddModRPCHandler("Wallflower", "SummonWarrior", function(player, kind)
    if player == nil or type(kind) ~= "string" then
        return
    end

    local inspiration = player.components.inspiration
    if inspiration == nil or not inspiration:IsWarriorUnlocked(kind) then
        return
    end

    if DoodleWarriors.IsAtCap(player, kind) then
        if player.components.talker ~= nil then
            player.components.talker:Say(STRINGS.CHARACTERS.WALLFLOWER.ANNOUNCE_SUMMONWARRIOR_ATCAP)
        end
        return
    end

    local cost = DoodleWarriors.SUMMON_COST[kind]
    if cost == nil or not inspiration:SpendInspiration(cost) then
        return
    end

    DoodleWarriors.Summon(player, kind)
end)

-- Lets the player dismiss every currently-active Doodle Warrior at once (the "despawn when I no
-- longer need them" feature) -- triggered from the "Dismiss All" button in WallflowerSummonScreen.
AddModRPCHandler("Wallflower", "DismissWarriors", function(player)
    if player == nil then
        return
    end

    DoodleWarriors.DismissAll(player)
end)

-- The character select screen lines
STRINGS.CHARACTER_TITLES.wallflower = "The Artist"
STRINGS.CHARACTER_NAMES.wallflower = "Wallflower"
STRINGS.CHARACTER_DESCRIPTIONS.wallflower = "*An inspired artist, and very creative...\n*Doesn't pack a punch.\n*Smart, but gets hungry quickly and is faint of heart..."
STRINGS.CHARACTER_QUOTES.wallflower = "\"When Charlie gives you shadows, make some awesome doodles!\""
STRINGS.CHARACTER_SURVIVABILITY.wallflower = "Slim"

-- Custom speech strings
STRINGS.CHARACTERS.WALLFLOWER = require "speech_wallflower"

-- The character's name as appears in-game
STRINGS.NAMES.WALLFLOWER = "Wallflower"
STRINGS.SKIN_NAMES.wallflower_none = "Wallflower"

-- Item display names (from the mod spec, not placeholder text)
STRINGS.NAMES.MONOCLE_WALLFLOWER = "Artist's Monocle"
STRINGS.NAMES.BRUSH_WALLFLOWER = "Visionary's Brush"

-- Achievement Doodle Warrior display names -- these are shown via inst.nameoverride (set in
-- util/wallflower_doodlewarriors.lua) since Treevor/Berrtha/Bouuldozer are the real "leif"/
-- "perd"/"rook" prefabs underneath, borrowing their assets, not new prefabs of their own.
STRINGS.NAMES.WALLFLOWER_TREEVOR = "Treevor"
STRINGS.NAMES.WALLFLOWER_BERRTHA = "Berrtha"
STRINGS.NAMES.WALLFLOWER_BOUULDOZER = "Bouuldozer"

-- Doodle Replica display names ("Bee Doodle", "Pig Man Doodle", ...) -- shown via each summoned
-- replica's own inst.nameoverride = "wallflower_doodle_<kind>" (set in
-- util/wallflower_doodlewarriors.lua). Derived from each creature's own real vanilla display
-- name rather than hardcoded, so this can't drift out of sync with it (e.g. penguin's real name
-- is "Pengull", not "Penguin").
for _, kind in ipairs(DoodleWarriors.REPLICA_KINDS) do
    STRINGS.NAMES["WALLFLOWER_DOODLE_" .. string.upper(kind)] = (STRINGS.NAMES[string.upper(kind)] or kind) .. " Doodle"
end

-- The skins shown in the cycle view window on the character select screen.
-- A good place to see what you can put in here is in skinutils.lua, in the function GetSkinModes
local skin_modes = {
    { 
        type = "ghost_skin",
        anim_bank = "ghost",
        idle_anim = "idle", 
        scale = 0.75, 
        offset = { 0, -25 } 
    },
}

-- Add mod character to mod character list. Also specify a gender. Possible genders are MALE, FEMALE, ROBOT, NEUTRAL, and PLURAL.
AddModCharacter("wallflower", "FEMALE", skin_modes)
