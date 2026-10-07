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

	-- Teleport to a named destination. Planet "Center" parts are the planet
	-- itself, so landing uses the shared surface raycast: drop from above
	-- and land on the ground, never inside the geometry.
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
		if not pos then
			-- The requested place is not in this world phase: fall back to a
			-- sibling in the same group instead of failing outright.
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
						break
					end
				end
			end
		end
		if not pos then
			util.notify("Teleport failed", name .. " is not in this world yet")
			return false
		end

		local root = util.root()
		if not root then
			return false
		end
		root.CFrame = CFrame.new(util.dropToSurface(pos))
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
			return
		end

		flyConn = util.RunService.Heartbeat:Connect(function(dt)
			local root = util.root()
			local hum = util.humanoid()
			if not root or not hum then
				return
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
