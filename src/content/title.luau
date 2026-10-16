--!strict
-- The Title screen's lettering (docs/design/feel.md, "Title screen"): the
-- heading's font ("Amy" and "& the Rain Forest") and the pill label's, the
-- story website's Dancing Script. A family is either the Asset name of a
-- manifest entry of kind font ("font:dancing_script"), which the binder
-- looks up in AssetIds, or a built-in family's path
-- ("rbxasset://fonts/families/<Name>.json", such as Kalam). A weight is a
-- FontWeight name.

export type Lettering = { family: string, weight: string }

local FAMILY = "font:dancing_script"

return {
	heading = { family = FAMILY, weight = "Bold" } :: Lettering,
	pill = { family = FAMILY, weight = "SemiBold" } :: Lettering,
}
