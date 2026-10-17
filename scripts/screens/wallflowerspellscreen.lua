-- Conjure Item picker for Wallflower's Brush: pick from whatever's been permanently unlocked by
-- studying (see scripts/components/inspiration.lua), spending Inspiration equal to its cost.
-- Kept deliberately simple/self-contained rather than reusing the crafting menu's internal
-- widgets, which are heavily tied to PLAYER.HUD/TechTree/builder state. The client only opens
-- this UI and reads the replicated unlock list; the actual grant + Inspiration spend happens
-- server-side via the "CastSpell" mod RPC after the player picks something (see modmain.lua).

local Screen = require "widgets/screen"
local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local TEMPLATES = require "widgets/redux/templates"
local Inspiration = require "components/inspiration"

local COLS = 8
local ROWS = 5
local PAGE_SIZE = COLS * ROWS
local CELL_SIZE = 80
local ICON_SIZE = 64

-- An unlocked entry is either a real recipe's product (something studied directly, e.g. an
-- inventory item) or a natural resource's drop (something a tree/boulder/pickable would yield,
-- which has no Recipe object at all -- GetRecipeForProduct returns nil for those).
local function GetDisplayName(name, recipe)
    if recipe ~= nil and recipe.nameoverride ~= nil then
        return recipe.nameoverride
    end
    return STRINGS.NAMES[string.upper(name)] or name
end

-- A few recipes (e.g. "amulet") end up with an atlas of nil while still having an image name.
-- Recipe's own constructor normally back-fills atlas via GetInventoryItemAtlas(image), but
-- evidently not always -- so redo that resolution defensively here. Returns nil, nil when no
-- real icon can be found at all; the caller (RefreshPage) is responsible for never actually
-- calling Image:SetTexture with that -- unlike the Image() constructor, SetTexture itself
-- unconditionally asserts both args non-nil, it has no "both nil clears it" handling of its own.
-- Natural resources (no Recipe object) resolve the same way, straight off their own prefab name
-- -- for those specifically, GetInventoryItemAtlas needs no_fallback=true, otherwise it always
-- guesses "images/inventoryimages4.xml" even when the image isn't actually there, which fails
-- silently (a logged warning, no real icon) instead of correctly reporting "no icon" here.
local function ResolveImage(name, recipe)
    local atlas = recipe ~= nil and recipe.atlas or nil
    local image = recipe ~= nil and recipe.image or (name .. ".tex")

    if atlas == nil and image ~= nil then
        atlas = GetInventoryItemAtlas(image, true)
        if atlas ~= nil then
            atlas = resolvefilepath(atlas)
        end
    end
    if atlas == nil or image == nil then
        return nil, nil
    end
    return atlas, image
end

local function GetUnlockedEntries(owner)
    local entries = {}

    local raw = owner.wallflower_unlockeditems ~= nil and owner.wallflower_unlockeditems:value() or ""
    if raw == "" then
        return entries
    end

    for name in string.gmatch(raw, "[^\n]+") do
        local recipe = Inspiration.GetRecipeForProduct(name)
        table.insert(entries, {
            name = name,
            recipe = recipe,
            displayname = GetDisplayName(name, recipe),
            cost = Inspiration.GetInspirationCost(recipe),
        })
    end

    table.sort(entries, function(a, b)
        return a.displayname < b.displayname
    end)

    return entries
end

