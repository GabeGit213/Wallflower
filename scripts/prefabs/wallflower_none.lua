local assets =
{
	Asset( "ANIM", "anim/wallflower.zip" ),
	Asset( "ANIM", "anim/ghost_wallflower_build.zip" ),
}

-- NOTE: these must stay pinned to "esctemplate" / "ghost_esctemplate_build" — that's the
-- actual build name baked inside anim/wallflower.zip and anim/ghost_wallflower_build.zip by
-- Klei's autocompiler when the template art was exported (renaming the .zip files doesn't
-- rename the build data inside them). Update these once real Wallflower art is compiled
-- with a build actually named "wallflower".
local skins =
{
	normal_skin = "esctemplate",
	ghost_skin = "ghost_esctemplate_build",
}

return CreatePrefabSkin("wallflower_none",
{
	base_prefab = "wallflower",
	type = "base",
	assets = assets,
	skins = skins,
	skin_tags = {"WALLFLOWER", "CHARACTER", "BASE"},
	build_name_override = "esctemplate",
	rarity = "Character",
})