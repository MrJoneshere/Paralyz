--!strict
-- Paralyz / src/safezone.luau
-- F5 safe zone (user request 2026-10-12): "make some sort of safe place
-- really far away from where player is so when im not focused i can turn
-- that module on while you work... you can actually tp to an existing
-- platform, test drop, then go back... make sure theres no npc or player
-- or anything around that".
--
-- Toggle ON: scan workspace for anchored BaseParts (>=6x6) whose center
-- is >=250 studs from every other player character and >=150 studs from
-- every loaded non-player humanoid; rank by that clearance; generate
-- part-LOCAL candidate points (top-center + top corners; planets are
-- rotated, world-axis offsets fall off them - first live test dropped
-- through and free-fell); teleport to the first candidate with VERIFIED
-- ground under it (raycast after landing, else try the next). Saved CFrame
-- restored on OFF. Death clears the saved spot silently. stop() returns
-- the character first - never strand them. SeatPart guard: never yank a
-- seated character out of a vehicle.
--
-- Why real geometry instead of a made-up platform: a dropped tool falls
-- by SERVER physics - a client-created part doesn't exist for the
-- server, so drops would fall through it forever. Real planet parts are
-- server-anchored, so tools actually land and can be picked up.

return function(deps)
	local util = deps.util

	local safezone = {}

	local KEY = Enum.KeyCode.F5
	local MIN_PLAYER_DIST = 250
	local MIN_NPC_DIST = 150
	local MIN_SIZE = 6
	local TOP_MARGIN = 3 -- studs above the part's top surface
	local EDGE_INSET = 10 -- keep corner points this far inside the edge
	local GROUND_CHECK = 30 -- raycast depth for ground verification
	local VERIFY_WAIT = 0.3 -- settle time before the ground raycast
	local MAX_CANDIDATES = 12 -- teleport attempts before giving up

	local UIS = game:GetService("UserInputService")
	local Players = game:GetService("Players")

	local listening = false
	local away = false
	local savedCFrame: CFrame? = nil
	local conn: RBXScriptConnection? = nil
	local charConn: RBXScriptConnection? = nil

	local function npcRoots(): { Vector3 }
		local roots: { Vector3 } = {}
		for _, m in ipairs(workspace:GetDescendants()) do
			if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") and Players:GetPlayerFromCharacter(m) == nil then
				local p = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildWhichIsA("BasePart", true)
				if p then
					table.insert(roots, (p :: BasePart).Position)
				end
			end
		end
		return roots
	end

	-- Distance from pos to the nearest entry (math.huge when list empty).
	local function clearance(pos: Vector3, list: { Vector3 }): number
		local min = math.huge
		for _, p in ipairs(list) do
			local d = (p - pos).Magnitude
			if d < min then
				min = d
			end
		end
		return min
	end

	-- Candidate landing CFrames: best-ranked parts, and on each part the
	-- top-surface point farthest from currently loaded NPCs. Part-local
	-- math (CFrame * offset) so rotated planets work.
	local function buildCandidates(): { CFrame }
		local me = Players.LocalPlayer
		local others: { Vector3 } = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= me then
				local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					table.insert(others, (hrp :: BasePart).Position)
				end
			end
		end
		local npcs = npcRoots()

		-- Score parts by player+NPC clearance; keep the best few.
		local scored: { { part: BasePart, score: number } } = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d.Anchored and d.Size.X >= MIN_SIZE and d.Size.Z >= MIN_SIZE then
				local center = d.Position
				local dp = clearance(center, others)
				local dn = clearance(center, npcs)
				if dp >= MIN_PLAYER_DIST and dn >= MIN_NPC_DIST then
					table.insert(scored, { part = d, score = dp + dn })
				end
			end
		end
		table.sort(scored, function(a, b)
			return a.score > b.score
		end)

		local candidates: { CFrame } = {}
		for i = 1, math.min(4, #scored) do
			local part = scored[i].part
			local topY = part.Size.Y / 2 + TOP_MARGIN
			local hx = math.max(part.Size.X / 2 - EDGE_INSET, 0)
			local hz = math.max(part.Size.Z / 2 - EDGE_INSET, 0)
			local offsets = { { 0, 0 }, { hx, hz }, { -hx, hz }, { hx, -hz }, { -hx, -hz }, { 0, hz }, { 0, -hz }, { hx, 0 }, { -hx, 0 } }
			-- Rank this part's points by NPC clearance (best first).
			local points: { { cf: CFrame, npcDist: number } } = {}
			for _, off in ipairs(offsets) do
				local cf = part.CFrame * CFrame.new(off[1], topY, off[2])
				table.insert(points, { cf = cf, npcDist = clearance(cf.Position, npcs) })
			end
			table.sort(points, function(a, b)
				return a.npcDist > b.npcDist
			end)
			for _, pt in ipairs(points) do
				table.insert(candidates, pt.cf)
				if #candidates >= MAX_CANDIDATES then
					return candidates
				end
			end
		end
		return candidates
	end

	local function charParts()
		local char = Players.LocalPlayer.Character
		if not char then
			return nil, nil
		end
		return char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
	end

	-- Ground verification: is there real collision right below us?
	local function groundBelow(): boolean
		local hrp = select(1, charParts())
		local char = Players.LocalPlayer.Character
		if not (hrp and char) then
			return false
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local ok, result = pcall(function()
			return workspace:Raycast((hrp :: BasePart).Position, Vector3.new(0, -GROUND_CHECK, 0), params)
		end)
		if ok then
			return result ~= nil
		end
		local hit = workspace:FindPartOnRayWithIgnoreList(Ray.new((hrp :: BasePart).Position, Vector3.new(0, -GROUND_CHECK, 0)), { char })
		return hit ~= nil
	end

	local function moveTo(pos: CFrame): boolean
		local hrp, hum = charParts()
		if not (hrp and hum) then
			return false
		end
		if hum.SeatPart then
			return false
		end
		pcall(function()
			local part = hrp :: BasePart
			part.CFrame = pos
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
		return true
	end

	-- Try candidates in order; only report success when ground is real.
	local function teleportVerified(): boolean
		for _, cf in ipairs(buildCandidates()) do
			if moveTo(cf) then
				task.wait(VERIFY_WAIT)
				if groundBelow() then
					return true
				end
			end
		end
		return false
	end

	local function toggle()
		if away then
			local saved = savedCFrame
			away = false
			savedCFrame = nil
			if saved then
				moveTo(saved)
			end
			if util and util.notify then
				util.notify("Safe zone", "OFF - back where you were")
			end
			return
		end
		local hrp, hum = charParts()
		if not (hrp and hum) or hum.Health <= 0 then
			if util and util.notify then
				util.notify("Safe zone", "no character right now")
			end
			return
		end
		if hum.SeatPart then
			if util and util.notify then
				util.notify("Safe zone", "unseat first")
			end
			return
		end
		savedCFrame = hrp.CFrame
		local ok = teleportVerified()
		if not ok then
			-- No candidate had ground: restore and say so.
			local saved = savedCFrame
			savedCFrame = nil
			if saved then
				moveTo(saved)
			end
			if util and util.notify then
				util.notify("Safe zone", "no verified far-away platform found")
			end
			return
		end
		away = true
		if util and util.notify then
			local pos = select(1, charParts())
			local nearest = math.huge
			if pos then
				for _, o in ipairs(Players:GetPlayers()) do
					if o ~= Players.LocalPlayer and o.Character then
						local oh = o.Character:FindFirstChild("HumanoidRootPart")
						if oh then
							local d = ((oh :: BasePart).Position - (pos :: BasePart).Position).Magnitude
							if d < nearest then
								nearest = d
							end
						end
					end
				end
			end
			local nearestNpc = clearance((pos :: BasePart).Position, npcRoots())
			util.notify(
				"Safe zone",
				string.format("ON - %d studs from players, %d from NPCs, F5 to return", nearest, nearestNpc)
			)
		end
	end

	function safezone.start()
		if listening then
			return
		end
		listening = true
		-- Same gate as F6/F7/F8: only a focused text box blocks the key.
		conn = UIS.InputBegan:Connect(function(input)
			if input.KeyCode ~= KEY then
				return
			end
			if UIS:GetFocusedTextBox() then
				return
			end
			toggle()
		end)
		charConn = Players.LocalPlayer.CharacterAdded:Connect(function()
			if away then
				away = false
				savedCFrame = nil
			end
		end)
	end

	function safezone.stop()
		-- Return the character before dying: never strand them far away.
		if away then
			local saved = savedCFrame
			away = false
			savedCFrame = nil
			if saved then
				moveTo(saved)
			end
		end
		listening = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if charConn then
			charConn:Disconnect()
			charConn = nil
		end
	end

	function safezone.isRunning(): boolean
		return listening
	end

	function safezone.isOn(): boolean
		return away
	end

	-- Programmatic toggle (used by the keybind AND remote testing).
	safezone.toggle = toggle

	return safezone
end
