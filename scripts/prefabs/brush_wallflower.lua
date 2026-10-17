-- Visionary's Brush: hands-slot weapon (35 damage) that, at max Inspiration, lets Wallflower
-- cast a spell to receive a chosen craftable item. Placeholder art: reuses the vanilla
-- Spear's build (bank "spear", build "swap_spear") until custom Wallflower art replaces it.
--
-- Deliberately NOT declaring Asset("ANIM", "anim/spear.zip"/"swap_spear.zip") here: spear.lua
-- is a core, always-loaded vanilla prefab that already declares and loads these builds itself,
-- so they're guaranteed available by the time this prefab needs them. Redeclaring a
-- mod-shared vanilla asset path (whether in modmain.lua's Assets table or here) makes the
-- engine's startup FilesExistAsyncThread check look for the file as if this mod shipped it,
-- which crashes with "Could not find file: anim/spear.zip" since it's not in this mod's own
-- anim/ folder.

local assets = {}

local function onequip(inst, owner)
    owner.AnimState:OverrideSymbol("swap_object", "swap_spear", "swap_spear")
    owner.AnimState:Show("ARM_carry")
    owner.AnimState:Hide("ARM_normal")
end

local function onunequip(inst, owner)
    owner.AnimState:Hide("ARM_carry")
    owner.AnimState:Show("ARM_normal")
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("spear")
    inst.AnimState:SetBuild("swap_spear")
    inst.AnimState:PlayAnimation("idle")

    inst:AddTag("sharp")
    inst:AddTag("wallflower_brush")

    --weapon (from weapon component) added to pristine state for optimization
    inst:AddTag("weapon")

    MakeInventoryFloatable(inst, "med", 0.05, {1.1, 0.5, 1.1}, true, -9)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("weapon")
    inst.components.weapon:SetDamage(TUNING.WALLFLOWER_BRUSH_DAMAGE)

    inst:AddComponent("inventoryitem")
    -- Reuse the Spear's inventory icon too (not just its equip/carry build), since we don't
    -- have custom Wallflower art yet -- without this, the game can't find an icon named
    -- "brush_wallflower.tex" in any inventoryimages atlas and shows a blank slot.
    inst.replica.inventoryitem:SetImage("spear")

    inst:AddComponent("inspectable")

    inst:AddComponent("equippable")
    -- equipslot defaults to EQUIPSLOTS.HANDS
    inst.components.equippable:SetOnEquip(onequip)
    inst.components.equippable:SetOnUnequip(onunequip)

    MakeHauntableLaunch(inst)

    return inst
end

return Prefab("brush_wallflower", fn, assets)
