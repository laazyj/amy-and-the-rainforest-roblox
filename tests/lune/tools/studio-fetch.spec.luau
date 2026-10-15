local Fetch = require("../../../tools/studio-playtest/fetch")

local luau = require("@lune/luau")
local serde = require("@lune/serde")

local TREE: Fetch.Described = {
	name = "Low Poly Tree",
	creator = "Remadex Development",
	free = true,
	classes = { Model = 2, MeshPart = 2, Weld = 1 },
	code = {},
}

-- A name its creator could give a model to break out of a Luau string.
local HOSTILE = 'X"]; evil() --'
local FOLDER = Fetch.folderName("12549617200", 1760000000)

-- An instance as the in-Studio scripts see it.
local function instance(className: string, children: { any }?): any
	local kids = children or {}
	local scripts = { Script = true, LocalScript = true, ModuleScript = true }
	return {
		ClassName = className,
		Name = HOSTILE,
		IsA = function(_, class)
			return class == className or (class == "LuaSourceContainer" and scripts[className] == true)
		end,
		GetChildren = function()
			return kids
		end,
		GetDescendants = function(self)
			local all = {}
			for _, child in self:GetChildren() do
				table.insert(all, child)
				for _, below in child:GetDescendants() do
					table.insert(all, below)
				end
			end
			return all
		end,
	}
end

