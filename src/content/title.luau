--!strict
-- The Title screen's lettering (docs/design/feel.md, "Title screen"): the
-- heading's font ("Amy" and "& the Rain Forest", a hand-written script
-- like the story website's) and the pill label's. To try another, change
-- FAMILY: one of Roblox's built-in families
-- ("rbxasset://fonts/families/<Name>.json": Kalam, IndieFlower,
-- PatrickHand, AmaticSC). A Creator Store family, referenced by its asset
-- id, first needs a font kind in assets/manifest.json (docs/ASSETS.md):
-- tier 0 allows only the manifest's asset ids. A weight is a FontWeight
-- name.

export type Lettering = { family: string, weight: string }

local FAMILY = "rbxasset://fonts/families/Kalam.json"

return {
	heading = { family = FAMILY, weight = "Bold" } :: Lettering,
	pill = { family = FAMILY, weight = "Regular" } :: Lettering,
}
