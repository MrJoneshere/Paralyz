--!strict
-- Paralyz / src/minekey.luau
-- Keybind auto-mining (user request 2026-10-12): F7 toggles continuous
-- pickaxe swings while a pickaxe is equipped - "hold-to-mine without
-- holding", made for going AFK on top of a mining spot.
--
-- Click cadence = one click per COMPLETED swing (user report 2026-10-12:
-- "it happens if you click too much when mining... usually youd need to
-- click very little, if possible click after the mining is done, thats
-- why i requested you to make it 0 delay"): the previous build called
-- Activate() every frame (~60 clicks/s) - exactly the "clicking too
-- much" that glitches the character (only a very long wait or a rejoin
-- clears it). The pickaxe's swing is server-side, gated by a ~0.758s
-- animation (the Mining sound length), so the loop now clicks ONCE,
-- waits for the swing animation to end (fallback = that sound length),
-- waits out the server's Enabled lock, then clicks again immediately -
-- zero delay BETWEEN swings, which was the real request.
--
-- Stall watchdog + recovery (user: "mining stops for no reason... unequip
-- and re equip the pickaxe and move 5 studs... the character never gets
-- out of that 7.5 stud"):
--   * progress signal = util.juiceCount(); no change for STALL_SECS
--     while F7 is on = stall -> recovery.
--   * recovery = UnequipTools -> EquipTool(best pickaxe) -> walk up to
--     WALK studs in a random direction, hard-clamped inside RADIUS of the
--     anchor (0.3 margin), bounded by WALK_TIMEOUT.
--   * anchor = the position where the pickaxe is equipped when F7 goes
--     on (recaptures only on the next toggle-on, or on the first equip
--     after toggle-on). The character never leaves that circle: a
--     throttled boundary check walks it back if physics pushes it out.
--   * every loop step is pcall-guarded: a Lua error can no longer kill
--     the task silently (the likely original "stops for no reason").
--   * plain Humanoid:MoveTo walking only - no teleports, no camera
--     touches, nothing fired; any walk stops the moment F7 goes off.
--
-- Rules kept from holdmine:
--   * pickaxes only (name contains "pickaxe", same test as util.bestPickaxe).
--   * no pickaxe equipped = the loop idles (swings nothing).
--   * stop() on unload kills the loop for good.
--   * only a focused text box blocks the F7 toggle (GUIs claiming keys
--     must not eat it - see start()).
--
-- Hidden feature, no GUI entry (user's choice); a toast reports the state
-- on every toggle so it is never a mystery.

return function(deps)
	local util = deps.util

	local minekey = {}

	local KEY = Enum.KeyCode.F7
	local STALL_SECS = 12 -- no juice gain this long = stall -> recover
	local WALK = 5 -- recovery step length (studs)
	local RADIUS = 7.5 -- hard boundary around the anchor point
	local WALK_TIMEOUT = 4 -- seconds a recovery walk may take
	local BOUNDARY_EVERY = 0.5 -- boundary check throttle
	local WATCH_EVERY = 0.25 -- juice watchdog throttle
	local ERR_WARN_EVERY = 5 -- console warn throttle for loop errors

	local UIS = game:GetService("UserInputService")
	local Players = game:GetService("Players")

	local listening = false
	local swinging = false
	local recovering = false
	local runId = 0 -- bumped every toggle; stale loops see a mismatch
	local anchor: Vector3? = nil
	local conn: RBXScriptConnection? = nil
	-- Stable impl table handed to util.singleOwner: the first generation
	-- to start owns the live listener, later generations (after a reload)
	-- delegate start/stop/status to it, so the newest menu steers the one
	-- connection that actually exists.
	local IMPL: any = {}
	-- Cross-reload generation (see perf.luau): live-reload leaves old
	-- threads/listeners running. Claim a generation per loop-start; loops
	-- exit when superseded so swings never stack across reloads.
	local GEN_KEY = "ParalyzGen_minekey"
	local function claimGen(): number
		local env: any = getgenv()
		local g = (env[GEN_KEY] or 0) + 1
		env[GEN_KEY] = g
		return g
	end
	local function genAlive(g: number): boolean
		local env: any = getgenv()
		return env[GEN_KEY] == g
	end

	local function isPickaxe(tool: Tool): boolean
		return string.find(string.lower(tool.Name), "pickaxe", 1, true) ~= nil
	end

	-- One click per completed swing: length of a single swing. The swing
	-- itself is server-side; the Mining sound (0.758s on the Diamond
	-- Pickaxe) tracks the animation, + 0.1s margin for the server's
	-- Enabled-lock release. Fallback 0.85 if the tool has no such sound.
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

	-- Rock aim (root cause of "5-20s between mining acts", user report
	-- 2026-10-12): measured live, every activation gets an immediate
	-- server reply asking for Mouse.Target (ReplicatedStorage.Events.
	-- Pickaxe -> PickaxeController echoes it back), and the server only
	-- plays a swing / rolls the drop when that target is a rock within
	-- 30 studs. The old loop fired blind swings at whatever the view
	-- pointed at (measured: target=Planets.Planet6.Center, 298 studs at
	-- part center) - answered, then silently dropped - so acts only
	-- appeared when the view happened to line up with a rock. Two layers:
	--   gate: activate ONLY while the mouse target is a rock <= 30 studs.
	--   assist: when the aim is off but a rock is on screen, nudge the
	--     real cursor onto it (executor mousemoverel = native input, so it
	--     only moves the pointer while the Roblox window is focused -
	--     verified live). Up to 3 convergence passes absorb Windows DPI
	--     scaling; an ignored move (unfocused) backs the assist off for a
	--     few seconds instead of spamming. The cursor position saved at
	--     the first nudge is put back when F7 goes off.
	local function isRockPart(p: any): boolean
		if typeof(p) ~= "Instance" or not p:IsA("BasePart") then
			return false
		end
		local node: Instance? = p
		while node and node ~= workspace do
			local low = string.lower(node.Name)
			if node.Name == "Rocks" or string.find(low, "rock", 1, true) then
				return true
			end
			node = node.Parent
		end
		return false
	end

	local function aimValid(hrp: BasePart): boolean
		local t = (Players.LocalPlayer:GetMouse() :: any).Target
		return isRockPart(t) and ((t :: BasePart).Position - hrp.Position).Magnitude <= 30
	end

	-- Rock list for the assist (refreshed every 3s while swinging: rocks
	-- are destroyed on depletion and re-created on respawn).
	local rockCache: { BasePart } = {}
	local rockCacheAt = 0
	local cursorOrig: Vector2? = nil -- cursor position before our first nudge
	local assistRetryAt = 0 -- os.clock gate for assist attempts

	local function refreshRocks()
		rockCacheAt = os.clock()
		local out: { BasePart } = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and isRockPart(d) then
				table.insert(out, d)
			end
		end
		rockCache = out
	end

	-- One relative cursor move through the executor's native input.
	-- Returns false when the pointer did not move (window unfocused -
	-- native input is ignored then; verified live).
	local function rawMove(dx: number, dy: number): boolean
		local fn = (getgenv() :: any).mousemoverel
		if type(fn) ~= "function" then
			return false
		end
		local before = UIS:GetMouseLocation()
		local ok = pcall(fn, dx, dy)
		if not ok then
			return false
		end
		task.wait(0.03)
		local after = UIS:GetMouseLocation()
		return after.X ~= before.X or after.Y ~= before.Y
	end

	-- Steer the cursor onto the nearest on-screen rock. Returns true when
	-- the aim is valid afterwards. Re-measures after every move, so the	-- loop converges regardless of display scaling; never touches the
	-- cursor when the current aim is already good.
	local function assistAim(hrp: BasePart, now: number): boolean
		if now < assistRetryAt then
			return false
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return false
		end
		if os.clock() - rockCacheAt > 3 then
			refreshRocks()
		end
		local best, bestDist
		for _, r in ipairs(rockCache) do
			if r.Parent then
				local d = (r.Position - hrp.Position).Magnitude
				if d <= 30 then
					local vp, vis = cam:WorldToViewportPoint(r.Position)
					if vis and vp.Z > 0 and vp.X >= 0 and vp.X <= cam.ViewportSize.X
						and vp.Y >= 0 and vp.Y <= cam.ViewportSize.Y then
						if not bestDist or d < bestDist then
							best, bestDist = r, d
						end
					end
				end
			end
		end
		if not best then
			assistRetryAt = now + 1.0 -- nothing on screen: poll for respawn
			return false
		end
		if cursorOrig == nil then
			cursorOrig = UIS:GetMouseLocation()
		end
		for _ = 1, 3 do
			if aimValid(hrp) then
				return true
			end
			local cur = UIS:GetMouseLocation()
			local vp = cam:WorldToViewportPoint(best.Position)
			local dx, dy = vp.X - cur.X, vp.Y - cur.Y
			if math.abs(dx) <= 4 and math.abs(dy) <= 4 then
				break -- cursor is on the rock but the target is still not it
			end
			if not rawMove(dx, dy) then
				assistRetryAt = now + 3.0 -- input ignored (not focused)
				return false
			end
		end
		local valid = aimValid(hrp)
		if not valid then
			assistRetryAt = now + 1.5 -- aimed, still rejected: back off
		end
		return valid
	end

	-- Put the cursor back where it was before the assist nudged it.
	local function restoreCursor()
		local orig = cursorOrig
		cursorOrig = nil
		if not orig then
			return
		end
		for _ = 1, 2 do
			local cur = UIS:GetMouseLocation()
			local dx, dy = orig.X - cur.X, orig.Y - cur.Y
			if math.abs(dx) <= 1 and math.abs(dy) <= 1 then
				return
			end
			if not rawMove(dx, dy) then
				return -- window not focused: the nudge stays; next F7-off restores it
			end
		end
	end
	local function charParts()
		local char = Players.LocalPlayer.Character
		if not char then
			return nil, nil
		end
		return char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
	end

	local function stopWalk()
		local _, hum = charParts()
		if hum then
			pcall(function()
				hum:Move(Vector3.zero)
			end)
		end
	end

	-- Stall recovery (the user's fix): flick the tool off/on to reset the
	-- server's swing echo state, then step to a fresh spot so swings land
	-- on a new face of the rock - all inside the 7.5-stud circle.
	local function recover(cross: number?)
		if cross ~= nil and not genAlive(cross) then
			recovering = false
			return
		end
		if recovering or not swinging then
			return
		end
		recovering = true
		local hrp, hum = charParts()
		if not (hrp and hum) then
			recovering = false
			return
		end
		pcall(function()
			hum:UnequipTools()
		end)
		task.wait(0.25)
		if not swinging then
			recovering = false
			return
		end
		local pick = util.bestPickaxe()
		if pick then
			pcall(function()
				hum:EquipTool(pick)
			end)
		end
		task.wait(0.25)
		if not swinging then
			recovering = false
			return
		end
		local hrp2, hum2 = charParts()
		local a = anchor
		if hrp2 and hum2 and a then
			-- <= WALK studs in a random direction, clamped inside RADIUS
			local angle = math.random() * math.pi * 2
			local want = hrp2.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * WALK
			local off = want - a
			if off.Magnitude > RADIUS then
				want = a + off.Unit * (RADIUS - 0.3)
			end
			pcall(function()
				hum2:MoveTo(want)
			end)
			local t0 = os.clock()
			while swinging and os.clock() - t0 < WALK_TIMEOUT do
				if (hrp2.Position - want).Magnitude < 1 then
					break
				end
				task.wait(0.1)
			end
			pcall(function()
				hum2:Move(Vector3.zero)
			end)
		end
		recovering = false
	end

	local function swingLoop(myGen: number, cross: number)
		local lastJuice = nil
		local lastWatch = 0
		local lastBoundary = 0
		local lastProgress = os.clock()
		local lastErrAt = 0
		do
			local ok, j = pcall(util.juiceCount)
			if ok then
				lastJuice = j
			end
		end
		while swinging and runId == myGen and genAlive(cross) do
			local ok, err = pcall(function()
				local hrp, hum = charParts()
				local now = os.clock()

				-- F7 on without a pickaxe, equipped later: anchor there.
				local tool = util.equippedTool()
				local waitSecs = 0.1 -- no pickaxe: idle poll
				if tool and isPickaxe(tool) then
					if not anchor and hrp then
						anchor = hrp.Position
					end
					-- ONE click per completed swing (see header), and ONLY
					-- when the aim can land it: the server discards swings
					-- whose Mouse.Target is not a rock <= 30 studs (aim
					-- gate + cursor assist above). Blind clicks were the
					-- invisible "5-20s between acts".
					local swing = false
					if hrp then
						if aimValid(hrp) then
							swing = true
						else
							swing = assistAim(hrp, now)
						end
					end
					if swing then
						tool:Activate()
						waitSecs = swingSecs(tool)
					else
						-- no mineable rock under the aim (respawn, or the
						-- view needs turning): poll cheaply - the watchdog
						-- and boundary keep running through this state.
						waitSecs = 0.2
					end
				end

				-- Watchdog + boundary keep running WHILE the swing plays
				-- (sliced), so a stall is still caught on time.
				local t0 = os.clock()
				-- Tail spam (user request 2026-10-12: "spam 4 times per
				-- second 1 second before the mining finishes"): click every
				-- 0.25s across the last second of the swing - the whole
				-- swing when it is under 1s (diamond pickaxe = 0.76s) - so
				-- whichever click lands first after the server re-enables
				-- the tool starts the next swing with zero dead time.
				-- Mid-swing fires are measured-safe (server ignores them,
				-- no kick) and stay aim-gated like the starting click.
				local nextClick = math.max(0.25, waitSecs - 1.0)
				while swinging and runId == myGen and genAlive(cross) and os.clock() - t0 < waitSecs do
					local nowSlice = os.clock()

					-- Juice watchdog: no progress for STALL_SECS -> recover.
					if nowSlice - lastWatch >= WATCH_EVERY then
						lastWatch = nowSlice
						local okJ, j = pcall(util.juiceCount)
						if okJ and type(j) == "number" then
							if lastJuice == nil then
								lastJuice = j
							elseif j ~= lastJuice then
								lastJuice = j
								lastProgress = nowSlice
							end
							if nowSlice - lastProgress >= STALL_SECS then
								lastProgress = nowSlice -- one recovery per window
								task.spawn(function()
									recover(cross)
								end)
							end
						end
					end

					-- Boundary: never beyond RADIUS from the anchor.
					if hrp and hum and anchor and not recovering then
						if nowSlice - lastBoundary >= BOUNDARY_EVERY then
							lastBoundary = nowSlice
							local dir = hrp.Position - anchor
							if dir.Magnitude > RADIUS then
								pcall(function()
									hum:MoveTo(anchor + dir.Unit * (RADIUS - 0.3))
								end)
							end
						end
					end

					-- Tail clicks: 4/s across the last second of the
					-- swing; only while the aim is on a rock.
					if tool and hrp and tool.Parent == hrp.Parent
						and nowSlice - t0 >= nextClick
						and aimValid(hrp) then
						nextClick = nextClick + 0.25
						pcall(function()
							tool:Activate()
						end)
					end

					task.wait(0.05)
				end
			end)
			if not ok and os.clock() - lastErrAt >= ERR_WARN_EVERY then
				lastErrAt = os.clock()
				warn("[Paralyz] minekey loop error: " .. tostring(err))
			end
			task.wait()
		end
	end

	local function toggle()
		runId = runId + 1
		swinging = not swinging
		if swinging then
			-- Fresh circle per ON: the anchor is where the pickaxe is
			-- equipped when the user starts AFK-mining.
			anchor = nil
			assistRetryAt = 0
			rockCacheAt = 0 -- force a fresh rock list this session
			local tool = util.equippedTool()
			if tool and isPickaxe(tool) then
				local hrp = charParts()
				if hrp then
					anchor = hrp.Position
				end
			end
			local myGen = runId
			local cross = claimGen()
			task.spawn(function()
				swingLoop(myGen, cross)
			end)
		else
			anchor = nil
			claimGen() -- invalidate any stray loop from any generation
			stopWalk()
			pcall(restoreCursor) -- undo the aim assist's cursor nudge
		end
		if util and util.notify then
			util.notify("Auto-mine", swinging and "ON - one click per completed swing" or "OFF")
		end
	end

	function minekey.start()
		local ctl = util.singleOwner("key_minekey", IMPL)
		if ctl ~= IMPL then
			ctl.start() -- an older generation holds the live F7 listener
			return
		end
		if listening then
			return
		end
		listening = true
		-- Deliberately NOT gated on gameProcessed: GUIs and other hubs (IY)
		-- claim keys and Roblox flags those presses processed, which silently
		-- ate F7. Only a focused text box (typing) blocks the toggle now.
		conn = UIS.InputBegan:Connect(function(input)
			if input.KeyCode ~= KEY then
				return
			end
			if UIS:GetFocusedTextBox() then
				return
			end
			toggle()
		end)
	end

	function minekey.stop()
		local ctl = util.stopOwner("key_minekey", IMPL)
		if ctl == nil then
			return -- nobody is listening (loops of a dead owner are gone
			-- with their run, or were already invalidated by its own stop)
		end
		if ctl ~= IMPL then
			ctl.stop() -- the owner's claimGen() invalidates every loop
			return
		end
		runId = runId + 1
		claimGen() -- invalidate any loop, including older generations
		swinging = false
		recovering = false
		listening = false
		anchor = nil
		stopWalk()
		pcall(restoreCursor)
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	function minekey.isRunning(): boolean
		local owner = util.ownerOf("key_minekey")
		if owner ~= nil and owner ~= IMPL then
			return owner.isRunning()
		end
		return listening
	end

	function minekey.isSwinging(): boolean
		local owner = util.ownerOf("key_minekey")
		if owner ~= nil and owner ~= IMPL then
			return owner.isSwinging()
		end
		return swinging
	end

	function minekey.getAnchor()
		local owner = util.ownerOf("key_minekey")
		if owner ~= nil and owner ~= IMPL then
			return owner.getAnchor()
		end
		return anchor
	end

	IMPL.start = minekey.start
	IMPL.stop = minekey.stop
	IMPL.isRunning = minekey.isRunning
	IMPL.isSwinging = minekey.isSwinging
	IMPL.getAnchor = minekey.getAnchor

	return minekey
end
