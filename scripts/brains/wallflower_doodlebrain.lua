-- Shared combat-follow brain for every Doodle Warrior (see scripts/util/wallflower_doodlewarriors.lua
-- for how it's attached to a freshly-summoned creature). Deliberately generic and reused for all
-- twelve warrior kinds rather than hand-authoring per-creature AI: each borrowed creature already
-- has correct idle/walk/attack/hit/death animations via its own stategraph (SGpig, SGbee, SGLeif,
-- etc), so all this needs to decide is who to follow and who to fight, using the same standard
-- vanilla behaviours (Follow, ChaseAndAttack) every other DST companion (Abigail, Bernie) is built
-- from -- see scripts/behaviours/follow.lua and scripts/behaviours/chaseandattack.lua.
--
-- Targets come from two places: proactively, anything actually tagged "hostile" (real monsters --
-- spiders, hounds, Treeguards, ...) within FindHostile's search radius; reactively, whatever
-- Wallflower attacks or gets attacked by, or whatever attacks the warrior itself, all wired up in
-- ConvertToDoodleWarrior (wallflower_doodlewarriors.lua) via combat.target. Deliberately does NOT
-- scan for the much broader "_combat" tag (anything with a combat component at all) -- that
-- caught passive/neutral creatures too (pigs, bunnymen, koalefants, ...) and made warriors pick
-- fights Wallflower never asked for. Either way, IsAlly() keeps two of Wallflower's own warriors
-- (sharing her as their leader) from ever targeting each other over incidental splash damage.

require "behaviours/follow"
require "behaviours/chaseandattack"
require "behaviours/wander"

local SEE_HOSTILE_DIST = 15
local MAX_CHASE_TIME = 8
local GIVE_UP_DIST = 20

local FIND_HOSTILE_MUST_TAGS = { "hostile" }
local FIND_HOSTILE_CANT_TAGS = { "INLIMBO", "companion", "player", "playerghost", "invisible", "notarget" }

local function GetLeader(inst)
    return inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
end

-- Looks for actual monsters around the leader (not just around the warrior itself) so warriors
-- that have wandered slightly ahead or behind still converge on whatever's threatening Wallflower.
local function FindHostile(inst)
    local leader = GetLeader(inst)
    local x, y, z
    if leader ~= nil and leader:IsValid() then
        x, y, z = leader.Transform:GetWorldPosition()
    else
        x, y, z = inst.Transform:GetWorldPosition()
    end

    local ents = TheSim:FindEntities(x, y, z, SEE_HOSTILE_DIST, FIND_HOSTILE_MUST_TAGS, FIND_HOSTILE_CANT_TAGS)
    for _, ent in ipairs(ents) do
        if ent ~= inst and ent:IsValid() and ent.entity:IsVisible()
            and ent.components.health ~= nil and not ent.components.health:IsDead()
            and inst.components.combat:CanTarget(ent)
            and not inst.components.combat:IsAlly(ent) then
            return ent
        end
    end
    return nil
end

local WallflowerDoodleBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

function WallflowerDoodleBrain:OnStart()
    local root = PriorityNode({
        ChaseAndAttack(self.inst, MAX_CHASE_TIME, GIVE_UP_DIST, nil, FindHostile),
        Follow(self.inst, function() return GetLeader(self.inst) end, 2, 5, 10),
        Wander(self.inst),
    }, .25)

    self.bt = BT(self.inst, root)
end

return WallflowerDoodleBrain
