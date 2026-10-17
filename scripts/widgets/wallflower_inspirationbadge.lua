local Badge = require "widgets/badge"

-- Placeholder tint until the user's custom Inspiration badge art exists. Once that art is
-- ready: add Asset("ANIM", "anim/status_inspiration.zip") in modmain.lua's Assets table, and
-- pass its build name as the 4th arg to Badge._ctor below (see how HungerBadge/SanityBadge
-- pass "status_hunger"/"status_sanity") to swap in the custom icon symbol.
local INSPIRATION_TINT = { 178 / 255, 102 / 255, 1, 1 }

local InspirationBadge = Class(Badge, function(self, owner)
    -- Matches how HungerBadge/SanityBadge call this: nil anim (use the shared "status_meter"
    -- pie-fill look), nil iconbuild until custom art exists, nil circular_meter (that's a
    -- different alternate badge style, not what health/hunger/sanity use).
    Badge._ctor(self, nil, owner, INSPIRATION_TINT, nil, nil, nil, true)

    -- Starts at 0, not 1 -- Inspiration always starts empty, and initializing this to 1 made
    -- the very first sync (0/max) look like a decrease and misfire a red pulse on spawn.
    self.lastpercent = 0
end)

function InspirationBadge:SetInspirationPercent(pct)
    -- Badge:SetPercent's 2nd arg isn't a normalizer -- it's the real max stat value, used to
    -- reconstruct the raw number for the hover tooltip (math.ceil(val * max)). Passing 1 here
    -- made a 10% fill show "1" instead of "10".
    self:SetPercent(pct, TUNING.WALLFLOWER_INSPIRATION_MAX)

    -- Same sound vanilla's own meters (health/hunger/sanity) play on an increase, via
    -- widgets/statusdisplays.lua's SanityDelta/HealthDelta/HungerDelta handlers.
    if pct > self.lastpercent then
        self:PulseGreen()
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/sanity_up")
    elseif pct < self.lastpercent then
        self:PulseRed()
    end
    self.lastpercent = pct
end

return InspirationBadge
