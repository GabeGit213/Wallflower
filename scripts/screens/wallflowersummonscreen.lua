-- Summon Warrior picker for Wallflower's Brush: pick from whatever Doodle Warrior kind has been
-- unlocked by studying (see scripts/components/inspiration.lua for the unlock tracking and
-- scripts/util/wallflower_doodlewarriors.lua for what each kind costs/caps at), spending
-- Inspiration the same way Conjure Item does. Deliberately mirrors
-- scripts/screens/wallflowerspellscreen.lua's structure -- see that file for the reasoning behind
-- the simple/self-contained (non-crafting-menu) widget approach. No search box here: unlike
-- Conjure Item's potentially-large recipe list, there are only ever 12 possible warrior kinds
-- total, which comfortably fits on one page.

local Screen = require "widgets/screen"
local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local TEMPLATES = require "widgets/redux/templates"
local DoodleWarriors = require "util/wallflower_doodlewarriors"

local COLS = 6
local ROWS = 2
local PAGE_SIZE = COLS * ROWS
local CELL_SIZE = 80
local ICON_SIZE = 56

-- The 3 achievement warriors are shown even while still locked, as a progress readout, so
-- there's some visible feedback toward unlocking them instead of them just never appearing.
local ACHIEVEMENT_PROGRESS_FIELD = {
    treevor = "wallflower_treecount",
    berrtha = "wallflower_berrybushcount",
    bouuldozer = "wallflower_bouldercount",
}
local ACHIEVEMENT_PROGRESS_LABEL = {
    treevor = "trees studied",
    berrtha = "berry bushes studied",
    bouuldozer = "boulders studied",
}

-- Replicas display as "Bee Doodle"/"Pig Man Doodle"/... (STRINGS.NAMES.WALLFLOWER_DOODLE_<KIND>,
-- set in modmain.lua); achievement warriors display as their own plain custom name
-- (STRINGS.NAMES.WALLFLOWER_<KIND>). Both are set via inst.nameoverride at summon time in
-- util/wallflower_doodlewarriors.lua -- this just has to look them up the same way.
local function GetDisplayName(kind)
    return STRINGS.NAMES["WALLFLOWER_DOODLE_" .. string.upper(kind)]
        or STRINGS.NAMES["WALLFLOWER_" .. string.upper(kind)]
        or STRINGS.NAMES[string.upper(kind)]
        or kind
end

-- Most of these 12 creatures were never meant to be inventory items, so most of them have no
-- real inventory icon at all. GetInventoryItemAtlas's default (no_fallback=false) behavior masks
-- that: it always returns "images/inventoryimages4.xml" as a guess even when the image isn't
-- actually in it, which made SetTexture fail on a bogus region instead of cleanly reporting "no
-- icon" -- passing no_fallback=true here fixes that. The persistent button-slot background (see
-- the cell-creation loop below, which no longer hides ImageButton's own default image) means a
-- missing icon is still a clearly visible, clickable slot rather than nothing at all.
local function ResolveImage(kind)
    local image = kind .. ".tex"
    local atlas = GetInventoryItemAtlas(image, true)
    if atlas == nil then
        return nil, nil
    end
    return resolvefilepath(atlas), image
end

local function GetEntries(owner)
    local entries = {}
    local unlocked = {}

    local raw = owner.wallflower_unlockedwarriors ~= nil and owner.wallflower_unlockedwarriors:value() or ""
    for kind in string.gmatch(raw, "[^\n]+") do
        unlocked[kind] = true
        table.insert(entries, {
            kind = kind,
            displayname = GetDisplayName(kind),
            cost = DoodleWarriors.SUMMON_COST[kind] or 0,
            locked = false,
        })
    end

    for _, kind in ipairs(DoodleWarriors.ACHIEVEMENT_KINDS) do
        if not unlocked[kind] then
            local field = ACHIEVEMENT_PROGRESS_FIELD[kind]
            local netvar = field ~= nil and owner[field] or nil
            local count = netvar ~= nil and netvar:value() or 0
            table.insert(entries, {
                kind = kind,
                displayname = GetDisplayName(kind),
                locked = true,
                progresstext = string.format("%d/10 %s", count, ACHIEVEMENT_PROGRESS_LABEL[kind] or ""),
            })
        end
    end

    table.sort(entries, function(a, b)
        if a.locked ~= b.locked then
            return not a.locked
        end
        return a.displayname < b.displayname
    end)

    return entries
end

