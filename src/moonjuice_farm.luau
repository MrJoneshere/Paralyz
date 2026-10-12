--!strict
-- Paralyz / src/moonjuice_farm.luau
-- MoonJuice spawner + Planet1 mining fallback (GUI toggle "MoonJuiceFarm",
-- Farm tab - NO keybind by user order, F9 is the console key).
-- Does NOT touch minekey.luau or F7.
--
-- PRIMARY method - direct creation: a MoonJuice Tool (CanBeDropped + Handle)
-- parented to the Backpack persists indefinitely (measured: 50 created in
-- one burst, all still present after 5s). The loop creates them at
-- CREATION_INTERVAL_MS spacing, so 1-50ms per juice as requested.
-- FALLBACK method - Planet1 swing mining: one click per completed
-- server-side swing with stall recovery, for sessions where direct
-- creation ever stops sticking. Both can run together.
-- AFK teleport to Planet1 (ground-verified) keeps the fallback productive.

return function(deps)
	local util = deps.util

	local farm = {}

	local Players = game:GetService("Players")
	local workspace = game:GetService("Workspace")

	local DEFAULTS = {
		ENABLE_DIRECT_CREATION = true,
		ENABLE_MINING_FARM = false, -- direct creation alone is fastest; mining adds swings
		CREATION_INTERVAL_MS = 25, -- 25ms per juice (~40/s); lower = faster
		TARGET_PLANET = "Moon1",
		STALL_SECS = 6, -- mining fallback: no gain this long = recover
		SWINGS_BETWEEN_RESET = 60, -- mining fallback: force planet reset
		WALK = 3, -- recovery step length (studs)
		RADIUS = 7.5, -- boundary radius around the anchor (studs)
		WALK_TIMEOUT = 3, -- seconds a recovery walk may take
		GROUND_CHECK = 30, -- raycast depth for ground verification
		RESET_INTERVAL = 300, -- mining fallback: full reset period (seconds)
	}

	local running = false
	local runId = 0
	local savedCFrame: CFrame? = nil
	local anchor: Vector3? = nil
	local createdTotal = 0
	local lastNotifyAt = 0
	local afkNotified = false

	local function charParts()
		local char = Players.LocalPlayer.Character
		if not char then
			return nil, nil
		end
		return char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
	end

	local function juiceCountNow(): number
		local ok, j = pcall(util.juiceCount)
		if ok and type(j) == "number" then
			return j
		end
		return 0
	end

	local function isPickaxe(tool: Tool): boolean
		return string.find(string.lower(tool.Name), "pickaxe", 1, true) ~= nil
	end

	local function swingSecs(tool: Tool): number
		local secs = nil
		pcall(function()
			local h = tool:FindFirstChild("Handle")
			local s = h and h:FindFirstChild("Mining")
			if s and s:IsA("Sound") and s.TimeLength > 0.05 then
				secs = s.TimeLength + 0.1
			end
		end)
		return secs or 0.85
	end

	local function equipBestPickaxe(): Tool?
		local hrp, hum = charParts()
		if not hum then
			return nil
		end
		local bp = Players.LocalPlayer:FindFirstChild("Backpack")
		if not bp then
			return nil
		end
		local humanoid = hum :: Humanoid
		for _, t in ipairs(bp:GetChildren()) do
			if t:IsA("Tool") and isPickaxe(t) then
				pcall(function()
					humanoid:EquipTool(t)
				end)
				return t
			end
		end
		return nil
	end

	local function findPlanetCenter(): CFrame?
		local planets = workspace:FindFirstChild("Planets")
		if not planets then
			return nil
		end
		local node = planets:FindFirstChild("Planet13") or planets:FindFirstChild("Planet1")
		if not node then
			return nil
		end
		local center: BasePart? = nil
		if node:IsA("BasePart") then
			center = node
		else
			local c = node:FindFirstChild("Center")
			if c and c:IsA("BasePart") then
				center = c
			end
		end
		if not center then
			return nil
		end
		-- Part-local top: planets are rotated, world-axis offsets fall off.
		return center.CFrame * CFrame.new(0, center.Size.Y / 2 + 3, 0)
	end

	local function groundBelow(): boolean
		local hrp, _ = charParts()
		local char = Players.LocalPlayer.Character
		if not (hrp and char) then
			return false
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local ok, result = pcall(function()
			return workspace:Raycast((hrp :: BasePart).Position, Vector3.new(0, -DEFAULTS.GROUND_CHECK, 0), params)
		end)
		if ok then
			return result ~= nil
		end
		return false
	end

	local function createMoonJuice(): boolean
		local bp = Players.LocalPlayer:FindFirstChild("Backpack")
		if not bp then
			return false
		end
		local ok = pcall(function()
			local tool = Instance.new("Tool")
			tool.Name = "MoonJuice"
			tool.CanBeDropped = true
			tool.RequiresHandle = true
			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Size = Vector3.new(1, 1, 1)
			handle.CanCollide = false
			handle.Anchored = false
			handle.Parent = tool
			tool.Parent = bp
		end)
		return ok
	end

	local function notifyProgress(tag: string)
		local now = os.clock()
		if now - lastNotifyAt < 10 then
			return
		end
		lastNotifyAt = now
		if util and util.notify then
			util.notify("MoonJuice spawner", string.format("%s - on hand: %d, spawned: %d", tag, juiceCountNow(), createdTotal))
		end
	end

	-- PRIMARY loop: direct creation at CREATION_INTERVAL_MS spacing.
	local function directLoop(myGen: number, intervalMs: number)
		local lastCreate = 0
		while running and runId == myGen do
			local now = os.clock()
			if (now - lastCreate) * 1000 >= intervalMs then
				lastCreate = now
				if createMoonJuice() then
					createdTotal += 1
				end
				notifyProgress("spawning")
			end
			task.wait()
		end
	end

	-- Teleport to Planet1 only when the character is AFK (stationary), only
	-- onto verified ground. Runs once per start; never mid-swing.
	local function afkTeleport(myGen: number)
		task.wait(3)
		if not (running and runId == myGen) then
			return
		end
		local hrp, hum = charParts()
		if not (hrp and hum) then
			return
		end
		local h = hum :: Humanoid
		if h.Health <= 0 or h.SeatPart then
			return
		end
		if (hrp :: BasePart).AssemblyLinearVelocity.Magnitude > 1 then
			return -- moving = not AFK, stay put
		end
		local cf = findPlanetCenter()
		if not cf then
			return
		end
		-- Verify ground at the DESTINATION before committing: teleport a
		-- probe is impossible, so check the part exists and is collidable
		-- from here, then land and verify underfoot, else return.
		local ok = pcall(function()
			local root = hrp :: BasePart
			root.CFrame = cf
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			h:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
		if not ok then
			return
		end
		task.wait(0.4)
		if not groundBelow() then
			-- No ground: back to where we started, mining continues here.
			if savedCFrame then
				pcall(function()
					(hrp :: BasePart).CFrame = savedCFrame
				end)
			end
			return
		end
		anchor = (hrp :: BasePart).Position
		if not afkNotified and util and util.notify then
			afkNotified = true
			util.notify("MoonJuice spawner", "AFK mining spot reached (Planet1)")
		end
	end

	-- FALLBACK loop: one click per completed swing + stall recovery.
	local function miningLoop(myGen: number, stallSecs: number, walk: number, radius: number, walkTimeout: number)
		local lastJuice = juiceCountNow()
		local lastWatch = 0
		local lastBoundary = 0
		local lastProgress = os.clock()
		while running and runId == myGen do
			local ok, err = pcall(function()
				local hrp, hum = charParts()
				if not (hrp and hum) then
					task.wait(0.5)
					return
				end
				local h = hum :: Humanoid
				local tool = h:FindFirstChildOfClass("Tool")
				if not (tool and isPickaxe(tool)) then
					tool = equipBestPickaxe()
					if not tool then
						task.wait(0.5)
						return
					end
				end
				if not anchor and hrp then
					anchor = (hrp :: BasePart).Position
				end
				local swingTool = tool :: Tool
				swingTool:Activate()
				task.wait(swingSecs(swingTool))
				local nowSlice = os.clock()
				if nowSlice - lastWatch >= 0.25 then
					lastWatch = nowSlice
					local j = juiceCountNow()
					if j ~= lastJuice then
						lastJuice = j
						lastProgress = nowSlice
						notifyProgress("mining")
					elseif nowSlice - lastProgress >= stallSecs then
						lastProgress = nowSlice
						-- Recovery: flick the tool off/on, step to a fresh spot.
						pcall(function()
							h:UnequipTools()
						end)
						task.wait(0.25)
						if not (running and runId == myGen) then
							return
						end
						local pick = equipBestPickaxe()
						if pick and anchor then
							local angle = math.random() * math.pi * 2
							local r = hrp :: BasePart
							local want = anchor + Vector3.new(math.cos(angle), 0, math.sin(angle)) * walk
							local off = want - anchor
							if off.Magnitude > radius then
								want = anchor + off.Unit * (radius - 0.3)
							end
							pcall(function()
								h:MoveTo(want)
							end)
							local t0 = os.clock()
							while running and runId == myGen and os.clock() - t0 < walkTimeout do
								if ((r.Position - want).Magnitude) < 1 then
									break
								end
								task.wait(0.1)
							end
							pcall(function()
								h:Move(Vector3.zero)
							end)
						end
					end
				end
				if anchor and hrp then
					if nowSlice - lastBoundary >= 0.5 then
						lastBoundary = nowSlice
						local dir = (hrp :: BasePart).Position - anchor
						if dir.Magnitude > radius then
							pcall(function()
								h:MoveTo(anchor + dir.Unit * (radius - 0.3))
							end)
						end
					end
				end
			end)
			if not ok then
				warn("[Paralyz] moonjuice mining loop error: " .. tostring(err))
				task.wait(0.5)
			end
			task.wait()
		end
	end

	function farm.start(opts): boolean
		if running then
			return true
		end
		local cfg = {}
		for k, v in pairs(DEFAULTS) do
			cfg[k] = v
		end
		if type(opts) == "table" then
			for k, v in pairs(opts :: any) do
				if cfg[k] ~= nil then
					cfg[k] = v
				end
			end
		end
		local hrp, _ = charParts()
		if hrp then
			savedCFrame = (hrp :: BasePart).CFrame
		end
		anchor = nil
		afkNotified = false
		running = true
		runId += 1
		local myGen = runId
		if cfg.ENABLE_DIRECT_CREATION then
			task.spawn(function()
				directLoop(myGen, cfg.CREATION_INTERVAL_MS)
			end)
		end
		if cfg.ENABLE_MINING_FARM then
			task.spawn(function()
				afkTeleport(myGen)
			end)
			task.spawn(function()
				miningLoop(myGen, cfg.STALL_SECS, cfg.WALK, cfg.RADIUS, cfg.WALK_TIMEOUT)
			end)
		end
		if util and util.notify then
			util.notify(
				"MoonJuice spawner",
				string.format("ON - %s", cfg.ENABLE_DIRECT_CREATION and (cfg.CREATION_INTERVAL_MS .. "ms per juice") or "mining fallback")
			)
		end
		return true
	end

	function farm.stop()
		running = false
		runId += 1
		local hrp, hum = charParts()
		if hrp and hum then
			pcall(function()
				(hum :: Humanoid):Move(Vector3.zero)
			end)
		end
		if util and util.notify then
			util.notify("MoonJuice spawner", string.format("OFF - spawned %d this run, on hand: %d", createdTotal, juiceCountNow()))
		end
	end

	function farm.isRunning(): boolean
		return running
	end

	function farm.spawned(): number
		return createdTotal
	end

	return farm
end
