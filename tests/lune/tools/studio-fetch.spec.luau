local Fetch = require("../../../tools/studio-playtest/fetch")

local TREE: Fetch.Described = {
	name = "Low Poly Tree",
	creator = "Remadex Development",
	free = true,
	classes = { Model = 1, MeshPart = 2, Weld = 1 },
}

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

		t.it("refuses what is not base64", function()
			t.expectError(function()
				Fetch.base64Decode("abc")
			end, "not base64")
			t.expectError(function()
				Fetch.base64Decode("ab$c")
			end, "not base64")
		end)

		t.it("takes a free model without scripts", function()
			t.expect(Fetch.refusal(TREE)).toBeNil()
		end)

		t.it("refuses a model that carries code, naming each kind", function()
			local infected = table.clone(TREE)
			infected.classes = { Model = 1, Script = 2, LocalScript = 1, ModuleScript = 1 }
			t.expect(Fetch.refusal(infected)).toBe(
				"'Low Poly Tree' carries code (1 LocalScript, 1 ModuleScript, 2 Script); only models without scripts are fetched"
			)
		end)

		t.it("refuses a model that is not free", function()
			local paid = table.clone(TREE)
			paid.free = false
			t.expect(Fetch.refusal(paid)).toBe("'Low Poly Tree' is not free on the Creator Store")
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

		t.it("runs its Studio scripts against the inserted model's path", function()
			local path = 'game.ServerStorage["Low Poly Tree"]'
			t.expect(string.find(Fetch.describeScript(path, "12549617200"), path, 1, true) ~= nil).toBe(true)
			t.expect(
				string.find(Fetch.describeScript(path, "12549617200"), "GetProductInfoAsync(12549617200)", 1, true)
					~= nil
			)
				.toBe(true)
			t.expect(
				string.find(Fetch.serialiseScript(path), "SerializeInstancesAsync({ " .. path .. " })", 1, true) ~= nil
			)
				.toBe(true)
		end)
	end)
end
