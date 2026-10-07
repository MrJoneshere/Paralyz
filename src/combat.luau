--!strict
-- Paralyz / src/combat.luau
-- Keep-distance guard and gun MODS.
--
-- Scope decided with the user: no auto-swing / auto-shoot helpers (they
-- were weak and camera-locking) and no damage guard - damage in this game
-- is applied server-side, so a client cannot cancel it. What a client CAN
-- change is how its own guns are FIRED: rate, client gates, and how many
-- targets one trigger touches. That is what these mods do. The user aims;
-- the mods remove the limits.
--
-- What the guns actually are (read from the tools themselves):
--   Rail Gun        LocalScript fires tool.Click:FireServer(mouse.Hit.p) on
--                   Button1Down; the 5s wait in that script is only the
--                   cursor icon, and the remote takes an explicit position.
--   RocketLauncher  the client side is just MouseLoc.OnClientInvoke
--                   returning Mouse.Hit.p - the server pulls the aim when
--                   it fires - plus Tool.Enabled mirroring a server gate.

return function(deps)
	local config = deps.config
	local state = deps.state
	local util = deps.util

	local combat = {}

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

	---------------------------------------------------------------- gun mods
	-- GunRapid: refire the equipped gun every config.combat.gunDelay,
	-- clearing the rocket's client-side Enabled gate first. No camera
	-- movement anywhere - the mod fires where the user is already looking.
	-- GunVolley: every rail trigger additionally sends a shot at every
	-- monster in gunRange. Server damage math is not client-writable, so
	-- this is the honest "bigger hitbox": one trigger, the whole crowd.
	local modRunning = false
	local nextFire = 0

	local function gunKind(tool: Tool?): string?
		if not tool then
			return nil
		end
		local low = string.lower(tool.Name)
		if string.find(low, "rail", 1, true) then
			return "rail"
		end
		if string.find(low, "rocket", 1, true) then
			return "rocket"
		end
		return nil
	end

	local function modLoop()
		while modRunning do
			local rapid = state.enabled("GunRapid")
			local volley = state.enabled("GunVolley")
			if not rapid and not volley then
				task.wait(0.25)
				continue
			end
			if not util.alive() then
				task.wait(0.5)
				continue
			end

			local tool = util.equippedTool()
			local kind = gunKind(tool)
			if not kind or not tool then
				task.wait(0.3)
				continue
			end

			local now = os.clock()
			if now < nextFire then
				task.wait(0.05)
				continue
			end

			if kind == "rail" then
				local click = (tool :: Tool):FindFirstChild("Click")
				if click and click:IsA("RemoteEvent") then
					local mouse = game:GetService("Players").LocalPlayer:GetMouse()
					click:FireServer(mouse.Hit.Position)
					if volley then
						local root = util.root()
						if root then
							for _, monster in ipairs(util.aliveMonsters()) do
								local pivot = monster:GetPivot().Position
								if util.dist(root.Position, pivot) <= config.combat.gunRange then
									click:FireServer(pivot)
								end
							end
						end
					end
					nextFire = now + config.combat.gunDelay
				end
			else
				-- Client gate only; the server owns the real cooldown.
				(tool :: Tool).Enabled = true
				pcall(function()
					(tool :: Tool):Activate()
				end)
				nextFire = now + config.combat.gunDelay
			end
			task.wait(0.05)
		end
	end

	function combat.startGuns()
		if modRunning then
			return false
		end
		modRunning = true
		nextFire = 0
		task.spawn(modLoop)
		return true
	end

	function combat.stopGuns()
		modRunning = false
	end

	function combat.sync()
		setAvoid(state.enabled("Avoid"))
		if state.enabled("GunRapid") or state.enabled("GunVolley") then
			combat.startGuns()
		else
			combat.stopGuns()
		end
	end

	function combat.stop()
		combat.stopGuns()
		setAvoid(false)
	end

	return combat
end