local WallflowerSummonScreen = Class(Screen, function(self, owner)
    Screen._ctor(self, "WallflowerSummonScreen")

    self.owner = owner
    self.entries = GetEntries(owner)
    self.page = 1

    self.black = self:AddChild(TEMPLATES.BackgroundTint())
    self.proot = self:AddChild(TEMPLATES.ScreenRoot())

    self.title = self.proot:AddChild(Text(TITLEFONT, 40))
    self.title:SetPosition(0, 200)
    self.title:SetString("Summon Warrior")

    self.emptylabel = self.proot:AddChild(Text(BODYTEXTFONT, 28))
    self.emptylabel:SetPosition(0, 100)
    self.emptylabel:SetString("Nothing unlocked yet -- Study animals, trees, berry bushes, or boulders first.")
    self.emptylabel:Hide()

    self.grid = self.proot:AddChild(Widget("grid"))
    self.grid:SetPosition(-(COLS - 1) * CELL_SIZE / 2, 100)

    self.cells = {}
    for i = 1, PAGE_SIZE do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)

        local btn = self.grid:AddChild(ImageButton())
        btn:SetPosition(col * CELL_SIZE, -row * CELL_SIZE)
        -- Unlike wallflowerspellscreen.lua, this deliberately does NOT hide the default button
        -- image -- shrunk down to a small persistent slot background instead, it guarantees
        -- every cell has a real, clickable, visible frame even when the real creature icon on
        -- top of it can't be resolved (most of these 12 creatures have no inventory icon).
        btn:ForceImageSize(CELL_SIZE - 10, CELL_SIZE - 10)
        btn.icon = btn:AddChild(Image())
        -- Most of these 12 creatures were never meant to be inventory items and have no real
        -- icon anywhere in the base game to draw from (not even a minimap icon -- wild
        -- creatures don't get one). Until there's custom Doodle Warrior art, a big initial
        -- letter is a clearer placeholder than an unexplained blank slot.
        btn.iconletter = btn:AddChild(Text(NUMBERFONT, 40))
        btn.iconletter:SetPosition(0, 8)
        btn.costlabel = btn:AddChild(Text(NUMBERFONT, 22))
        btn.costlabel:SetPosition(0, -34)
        btn:Hide()
        btn:SetOnClick(function() self:OnPickEntry(btn.entry) end)

        self.cells[i] = btn
    end

    self.pagelabel = self.proot:AddChild(Text(BODYTEXTFONT, 28))
    self.pagelabel:SetPosition(0, -230)

    self.prevbutton = self.proot:AddChild(TEMPLATES.StandardButton(function() self:ChangePage(-1) end, "Prev", {100, 45}))
    self.prevbutton:SetPosition(-150, -280)

    self.nextbutton = self.proot:AddChild(TEMPLATES.StandardButton(function() self:ChangePage(1) end, "Next", {100, 45}))
    self.nextbutton:SetPosition(150, -280)

    self.closebutton = self.proot:AddChild(TEMPLATES.StandardButton(function() self:Close() end, "Cancel", {160, 45}))
    self.closebutton:SetPosition(0, -280)

    -- The despawn feature: dismisses every currently-active Doodle Warrior at once.
    self.dismissbutton = self.proot:AddChild(TEMPLATES.StandardButton(function() self:OnDismissAll() end, "Dismiss All Warriors", {220, 45}))
    self.dismissbutton:SetPosition(0, -330)

    self.default_focus = self.closebutton

    self:RefreshPage()
end)

function WallflowerSummonScreen:GetNumPages()
    return math.max(1, math.ceil(#self.entries / PAGE_SIZE))
end

function WallflowerSummonScreen:ChangePage(delta)
    local numpages = self:GetNumPages()
    self.page = math.clamp(self.page + delta, 1, numpages)
    self:RefreshPage()
end

function WallflowerSummonScreen:RefreshPage()
    local startindex = (self.page - 1) * PAGE_SIZE

    local currentinspiration = self.owner.inspiration ~= nil and self.owner.inspiration:value() or 0

    for i, btn in ipairs(self.cells) do
        local entry = self.entries[startindex + i]
        if entry ~= nil then
            btn.entry = entry
            -- Image:SetTexture (unlike the Image() constructor) asserts BOTH args non-nil --
            -- it has no graceful "both nil clears it" handling of its own, so this must never
            -- be called at all when resolution fails, not just skip the follow-up scaling.
            local atlas, image = ResolveImage(entry.kind)
            if atlas ~= nil and image ~= nil then
                btn.icon:SetTexture(atlas, image)
                btn.icon:ScaleToSize(ICON_SIZE, ICON_SIZE)
                btn.icon:Show()
                btn.iconletter:Hide()
            else
                btn.icon:Hide()
                btn.iconletter:SetString(string.upper(string.sub(entry.displayname, 1, 1)))
                btn.iconletter:Show()
            end

            if entry.locked then
                btn.costlabel:SetString(entry.progresstext)
                btn.costlabel:SetColour(0.7, 0.7, 0.7, 1)
                btn:SetHoverText(entry.displayname .. " (" .. entry.progresstext .. ")")
                btn:Disable()
            else
                btn.costlabel:SetString(tostring(entry.cost))
                btn.costlabel:SetColour(currentinspiration >= entry.cost and 1 or 0.9, currentinspiration >= entry.cost and 1 or 0.2, currentinspiration >= entry.cost and 1 or 0.2, 1)
                btn:SetHoverText(entry.displayname .. " (" .. tostring(entry.cost) .. " Inspiration)")
                btn:Enable()
            end
            btn:Show()
        else
            btn.entry = nil
            btn:Hide()
        end
    end

    if #self.entries == 0 then
        self.emptylabel:Show()
    else
        self.emptylabel:Hide()
    end
    self.pagelabel:SetString(string.format("Page %d / %d", self.page, self:GetNumPages()))
end

function WallflowerSummonScreen:OnPickEntry(entry)
    if entry == nil or entry.locked then
        return
    end

    local currentinspiration = self.owner.inspiration ~= nil and self.owner.inspiration:value() or 0
    if currentinspiration < entry.cost then
        return -- Can't afford it -- server would reject anyway, but no reason to even try.
    end

    SendModRPCToServer(GetModRPC("Wallflower", "SummonWarrior"), entry.kind)
    self:Close()
end

function WallflowerSummonScreen:OnDismissAll()
    SendModRPCToServer(GetModRPC("Wallflower", "DismissWarriors"))
    self:Close()
end

function WallflowerSummonScreen:Close()
    TheFrontEnd:PopScreen(self)
end

function WallflowerSummonScreen:OnControl(control, down)
    if WallflowerSummonScreen._base.OnControl(self, control, down) then
        return true
    end

    if not down and control == CONTROL_CANCEL then
        self:Close()
        return true
    end

    return false
end

return WallflowerSummonScreen