local WallflowerSpellScreen = Class(Screen, function(self, owner)
    Screen._ctor(self, "WallflowerSpellScreen")

    self.owner = owner
    self.entries = GetUnlockedEntries(owner)
    self.filtered_entries = self.entries
    self.searchtext = ""
    self.page = 1

    self.black = self:AddChild(TEMPLATES.BackgroundTint())
    self.proot = self:AddChild(TEMPLATES.ScreenRoot())

    self.title = self.proot:AddChild(Text(TITLEFONT, 40))
    self.title:SetPosition(0, 280)
    self.title:SetString("Conjure Item")

    self.searchbox = self.proot:AddChild(TEMPLATES.StandardSingleLineTextEntry("", 300, 40, nil, 25, "Search..."))
    self.searchbox:SetPosition(0, 225)

    self.emptylabel = self.proot:AddChild(Text(BODYTEXTFONT, 28))
    self.emptylabel:SetPosition(0, 100)
    self.emptylabel:SetString("Nothing studied yet -- use the Monocle to Study something first.")
    self.emptylabel:Hide()

    self.grid = self.proot:AddChild(Widget("grid"))
    self.grid:SetPosition(-(COLS - 1) * CELL_SIZE / 2, 100)

    self.cells = {}
    for i = 1, PAGE_SIZE do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)

        local btn = self.grid:AddChild(ImageButton())
        btn:SetPosition(col * CELL_SIZE, -row * CELL_SIZE)
        -- ImageButton's own "image" child is for its normal/focus/disabled button-state
        -- textures (button_long.tex etc, a wide rectangle) -- it is NOT a generic icon slot.
        -- Reusing it directly for our square item icon is what caused both the squished
        -- icons (scaled against the wrong native texture size) and the "weird box" on hover
        -- (OnGainFocus swaps it to a different button-state texture) in an earlier version of
        -- this screen. Shrinking it down to a small square (ForceImageSize) instead of hiding
        -- it fixes both AND keeps every cell a real, clickable slot even for entries whose real
        -- icon can't be resolved (a hidden/textureless image widget has no rendered geometry to
        -- click at all) -- our own icon image is layered on top of it.
        btn:ForceImageSize(CELL_SIZE - 10, CELL_SIZE - 10)
        btn.icon = btn:AddChild(Image())
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

    self.default_focus = self.closebutton

    self:RefreshPage()

    -- No native "text changed" callback on TextEdit, so poll it -- cheap, and only actually
    -- re-filters when the string differs from last check.
    self:StartUpdating()
end)

function WallflowerSpellScreen:OnUpdate()
    local text = self.searchbox.textbox:GetString()
    if text ~= self.searchtext then
        self.searchtext = text
        self:ApplyFilter()
    end
end

function WallflowerSpellScreen:ApplyFilter()
    if self.searchtext == "" then
        self.filtered_entries = self.entries
    else
        local query = string.lower(self.searchtext)
        local filtered = {}
        for _, entry in ipairs(self.entries) do
            if string.find(string.lower(entry.displayname), query, 1, true) then
                table.insert(filtered, entry)
            end
        end
        self.filtered_entries = filtered
    end

    self.page = 1
    self:RefreshPage()
end

function WallflowerSpellScreen:GetNumPages()
    return math.max(1, math.ceil(#self.filtered_entries / PAGE_SIZE))
end

function WallflowerSpellScreen:ChangePage(delta)
    local numpages = self:GetNumPages()
    self.page = math.clamp(self.page + delta, 1, numpages)
    self:RefreshPage()
end

function WallflowerSpellScreen:RefreshPage()
    local startindex = (self.page - 1) * PAGE_SIZE

    local currentinspiration = self.owner.inspiration ~= nil and self.owner.inspiration:value() or 0

    for i, btn in ipairs(self.cells) do
        local entry = self.filtered_entries[startindex + i]
        if entry ~= nil then
            btn.entry = entry
            -- Image:SetTexture (unlike the Image() constructor) asserts BOTH args non-nil --
            -- it has no graceful "both nil clears it" handling of its own, so this must never
            -- be called at all when resolution fails, not just skip the follow-up scaling.
            -- (This is exactly what crashed WallflowerSummonScreen: most Doodle Warriors have no
            -- real inventory icon, which is the common case there but was never exercised here.)
            local atlas, image = ResolveImage(entry.name, entry.recipe)
            if atlas ~= nil and image ~= nil then
                btn.icon:SetTexture(atlas, image)
                btn.icon:ScaleToSize(ICON_SIZE, ICON_SIZE)
                btn.icon:Show()
            else
                btn.icon:Hide()
            end
            btn.costlabel:SetString(tostring(entry.cost))
            btn.costlabel:SetColour(currentinspiration >= entry.cost and 1 or 0.9, currentinspiration >= entry.cost and 1 or 0.2, currentinspiration >= entry.cost and 1 or 0.2, 1)
            btn:SetHoverText(entry.displayname .. " (" .. tostring(entry.cost) .. " Inspiration)")
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

function WallflowerSpellScreen:OnPickEntry(entry)
    if entry == nil then
        return
    end

    local currentinspiration = self.owner.inspiration ~= nil and self.owner.inspiration:value() or 0
    if currentinspiration < entry.cost then
        return -- Can't afford it -- server would reject anyway, but no reason to even try.
    end

    SendModRPCToServer(GetModRPC("Wallflower", "CastSpell"), entry.name)
    self:Close()
end

function WallflowerSpellScreen:Close()
    TheFrontEnd:PopScreen(self)
end

function WallflowerSpellScreen:OnControl(control, down)
    if WallflowerSpellScreen._base.OnControl(self, control, down) then
        return true
    end

    if not down and control == CONTROL_CANCEL then
        self:Close()
        return true
    end

    return false
end

return WallflowerSpellScreen