-- Runs one of Fetch's in-Studio scripts with `inserted` in the fetch
-- folder and `info` as the Creator Store's answer; returns what it returned.
local function runInStudio(source: string, inserted: { any }, info: { [string]: any }?): string
	local folder = instance("Folder", inserted)
	local services: { [string]: any } = {
		ServerStorage = {
			FindFirstChild = function(_, name)
				return if name == FOLDER then folder else nil
			end,
		},
		MarketplaceService = {
			GetProductInfoAsync = function(_, id)
				assert(id == 12549617200, "asks about the asset it inserted")
				return info or { Name = HOSTILE, Creator = { Name = "Someone" }, IsPublicDomain = true }
			end,
		},
		HttpService = {
			JSONEncode = function(_, value)
				return serde.encode("json", value)
			end,
		},
		SerializationService = {
			SerializeInstancesAsync = function(_, list)
				assert(#list == 1, "serialises the one model")
				return buffer.fromstring("<roblox!")
			end,
		},
		EncodingService = {
			Base64Encode = function(_, bytes)
				assert(buffer.tostring(bytes) == "<roblox!", "encodes the serialised bytes")
				return buffer.fromstring("PHJvYmxveCE=")
			end,
		},
	}
	local game = {
		GetService = function(_, name)
			return services[name] or error(`no service {name}`)
		end,
	}
	-- Lune adds the standard globals to the environment.
	return luau.load(source, { environment = { game = game } })()
end

local function describe(inserted: { any }, info: { [string]: any }?): Fetch.Described
	return serde.decode("json", runInStudio(Fetch.describeScript(FOLDER, "12549617200"), inserted, info))
end

return function(t: any)
	t.describe("studio-playtest fetch", function()
		t.it("decodes base64, padding included", function()
			t.expect(Fetch.base64Decode("")).toBe("")
			t.expect(Fetch.base64Decode("TQ==")).toBe("M")
			t.expect(Fetch.base64Decode("TWE=")).toBe("Ma")
			t.expect(Fetch.base64Decode("TWFu")).toBe("Man")
			t.expect(Fetch.base64Decode("PHJvYmxveCE=\n")).toBe("<roblox!")
			t.expect(Fetch.base64Decode("AP8=")).toBe("\0\255")
		end)

		t.it("refuses what is not base64, padding in the middle included", function()
			for _, text in { "abc", "ab$c", "TQ==TWFu", "T===" } do
				t.expectError(function()
					Fetch.base64Decode(text)
				end, "not base64")
			end
		end)

		t.it("takes a free model without scripts", function()
			t.expect(Fetch.refusal(TREE)).toBeNil()
		end)

		t.it("refuses a model that carries code, naming each kind", function()
			local infected = table.clone(TREE)
			infected.code = { Script = 2, LocalScript = 1, ModuleScript = 1 }
			t.expect(Fetch.refusal(infected)).toBe(
				"'Low Poly Tree' carries code (1 LocalScript, 1 ModuleScript, 2 Script); only models without scripts are fetched"
			)
		end)

		t.it("refuses a model that is not free", function()
			local paid = table.clone(TREE)
			paid.free = false
			t.expect(Fetch.refusal(paid)).toBe("'Low Poly Tree' is not free on the Creator Store")
		end)

		t.it("counts the model's root with what is under it, as Studio runs the description", function()
			local tree = instance("Model", { instance("MeshPart", { instance("Weld") }), instance("MeshPart") })
			local described = describe({ tree })
			t.expect(described.classes).toEqual({ Model = 1, MeshPart = 2, Weld = 1 })
			t.expect(Fetch.refusal(described)).toBeNil()
		end)

		t.it("catches a model that is a lone script, and every kind of script under a model", function()
			t.expect(describe({ instance("ModuleScript") }).code).toEqual({ ModuleScript = 1 })
			local mixed = instance("Model", { instance("Script"), instance("Part", { instance("LocalScript") }) })
			t.expect(describe({ mixed }).code).toEqual({ Script = 1, LocalScript = 1 })
		end)

		t.it("treats a model off sale, with no price, as not free", function()
			local described = describe({ instance("Model") }, { Name = "Tree", Creator = { Name = "Someone" } })
			t.expect(described.free).toBe(false)
			local priced = describe({ instance("Model") }, { Name = "Tree", PriceInRobux = 0 })
			t.expect(priced.free).toBe(true)
		end)

		t.it("fails unless exactly one instance was inserted", function()
			t.expectError(function()
				describe({})
			end, "expected one inserted instance, found 0")
			t.expectError(function()
				describe({ instance("Model"), instance("Model") })
			end, "expected one inserted instance, found 2")
		end)

		t.it("serialises the model, and refuses to if it holds a script by then", function()
			local source = Fetch.serialiseScript(FOLDER)
			t.expect(runInStudio(source, { instance("Model") })).toBe("PHJvYmxveCE=")
			t.expectError(function()
				runInStudio(source, { instance("Model", { instance("Script") }) })
			end, "the model carries code: Script")
		end)

		t.it("never puts the model's name into the Luau it sends Studio", function()
			local sent: { string } = {}
			local parent: string? = nil
			local bridge: any = {
				run = function(_, code)
					table.insert(sent, code)
					if string.find(code, "GetProductInfoAsync", 1, true) then
						return serde.encode("json", {
							name = HOSTILE,
							creator = HOSTILE,
							free = true,
							classes = { Model = 1 },
							code = {},
						})
					end
					return if string.find(code, "SerializeInstancesAsync", 1, true) then "PHJvYmxveCE=" else "ready"
				end,
				insertAsset = function(_, parentPath)
					parent = parentPath
				end,
			}
			local described, bytes = Fetch.fetch(bridge, "12549617200", FOLDER)
			t.expect(described.name).toBe(HOSTILE)
			t.expect(bytes).toBe("<roblox!")
			t.expect(parent).toBe(`game.ServerStorage.{FOLDER}`)
			t.expect(#sent).toBe(3)
			for _, code in sent do
				t.expect(string.find(code, "evil", 1, true)).toBeNil()
				t.expect(string.find(code, FOLDER, 1, true) ~= nil).toBe(true)
			end
		end)

		t.it("names its folder with letters, digits and underscores only", function()
			t.expect(string.match(FOLDER, "^[%w_]+$")).toBe(FOLDER)
			t.expectError(function()
				Fetch.describeScript('a"b', "1")
			end, "letters, digits and underscores")
			t.expectError(function()
				Fetch.describeScript(FOLDER, "1); evil(")
			end, "an asset id is digits")
		end)

		t.it("writes a pending manifest entry naming the Creator Store id and creator", function()
			local entry =
				Fetch.entry("prop:low_poly_tree", "assets/meshes/low-poly-tree.rbxm", "12549617200", TREE, "2026-10-14")
			t.expect(entry.kind).toBe("model")
			t.expect(entry.moderation).toBe("pending")
			t.expect(entry.licence).toBe("creator-store-free")
			t.expect(entry.creator).toBe("Remadex Development")
			t.expect(entry.assetId).toBeNil()
			t.expect(string.find(entry.origin, "Creator Store asset 12549617200", 1, true)).toBe(1)
		end)
	end)
end
