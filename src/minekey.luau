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

	-- Root part + humanoid of the CURRENT character (nil-safe).
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
					-- ONE click per completed swing (see header): the
					-- server plays a ~0.76s swing and locks the tool;
					-- re-clicking mid-swing was the character glitch.
					tool:Activate()
					waitSecs = swingSecs(tool)
				end

				-- Watchdog + boundary keep running WHILE the swing plays
				-- (sliced), so a stall is still caught on time.
				local t0 = os.clock()
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
