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

	-- Name -> resolver. Anything that does not exist yet simply reports nil.
	-- group tags a destination's siblings: when one is missing (phases come
	-- and go) travel.to falls back to another destination in its group.
	travel.destinations = {
		{ name = "Bunker", group = "hub", resolve = function() return anchorOf({ "Bunker" }) end },
		{ name = "City", group = "hub", resolve = function() return anchorOf({ "City" }) end },
		{ name = "Venus City", group = "hub", resolve = function() return anchorOf({ "VenusCity" }) end },
		{ name = "Sun", group = "landmark", resolve = function() return anchorOf({ "Sun" }) end },
		{ name = "Planet 1", group = "planet", resolve = function() return planetCentre(1) end },
		{ name = "Planet 2", group = "planet", resolve = function() return planetCentre(2) end },
		{ name = "Planet 3", group = "planet", resolve = function() return planetCentre(3) end },
		{ name = "Planet 4", group = "planet", resolve = function() return planetCentre(4) end },
		{ name = "Planet 5", group = "planet", resolve = function() return planetCentre(5) end },
		{ name = "Planet 6", group = "planet", resolve = function() return planetCentre(6) end },
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

	-- Teleport to a named destination. Planet "Center" parts are the planet
	-- itself, so landing uses the shared surface raycast: drop from above
	-- and land on the ground, never inside the geometry. After a planet
	-- landing the destination gets time to load before reporting anything.
	function travel.to(name: string): boolean
		local entry = nil
		for _, d in ipairs(travel.destinations) do
			if d.name == name then
				entry = d
				break
			end
		end
		if not entry then
			return false
		end

		local pos = entry.resolve()
		-- blind = we are teleporting without a fresh resolve (remembered or
		-- seeded coordinate): the destination then gets a load wait and a
		-- verified re-landing, exactly like planets do.
		local blind = false
		if not pos then
			-- Unloaded but visited this session: go to where it was and let
			-- the load bring it back (checked again after the wait below).
			local cached = known[entry.name]
			if cached then
				pos = cached
				blind = true
				util.notify("Teleport", entry.name .. " is not loaded - going to its last position")
			end
		end
		if not pos then
			-- Never visited this session but the hub has a measured spawn
			-- anchor: standing on it streams the structure back in. Without
			-- this, a hub request from across the world silently fell back
			-- to a different hub (Bunker -> Venus City).
			local seeded = config.travel.hubFallbacks[entry.name]
			if seeded then
				pos = seeded
				blind = true
				util.notify("Teleport", entry.name .. " is not loaded - going to its usual spot")
			end
		end
		if not pos then
			-- Genuinely not in this world phase: fall back to a sibling in
			-- the same group instead of failing outright (fresh resolve, so
			-- no confirm wait needed for the destination we end up at).
			for _, alt in ipairs(travel.destinations) do
				if alt.group == entry.group and alt.name ~= entry.name then
					local altPos = alt.resolve()
					if altPos then
						util.notify(
							"Teleport",
							entry.name .. " is not in this world - going to " .. alt.name
						)
						entry = alt
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
		local land = util.dropToSurface(pos)
		root.CFrame = CFrame.new(land)
		util.teleported(root.CFrame)

		-- The destination may have been teleported to blind, or may be a
		-- planet whose rocks stream in seconds after arrival: wait for the
		-- load, re-resolve in case the real position differs from the
		-- remembered one, and ALWAYS land on the fresh spot afterwards (the
		-- old code skipped this when re-resolving failed, which is exactly
		-- the "it loads but never takes me there" the user had to spam past).
		if blind or entry.group == "planet" then
			local n = 0
			local fresh: Vector3? = nil
			if entry.group == "planet" then
				-- Planets prove their load with rocks.
				n = util.settleRocks(pos, config.farm.loadWait, config.farm.streamRadius)
				fresh = entry.resolve()
			else
				-- Hubs prove it by re-resolving: the folder is always
				-- there, its structure parts only exist once streamed.
				local deadline = os.clock() + config.farm.loadWait
				while os.clock() < deadline do
					fresh = entry.resolve()
					if fresh then
						break
					end
					task.wait(0.5)
				end
			end
			fresh = fresh or pos
			known[entry.name] = fresh
			-- Re-fetch the root: the wait is long enough for a respawn, and a
			-- stale BasePart reference silently does nothing.
			local landed = false
			for _ = 1, 4 do
				root = util.root()
				if not root then
					task.wait(0.5)
					continue
				end
				local target = CFrame.new(util.dropToSurface(fresh))
				root.CFrame = target
				util.teleported(target)
				task.wait(0.25)
				if util.root() and util.dist(util.root().Position, target.Position) < 400 then
					landed = true
					break
				end
			end
			local suffix
			if not landed then
				suffix = " - load wait ended but the landing would not stick"
			elseif entry.group == "planet" and n > 0 then
				suffix = " - loaded, " .. n .. " rocks"
			elseif entry.group == "planet" then
				suffix = " - still empty after waiting"
			elseif entry.resolve() then
				suffix = " - loaded"
			else
				suffix = " - did not load, it may not exist in this phase"
			end
			util.notify("Teleport", entry.name .. suffix)
		else
			known[entry.name] = pos
		end
		return true
	end

	-- Teleport somewhere the menu names but the module does not hardcode,
	-- e.g. "nearest rock".
	function travel.toPosition(pos: Vector3): boolean
		local root = util.root()
		if not root then
			return false
		end
		root.CFrame = CFrame.new(pos + Vector3.new(0, 6, 0))
		util.teleported(root.CFrame)
		return true
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
			-- Give collisions back unless the Noclip toggle wants them off.
			if not state.enabled("Noclip") then
				local char = util.character()
				if char then
					for _, part in ipairs(char:GetDescendants()) do
						if part:IsA("BasePart") then
							part.CanCollide = true
						end
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
