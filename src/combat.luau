--!strict
-- Paralyz / src/combat.luau
-- Auto-swing against nearby monsters, a keep-distance guard, and a
-- best-effort damage guard.
--
-- Honest scope: damage in this game appears to be applied server-side, so a
-- client cannot simply cancel it. What a client CAN do:
--   * kill things before they reach us (auto-swing)
--   * stay out of reach (avoid radius -> step back / fly up)
--   * hook TakeDamage if the game ever calls it from the client at all
--     (harmless when it does not - it just never fires)
-- The health watchdog tells us what actually happens when we take a hit, so
-- the guard can be tuned with facts instead of guesses.

return function(deps)
	local config = deps.config
	local state = deps.state
	local util = deps.util

	local combat = {}

	--------------------------------------------------------------- auto-swing
	local swingRunning = false
	local swingThread: thread? = nil

	local function bestSword(): Tool?
		-- Preference order, then anything that looks like a weapon.
		local preference = { "Omega", "Sword", "Blade", "Saber", "Rail", "Rocket" }
		for _, key in ipairs(preference) do
			local found = util.findTool(key)
			if found then
				return found
			end
		end
		return nil
	end

	local function swingLoop()
		while swingRunning do
			if not util.alive() then
				task.wait(1)
				continue
			end

			local root = util.root()
			local monster = root and util.nearestMonster(root.Position, config.combat.swingRange)
			if not monster then
				task.wait(0.25)
				continue
			end

			local sword = bestSword()
			if not sword then
				task.wait(1)
				continue
			end
			if not util.equip(sword) then
				task.wait(0.5)
				continue
			end

			-- Aim at the monster the same way mining aims at a rock - stand off
			-- from its edge, not its pivot - then swing.
			local pivot = monster:GetPivot().Position
			local size = monster:GetExtentsSize()
			util.aimAt(pivot, math.max(size.X, size.Y, size.Z) / 2 + 20)
			pcall(function()
				sword:Activate()
			end)
			task.wait(config.combat.swingDelay)
		end
		util.stopAim()
		swingRunning = false
	end

	function combat.startSwing()
		if swingRunning then
			return false
		end
		swingRunning = true
		swingThread = task.spawn(swingLoop)
		return true
	end

	function combat.stopSwing()
		swingRunning = false
		util.stopAim()
	end

	------------------------------------------------------------------- avoid
	local avoidConn: RBXScriptConnection? = nil

	local function setAvoid(on: boolean)
		if on then
			if avoidConn then
				return
			end
			avoidConn = util.RunService.Heartbeat:Connect(function()
				local root = util.root()
				if not root then
					return
				end
				local monster = util.nearestMonster(root.Position, config.combat.avoidRadius)
				if monster then
					-- Push away from the threat: fast, server-agnostic, works
					-- mid-air because the game lets you walk on moons anyway.
					local away = (root.Position - monster:GetPivot().Position)
					if away.Magnitude < 1 then
						away = Vector3.new(0, 1, 0)
					end
					root.CFrame = root.CFrame + away.Unit * 6
				end
			end)
		else
			if avoidConn then
				avoidConn:Disconnect()
				avoidConn = nil
			end
		end
	end

	----------------------------------------------------------- damage guard
	-- Best effort: intercept client-side TakeDamage on our own humanoid.
	-- If damage arrives from the server (most likely), this never fires and we
	-- say so in the log rather than pretending it works.
	local guardHooked = false
	local guardBlocked = 0

	function combat.enableGuard(): string
		if guardHooked then
			return "guard already active"
		end
		if not hookmetamethod or not getrawmetatable then
			return "no metatable hook available in this environment"
		end

		local ok, err = pcall(function()
			local mt = getrawmetatable(game)
			local oldNamecall = mt.__namecall
			setreadonly(mt, false)
			mt.__namecall = newcclosure(function(self, ...)
				local method = getnamecallmethod()
				if (method == "TakeDamage" or method == "ChangeHealth") and self == util.humanoid() then
					guardBlocked += 1
					return nil
				end
				return oldNamecall(self, ...)
			end)
			setreadonly(mt, true)
		end)

		if ok then
			guardHooked = true
			return "guard installed (blocks client TakeDamage)"
		end
		return "guard failed: " .. tostring(err)
	end

	----------------------------------------------------------- health watch
	local lastHealth = 100
	local watchConn: RBXScriptConnection? = nil

	function combat.startWatch()
		if watchConn then
			return
		end
		watchConn = util.RunService.Heartbeat:Connect(function()
			local hum = util.humanoid()
			if not hum then
				return
			end
			if hum.Health < lastHealth then
				local delta = lastHealth - hum.Health
				util.notify(
					"Damage taken",
					string.format("-%d hp (%d left), guard blocked %d", delta, math.floor(hum.Health), guardBlocked)
				)
			end
			lastHealth = hum.Health
		end)
	end

	function combat.stopWatch()
		if watchConn then
			watchConn:Disconnect()
			watchConn = nil
		end
	end

	function combat.sync()
		if state.enabled("AutoSwing") then
			combat.startSwing()
		else
			combat.stopSwing()
		end
		setAvoid(state.enabled("Avoid"))
		if state.enabled("GodMode") then
			local msg = combat.enableGuard()
			combat.startWatch()
			util.notify("Damage guard", msg)
		else
			combat.stopWatch()
		end
	end

	function combat.stop()
		combat.stopSwing()
		setAvoid(false)
		combat.stopWatch()
	end

	return combat
end
