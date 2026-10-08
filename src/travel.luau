--!strict
-- Paralyz / src/travel.luau
-- Teleport, noclip and fly.
--
-- Destinations resolve lazily: planets and structures come and go as the story
-- phases advance, so a destination is a function, not a stored coordinate.

return function(deps)
	local config = deps.config
	local state = deps.state
	local util = deps.util

	local UserInputService = game:GetService("UserInputService")

	local travel = {}

	---------------------------------------------------------------- helpers
	local function anchorOf(path: { string }): Vector3?
		local inst: Instance? = workspace
		for _, name in ipairs(path) do
			if not inst then
				return nil
			end
			inst = (inst :: any):FindFirstChild(name)
		end
		if not inst then
			return nil
		end
		if inst:IsA("BasePart") then
			return (inst :: BasePart).Position
		end
		local part = (inst :: any):FindFirstChildWhichIsA("BasePart", true)
		return part and (part :: BasePart).Position or nil
	end

	local function planetCentre(n: number): Vector3?
		local planets = workspace:FindFirstChild("Planets")
		local planet = planets and planets:FindFirstChild("Planet" .. n)
		if not planet then
			return nil
		end
		if planet:IsA("BasePart") then
			return (planet :: BasePart).Position
		end
		local centre = (planet :: any):FindFirstChild("Center")
		if centre and centre:IsA("BasePart") then
			return (centre :: BasePart).Position
		end
		local anyPart = (planet :: any):FindFirstChildWhichIsA("BasePart", true)
		return anyPart and (anyPart :: BasePart).Position or nil
	end

	-- Position of the prompt holder for a machine prompt (the ionizer and
	-- anti converter both hang their ProximityPrompt off a "PartProximity"
	-- BasePart inside the machine).
	local function promptPos(get: () -> ProximityPrompt?): Vector3?
		local prompt = get()
		if not prompt then
			return nil
		end
		local holder = prompt.Parent
		if holder and holder:IsA("BasePart") then
			return (holder :: BasePart).Position
		end
		local part = holder and (holder :: Instance):FindFirstChildWhichIsA("BasePart", true)
		return part and (part :: BasePart).Position or nil
	end

	-- Live centre of the planet currently hosting the Space Station (the
	-- anti converter rides along with it). Folders do not stream, so this
	-- resolves even when the station's parts are unloaded.
	local function stationPlanetCentre(): Vector3?
		local planets = workspace:FindFirstChild("Planets")
		if planets then
			for _, p in ipairs((planets :: Folder):GetChildren()) do
				if p:FindFirstChild("SpaceStation") then
					local c = (p :: any):FindFirstChild("Center")
					if c and c:IsA("BasePart") then
						return (c :: BasePart).Position
					end
				end
			end
		end
		return planetCentre(1)
	end

	-- A destination is a function, not a coordinate: structures stream with
	-- distance and planets DRIFT across the round, so positions are always
	-- read live. Optional seed() names a living relative of the destination
	-- (usually its planet): when resolve() is nil the teleport goes and
	-- stands on the seed instead - the load then brings the destination
	-- back and the re-resolve finds the real spot. This beats remembered
	-- coordinates, which go stale the moment the planet moves.
	type Dest = {
		name: string,
		group: string,
		resolve: () -> Vector3?,
		seed: (() -> Vector3?)?,
		-- Machine destinations resolve to the prompt holder itself, which
		-- sits UNDER the station's roof deck: dropToSurface would land on
		-- top of the hull, 200+ studs out of the prompt's 10-stud range.
		-- Precise destinations land directly on the resolved position
		-- (same +3 as the farm's convert walks).
		precise: boolean?,
	}

	-- Planet names are the story's names (P1 Earth, P2 Moon, P3 Venus,
	-- P4 Mars, P5 Mercury, P6 Pluto), not the internal PlanetN folders.
	local destinations: { Dest } = {
		{ name = "Bunker", group = "hub", resolve = function() return anchorOf({ "Bunker" }) end, seed = nil },
		{ name = "City", group = "hub", resolve = function() return anchorOf({ "City" }) end, seed = nil },
		{
			name = "Venus City",
			group = "hub",
			resolve = function() return anchorOf({ "VenusCity" }) end,
			seed = function() return planetCentre(3) end,
		},
		{
			name = "Mars City",
			group = "hub",
			resolve = function() return anchorOf({ "MarsCity" }) end,
			seed = function() return planetCentre(4) end,
		},
		{ name = "Sun", group = "landmark", resolve = function() return anchorOf({ "Sun" }) end, seed = nil },
		{
			name = "Space Station",
			group = "station",
			resolve = function()
				local planets = workspace:FindFirstChild("Planets")
				if not planets then
					return nil
				end
				for _, p in ipairs((planets :: Folder):GetChildren()) do
					local station = p:FindFirstChild("SpaceStation")
					local part = station and (station :: Instance):FindFirstChildWhichIsA("BasePart", true)
					if part then
						return (part :: BasePart).Position
					end
				end
				return nil
			end,
			seed = stationPlanetCentre,
		},
		{
			name = "Ionizer",
			group = "ionizer",
			resolve = function() return promptPos(util.ionizerPrompt) end,
			-- The ionizer was measured on Pluto (Planet6.PlutoIndustries).
			seed = function() return planetCentre(6) end,
			precise = true,
		},
		{
			name = "Converter",
			group = "converter",
			resolve = function() return promptPos(util.converterPrompt) end,
			-- The anti converter lives on the Space Station, wherever it orbits.
			seed = stationPlanetCentre,
			precise = true,
		},
		{ name = "Earth", group = "planet", resolve = function() return planetCentre(1) end, seed = nil },
		{ name = "Moon", group = "planet", resolve = function() return planetCentre(2) end, seed = nil },
		{ name = "Venus", group = "planet", resolve = function() return planetCentre(3) end, seed = nil },
		{ name = "Mars", group = "planet", resolve = function() return planetCentre(4) end, seed = nil },
		{ name = "Mercury", group = "planet", resolve = function() return planetCentre(5) end, seed = nil },
		{ name = "Pluto", group = "planet", resolve = function() return planetCentre(6) end, seed = nil },
	}
	travel.destinations = destinations

	-- Saved selections from earlier versions used the internal names.
	local aliases: { [string]: string } = {
		["Planet 1"] = "Earth",
		["Planet 2"] = "Moon",
		["Planet 3"] = "Venus",
		["Planet 4"] = "Mars",
		["Planet 5"] = "Mercury",
		["Planet 6"] = "Pluto",
	}

	function travel.destinationNames(): { string }
		local out = {}
		for _, d in ipairs(travel.destinations) do
			table.insert(out, d.name)
		end
		return out
	end

	function travel.availableDestinations(): { string }
		local out = {}
		for _, d in ipairs(travel.destinations) do
			if d.resolve() then
				table.insert(out, d.name)
			end
		end
		return out
	end

	-- Session-local memory of where destinations were when they last
	-- existed: content unloads with distance, so "not in this world" often
	-- just means "not loaded yet". Teleporting to the last-known spot lets
	-- streaming bring it back, then the destination re-resolves fresh.
	local known: { [string]: Vector3 } = {}

	-- Old saved selections and scripts used the internal "Planet N" names.
	function travel.canonical(name: string): string
		return aliases[name] or name
	end

	-- Set the CFrame and confirm it stuck after a beat: a respawn, a
	-- story cutscene or an external script can swallow a single write,
	-- and the old code only ever verified planet landings.
	local function landVerified(target: Vector3, tries: number, precise: boolean?): boolean
		for _ = 1, tries do
			local root = util.root()
			if not root then
				task.wait(0.4)
				continue
			end
			-- Precise targets (machine prompts under a roof deck) must not
			-- surface-drop: the deck above would swallow the landing.
			local spot = if precise then target + Vector3.new(0, 3, 0) else util.dropToSurface(target)
			local land = CFrame.new(spot)
			root.CFrame = land
			util.teleported(land)
			task.wait(0.25)
			local after = util.root()
			-- "Did the write stick?" is answered against the spot we aimed
			-- at (surface drops land hundreds of studs from a planet's
			-- centre by design); precise targets also demand proximity to
			-- the machine itself, since that is the whole point.
			local stuck = after and util.dist(after.Position, spot) < (if precise then 15 else 400)
			if stuck then
				return true
			end
		end
		return false
	end

	-- Teleport to a named destination. Planet "Center" parts are the planet
	-- itself, so landing uses the shared surface raycast: drop from above
	-- and land on the ground, never inside the geometry. Blind or planet
	-- destinations additionally wait for the load before a verified
	-- re-landing; fresh resolves get a short verify + retry as well.
	function travel.to(name: string): boolean
		name = travel.canonical(name)
		local entry: Dest? = nil
		for _, d in ipairs(travel.destinations) do
			if d.name == name then
				entry = d
				break
			end
		end
		if not entry then
			return false
		end
		local dest: Dest = entry

		local pos = dest.resolve()
		-- blind = we are teleporting without a fresh resolve (seeded or
		-- remembered coordinate): the destination then gets a load wait and
		-- a verified re-landing, exactly like planets do.
		local blind = false
		if not pos and dest.seed then
			-- The destination's living relative (usually its planet) always
			-- knows where the neighbourhood is: planets DRIFT across the
			-- round, so a live centre beats remembered coordinates, and
			-- standing on the planet streams its structures back in.
			pos = dest.seed()
			if pos then
				blind = true
				util.notify("Teleport", dest.name .. " is not loaded - going to its planet first")
			end
		end
		if not pos then
			-- Unloaded but visited this session: go to where it was and let
			-- the load bring it back (checked again after the wait below).
			local cached = known[dest.name]
			if cached then
				pos = cached
				blind = true
				util.notify("Teleport", dest.name .. " is not loaded - going to its last position")
			end
		end
		if not pos then
			-- Never visited this session but the hub has a measured spawn
			-- anchor: standing on it streams the structure back in. Without
			-- this, a hub request from across the world silently fell back
			-- to a different hub (Bunker -> Venus City).
			local seeded = config.travel.hubFallbacks[dest.name]
			if seeded then
				pos = seeded
				blind = true
				util.notify("Teleport", dest.name .. " is not loaded - going to its usual spot")
			end
		end
		if not pos then
			-- Genuinely not in this world phase: fall back to a sibling in
			-- the same group instead of failing outright (fresh resolve, so
			-- no confirm wait needed for the destination we end up at).
			for _, alt in ipairs(travel.destinations) do
				if alt.group == dest.group and alt.name ~= dest.name then
					local altPos = alt.resolve()
					if altPos then
						util.notify(
							"Teleport",
							dest.name .. " is not in this world - going to " .. alt.name
						)
						dest = alt
						pos = altPos
						known[alt.name] = altPos
						break
					end
				end
			end
		end
		if not pos then
			util.notify("Teleport failed", name .. " is not in this world yet - get near it once so it can load")
			return false
		end

		local root = util.root()
		if not root then
			return false
		end
		-- Rough hop first (streams the area while the load wait runs).
		-- Precise targets skip the surface drop - but only when the
		-- position is the machine itself; a blind seed is still a planet
		-- centre, which needs the drop like any planet.
		local rough = if dest.precise and not blind
			then pos + Vector3.new(0, 3, 0)
			else util.dropToSurface(pos)
		root.CFrame = CFrame.new(rough)
		util.teleported(root.CFrame)

		-- The destination may have been teleported to blind, or may be a
		-- planet whose rocks stream in seconds after arrival: wait for the
		-- load, re-resolve in case the real position differs from the
		-- remembered one, and ALWAYS land on the fresh spot afterwards (the
		-- old code skipped this when re-resolving failed, which is exactly
		-- the "it loads but never takes me there" the user had to spam past).
		if blind or dest.group == "planet" then
			local n = 0
			local fresh: Vector3? = nil
			if dest.group == "planet" then
				-- Planets prove their load with rocks.
				n = util.settleRocks(pos, config.farm.loadWait, config.farm.streamRadius)
				fresh = dest.resolve()
			else
				-- Hubs prove it by re-resolving: the folder is always
				-- there, its structure parts only exist once streamed.
				local deadline = os.clock() + config.farm.loadWait
				while os.clock() < deadline do
					fresh = dest.resolve()
					if fresh then
						break
					end
					task.wait(0.5)
				end
			end
			local resolved = fresh ~= nil
			fresh = fresh or pos
			known[dest.name] = fresh
			-- landVerified re-fetches the root each try: the wait is long
			-- enough for a respawn, and a stale BasePart reference silently
			-- does nothing. Precise only when the position came from a
			-- resolve (the machine); a fallback to the seed is a planet
			-- centre and needs the surface drop.
			local landed = landVerified(fresh, 4, dest.precise and resolved)
			local suffix
			if not landed then
				suffix = " - load wait ended but the landing would not stick"
			elseif dest.group == "planet" and n > 0 then
				suffix = " - loaded, " .. n .. " rocks"
			elseif dest.group == "planet" then
				suffix = " - still empty after waiting"
			elseif dest.resolve() then
				suffix = " - loaded"
			else
				suffix = " - did not load, it may not exist in this phase"
			end
			util.notify("Teleport", dest.name .. suffix)
		else
			-- Fresh resolve: still verify, just with a short budget. The
			-- first write above can be swallowed by a respawn or a story
			-- cutscene, and a teleport that silently does nothing is the
			-- worst failure mode this button can have.
			known[dest.name] = pos
			if not landVerified(pos, 2, dest.precise) then
				util.notify("Teleport failed", dest.name .. " - the landing would not stick, try again")
				return false
			end
		end
		return true
	end

	-- Teleport somewhere the menu names but the module does not hardcode,
	-- e.g. "nearest rock".
	function travel.toPosition(pos: Vector3): boolean
		if not util.root() then
			return false
		end
		return landVerified(pos + Vector3.new(0, 6, 0), 3)
	end

	------------------------------------------------------------------ noclip
	local noclipConn: RBXScriptConnection? = nil

	local function setNoclip(on: boolean)
		if on then
			if noclipConn then
				return
			end
			noclipConn = util.RunService.Stepped:Connect(function()
				local char = util.character()
				if not char then
					return
				end
				for _, part in ipairs(char:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = false
					end
				end
			end)
		else
			if noclipConn then
				noclipConn:Disconnect()
				noclipConn = nil
			end
			local char = util.character()
			if char then
				for _, part in ipairs(char:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = true
					end
				end
			end
		end
	end

	--------------------------------------------------------------------- fly
	local flying = false
	local flyConn: RBXScriptConnection? = nil

	local function setFly(on: boolean)
		if on == flying then
			return
		end
		flying = on
		if not on then
			if flyConn then
				flyConn:Disconnect()
				flyConn = nil
			end
			local char = util.character()
			local root = util.root()
			local hum = util.humanoid()
			-- The fly loop parks the humanoid in Physics every frame; without
			-- an explicit recovery the character stays frozen and cannot walk
			-- again after the toggle goes off.
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
			end
			if hum then
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				if hum:GetState() == Enum.HumanoidStateType.Physics then
					hum:ChangeState(Enum.HumanoidStateType.Running)
				end
			end
			-- Give collisions back unless the Noclip toggle wants them off.
			if not state.enabled("Noclip") and char then
				for _, part in ipairs(char:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = true
					end
				end
			end
			return
		end

		flyConn = util.RunService.Heartbeat:Connect(function(dt)
			local root = util.root()
			local hum = util.humanoid()
			if not root or not hum then
				return
			end

			-- Flying ignores geometry on its own: without this the higher
			-- speed would just slam into walls whenever Noclip is off.
			local char = util.character()
			if char then
				for _, part in ipairs(char:GetDescendants()) do
					if part:IsA("BasePart") and part.CanCollide then
						part.CanCollide = false
					end
				end
			end

			-- Camera-relative movement, driven by the same keys the player uses.
			local cam = workspace.CurrentCamera
			if not cam then
				return
			end
			local cf = cam.CFrame
			local move = Vector3.zero

			local function pressed(key: Enum.KeyCode): boolean
				return UserInputService:IsKeyDown(key)
			end

			if pressed(Enum.KeyCode.W) then
				move += cf.LookVector
			end
			if pressed(Enum.KeyCode.S) then
				move -= cf.LookVector
			end
			if pressed(Enum.KeyCode.A) then
				move -= cf.RightVector
			end
			if pressed(Enum.KeyCode.D) then
				move += cf.RightVector
			end
			if pressed(Enum.KeyCode.Space) then
				move += Vector3.yAxis
			end
			if pressed(Enum.KeyCode.LeftControl) then
				move -= Vector3.yAxis
			end

			if move.Magnitude > 0 then
				move = move.Unit * config.travel.flySpeed * 60 * dt
			end

			hum:ChangeState(Enum.HumanoidStateType.Physics)
			root.AssemblyLinearVelocity = move
			root.CFrame = root.CFrame + move
		end)
	end

	------------------------------------------------------------------ toggle
	-- One entry point the menu calls: state key -> side effect.
	function travel.sync()
		setNoclip(state.enabled("Noclip"))
		setFly(state.enabled("Fly"))
	end

	function travel.stop()
		setNoclip(false)
		setFly(false)
	end

	return travel
end
