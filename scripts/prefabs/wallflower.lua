local MakePlayerCharacter = require "prefabs/player_common"

local assets = {
    Asset("SCRIPT", "scripts/prefabs/player_common.lua"),
}

-- Your character's stats
TUNING.WALLFLOWER_HEALTH = 100
TUNING.WALLFLOWER_HUNGER = 75
TUNING.WALLFLOWER_SANITY = 175

-- Custom starting inventory
TUNING.GAMEMODE_STARTING_ITEMS.DEFAULT.WALLFLOWER = {
	"monocle_wallflower",
}

local start_inv = {}
for k, v in pairs(TUNING.GAMEMODE_STARTING_ITEMS) do
    start_inv[string.lower(k)] = v.WALLFLOWER
end
local prefabs = FlattenTree(start_inv, true)

-- When the character is revived from human
local function onbecamehuman(inst)
	-- Set speed when not a ghost (optional)
	inst.components.locomotor:SetExternalSpeedMultiplier(inst, "wallflower_speed_mod", 1)
end

local function onbecameghost(inst)
	-- Remove speed modifier when becoming a ghost
   inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "wallflower_speed_mod")
end

-- When loading or spawning the character
local function onload(inst)
    inst:ListenForEvent("ms_respawnedfromghost", onbecamehuman)
    inst:ListenForEvent("ms_becameghost", onbecameghost)

    if inst:HasTag("playerghost") then
        onbecameghost(inst)
    else
        onbecamehuman(inst)
    end
end


-- This initializes for both the server and client. Tags can be added here.
local common_postinit = function(inst)
	-- Minimap icon
	inst.MiniMapEntity:SetIcon( "wallflower.tex" )

	-- Note: the placeholder art's actual build name is still "esctemplate", handled via
	-- build_name_override / skins in wallflower_none.lua rather than here.

	-- Recipe-restriction tag for the Monocle/Brush's AddCharacterRecipe builder_tag (DST does
	-- not auto-tag a player with their own prefab name, so this has to be added explicitly).
	inst:AddTag("wallflower")
end

-- This initializes for the server only. Components are added here.
local master_postinit = function(inst)
	-- Set starting inventory
    inst.starting_inventory = start_inv[TheNet:GetServerGameMode()] or start_inv.default
	
	-- choose which sounds this character will play
	inst.soundsname = "willow"
	
	-- Uncomment if "wathgrithr"(Wigfrid) or "webber" voice is used
    --inst.talker_path_override = "dontstarve_DLC001/characters/"
	
	-- Stats	
	inst.components.health:SetMaxHealth(TUNING.WALLFLOWER_HEALTH)
	inst.components.hunger:SetMax(TUNING.WALLFLOWER_HUNGER)
	inst.components.sanity:SetMax(TUNING.WALLFLOWER_SANITY)
	
	-- Damage multiplier: she's an artist, not a fighter -- 0.75x compensates for the Doodle
	-- Warriors mechanic (see modmain.lua) that's meant to make up for her weaker combat.
    inst.components.combat.damagemultiplier = 0.75
	
	-- Hunger rate (optional)
	inst.components.hunger.hungerrate = 1 * TUNING.WILSON_HUNGER_RATE
	
	inst.OnLoad = onload
    inst.OnNewSpawn = onload
	
end

return MakePlayerCharacter("wallflower", prefabs, assets, common_postinit, master_postinit, prefabs)
