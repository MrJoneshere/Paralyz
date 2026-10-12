--!strict
-- Paralyz / src/place.luau
-- Subplace / main-place detection + per-place variation data (user order:
-- "detect which subplace user is in or if they are in main place so that
-- script can be variated across subplaces and mainplace").
--
-- The hub NEVER moves the user across places (that would rip them out of
-- their server) - this module only describes where they are so every other
-- module can vary behavior: planet lists, machine availability, labels.
-- All queries are live (workspace + game.PlaceId), so a rejoin anywhere
-- is picked up with no restart.

return function(_deps)
	local place = {}

	local workspace = game:GetService("Workspace")

	-- Known places (universe u8751492147). Unknown placeIds get live data
	-- with static fields nil - callers must handle that (hasPlanet covers
	-- it: live workspace check, never the static list).
	local INFO: { [number]: { name: string, planets: { string }, converter: boolean, ionizer: boolean } } = {
		[133579701570149] = {
			name = "main",
			planets = { "Planet1", "Planet2", "Planet3", "Planet4", "Planet5", "Planet6" },
			converter = true,
			ionizer = true,
		},
		[77683185698128] = {
			name = "Pluto/Kuiper subplace",
			planets = { "Planet6", "Planet11", "Planet12", "Planet13", "Planet14", "Planet15" },
			converter = true, -- City.ConverterMachine, insert-only prompt
			ionizer = false,
		},
	}

	function place.id(): number
		return game.PlaceId
	end

	function place.isMain(): boolean
		return game.PlaceId == 133579701570149
	end

	function place.info()
		return INFO[game.PlaceId]
	end

	function place.name(): string
		local info = INFO[game.PlaceId]
		if info then
			return info.name
		end
		return "place-" .. tostring(game.PlaceId)
	end

	-- Live check: does this planet exist in THIS server right now.
	function place.hasPlanet(name: string): boolean
		local planets = workspace:FindFirstChild("Planets")
		return planets ~= nil and planets:FindFirstChild(name) ~= nil
	end

	-- Live list of planet folder names present right now.
	function place.livePlanets(): { string }
		local out: { string } = {}
		local planets = workspace:FindFirstChild("Planets")
		if planets then
			for _, p in ipairs(planets:GetChildren()) do
				table.insert(out, p.Name)
			end
			table.sort(out)
		end
		return out
	end

	-- Static-list planets that also exist live (safe teleport/farm targets).
	function place.knownLivePlanets(): { string }
		local info = INFO[game.PlaceId]
		if not info then
			return place.livePlanets()
		end
		local out: { string } = {}
		for _, name in ipairs(info.planets) do
			if place.hasPlanet(name) then
				table.insert(out, name)
			end
		end
		return out
	end

	function place.hasConverter(): boolean
		local info = INFO[game.PlaceId]
		if info ~= nil then
			return info.converter
		end
		return workspace:FindFirstChild("City") ~= nil
			and workspace.City:FindFirstChild("ConverterMachine") ~= nil
	end

	return place
end
