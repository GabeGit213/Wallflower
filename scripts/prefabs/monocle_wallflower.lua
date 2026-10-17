-- Artist's Monocle: head-slot equippable that lets Wallflower "Analyze" world entities.
-- Placeholder art: reuses the vanilla Gardeneer Hat's build (bank/build "plantregistryhat" /
-- "hat_plantregistry") until custom Wallflower art replaces it.
--
-- Deliberately NOT declaring Asset("ANIM", "anim/hat_plantregistry.zip") here: the Gardeneer
-- Hat's own prefab is a core, always-loaded vanilla prefab that already declares and loads
-- this build itself, so it's guaranteed available by the time this prefab needs it.
-- Redeclaring a mod-shared vanilla asset path makes the engine's startup
-- FilesExistAsyncThread check look for the file as if this mod shipped it, which crashes
-- since it's not in this mod's own anim/ folder (see brush_wallflower.lua for the same issue
-- hit with anim/spear.zip).

local assets = {}

local function onequip(inst, owner)
    owner.AnimState:OverrideSymbol("swap_hat", "hat_plantregistry", "swap_hat")
    owner.AnimState:Show("HAT")
    owner.AnimState:Show("HAIR_HAT")
    owner.AnimState:Hide("HAIR_NOHAT")
    owner.AnimState:Hide("HAIR")

    if owner.isplayer then
        owner.AnimState:Hide("HEAD")
        owner.AnimState:Show("HEAD_HAT")
        owner.AnimState:Show("HEAD_HAT_NOHELM")
        owner.AnimState:Hide("HEAD_HAT_HELM")
    end
end

local function onunequip(inst, owner)
    owner.AnimState:ClearOverrideSymbol("swap_hat")
    owner.AnimState:Hide("HAT")
    owner.AnimState:Hide("HAIR_HAT")
    owner.AnimState:Show("HAIR_NOHAT")
    owner.AnimState:Show("HAIR")

    if owner.isplayer then
        owner.AnimState:Show("HEAD")
        owner.AnimState:Hide("HEAD_HAT")
        owner.AnimState:Hide("HEAD_HAT_NOHELM")
        owner.AnimState:Hide("HEAD_HAT_HELM")
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("plantregistryhat")
    inst.AnimState:SetBuild("hat_plantregistry")
    inst.AnimState:PlayAnimation("anim")

    inst:AddTag("hat")
    inst:AddTag("wallflower_monocle")

    MakeInventoryFloatable(inst)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inventoryitem")
    -- Reuse the Gardeneer Hat's inventory icon too (not just its equip/carry build), since we
    -- don't have custom Wallflower art yet -- without this, the game can't find an icon named
    -- "monocle_wallflower.tex" in any inventoryimages atlas and shows a blank slot.
    inst.replica.inventoryitem:SetImage("plantregistryhat")

    inst:AddComponent("inspectable")

    inst:AddComponent("equippable")
    inst.components.equippable.equipslot = EQUIPSLOTS.HEAD
    inst.components.equippable:SetOnEquip(onequip)
    inst.components.equippable:SetOnUnequip(onunequip)

    MakeHauntableLaunch(inst)

    return inst
end

return Prefab("monocle_wallflower", fn, assets)
