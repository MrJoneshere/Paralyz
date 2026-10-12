--!strict
-- Paralyz / src/safezone.luau
-- Safe zone: a PRIVATE client-side platform for AFK working (user order
-- 2026-10-12: "get rid of that keybind it should be a button in gui...
-- the safezone place is a dangerous place where i died, we need to create
-- a place client side, like just a platform far away from others so we
-- can stand there while you work").
--
-- Why client-side (reversal of the old design): the old module teleported
-- to real planet geometry, but planets host NPC enemies that wandered over
-- and killed the AFK character. A client-created platform is unknown to
-- the server, so no NPC can path to it, no player can see or reach it, and
-- it sits ~2000 studs above everything - effectively a private room.
--
-- KNOWN CAVEAT (in the GUI description too): dropped tools fall by SERVER
-- physics, which does not know the platform - anything dropped up here
-- falls straight through to the ground far below. Stand here, do NOT test
-- drops here.
--
-- Toggle ON: save CFrame, (re)position the platform above the character,
-- teleport on top. OFF: teleport back. No keybind - Travel tab toggle
-- "SafeZone" owns it (F5 freed). Death clears state silently. stop()
-- returns the character first - never strand them.

return function(deps)
	local util = deps.util

	local safezone = {}

	local Players = game:GetService("Players")
	local workspace = game:GetService("Workspace")

	local ALTITUDE = 2000 -- studs above the starting spot
	local PLATFORM_SIZE = Vector3.new(40, 2, 40)

	local listening = false
	local away = false
	local savedCFrame: CFrame? = nil
	local platform: BasePart? = nil
	local charConn: RBXScriptConnection? = nil
	-- Stable impl table handed to util.singleOwner: the first generation
	-- to start owns the live listener, later generations (after a reload)
	-- delegate start/stop/status to it, so the newest menu steers the one
	-- connection that actually exists.
	local IMPL: any = {}

	local function charParts()
		local char = Players.LocalPlayer.Character
		if not char then
			return nil, nil
		end
		return char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
	end

	-- One persistent platform, repositioned per use, visible/collidable
	-- only while somebody is parked on it (all client-side: the server
	-- and every other player never know it exists).
	local function getPlatform(): BasePart
		if platform and platform.Parent then
			return platform
		end
		local p = Instance.new("Part")
		p.Name = "ParalyzSafePlatform"
		p.Size = PLATFORM_SIZE
		p.Anchored = true
		p.CanCollide = false
		p.Transparency = 1
		p.Material = Enum.Material.SmoothPlastic
		p.Color = Color3.fromRGB(90, 140, 200)
		p.Parent = workspace
		platform = p
		return p
	end

	local function showPlatform(cf: CFrame, show: boolean)
		local p = getPlatform()
		pcall(function()
			if show then
				p.CFrame = cf
			end
			p.Transparency = show and 0 or 1
			p.CanCollide = show
		end)
	end

	local function moveTo(pos: CFrame): boolean
		local hrp, hum = charParts()
		if not (hrp and hum) then
			return false
		end
		if (hum :: Humanoid).SeatPart then
			return false
		end
		local ok = pcall(function()
			local root = hrp :: BasePart
			local humanoid = hum :: Humanoid
			root.CFrame = pos
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
		return ok
	end

	local function groundIsPlatform(): boolean
		local hrp, _ = charParts()
		local char = Players.LocalPlayer.Character
		if not (hrp and char) then
			return false
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local ok, result = pcall(function()
			return workspace:Raycast((hrp :: BasePart).Position, Vector3.new(0, -30, 0), params)
		end)
		return ok and result ~= nil and result.Instance == platform
	end

	local function toggle()
		if away then
			local saved = savedCFrame
			away = false
			savedCFrame = nil
			showPlatform(CFrame.new(), false)
			if saved then
				moveTo(saved)
			end
			if util and util.notify then
				util.notify("Safe zone", "OFF - back where you were")
			end
			return
		end
		local hrp, hum = charParts()
		if not (hrp and hum) or (hum :: Humanoid).Health <= 0 then
			if util and util.notify then
				util.notify("Safe zone", "no character right now")
			end
			return
		end
		if (hum :: Humanoid).SeatPart then
			if util and util.notify then
				util.notify("Safe zone", "unseat first")
			end
			return
		end
		savedCFrame = (hrp :: BasePart).CFrame
		local spot = (hrp :: BasePart).Position + Vector3.new(0, ALTITUDE, 0)
		local topY = spot.Y + PLATFORM_SIZE.Y / 2
		showPlatform(CFrame.new(spot), true)
		if not moveTo(CFrame.new(Vector3.new(spot.X, topY + 3, spot.Z))) then
			savedCFrame = nil
			showPlatform(CFrame.new(), false)
			return
		end
		task.wait(0.4)
		if not groundIsPlatform() then
			-- Platform failed us: restore and report, never strand mid-air.
			local saved = savedCFrame
			savedCFrame = nil
			away = false
			showPlatform(CFrame.new(), false)
			if saved then
				moveTo(saved)
			end
			if util and util.notify then
				util.notify("Safe zone", "platform failed - stayed put")
			end
			return
		end
		away = true
		if util and util.notify then
			util.notify("Safe zone", "ON - private platform, toggle off to return")
		end
	end

	function safezone.start()
		local ctl = util.singleOwner("conn_safezone", IMPL)
		if ctl ~= IMPL then
			ctl.start() -- an older generation owns the CharacterAdded handler
			return
		end
		if listening then
			return
		end
		listening = true
		-- No keybind (user order): the Travel tab toggle owns on/off.
		charConn = Players.LocalPlayer.CharacterAdded:Connect(function()
			if away then
				away = false
				savedCFrame = nil
			end
			showPlatform(CFrame.new(), false)
		end)
	end

	function safezone.stop()
		local ctl = util.stopOwner("conn_safezone", IMPL)
		if ctl == nil then
			return -- nobody is listening
		end
		if ctl ~= IMPL then
			ctl.stop()
			return
		end
		if away then
			local saved = savedCFrame
			away = false
			savedCFrame = nil
			if saved then
				moveTo(saved)
			end
		end
		showPlatform(CFrame.new(), false)
		listening = false
		if charConn then
			charConn:Disconnect()
			charConn = nil
		end
	end

	function safezone.toggle()
		-- The platform + away state belong to whichever generation is the
		-- owner, so a toggle from a reloaded menu must run THERE - otherwise
		-- isOn() would disagree with where the character actually is.
		local ctl = util.singleOwner("conn_safezone", IMPL)
		if ctl ~= IMPL then
			ctl.toggle()
			return
		end
		toggle()
	end

	function safezone.isRunning(): boolean
		local owner = util.ownerOf("conn_safezone")
		if owner ~= nil and owner ~= IMPL then
			return owner.isRunning()
		end
		return listening
	end

	function safezone.isOn(): boolean
		local owner = util.ownerOf("conn_safezone")
		if owner ~= nil and owner ~= IMPL then
			return owner.isOn()
		end
		return away
	end

	IMPL.start = safezone.start
	IMPL.stop = safezone.stop
	IMPL.toggle = safezone.toggle
	IMPL.isRunning = safezone.isRunning
	IMPL.isOn = safezone.isOn

	return safezone
end
