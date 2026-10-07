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
--   HexSpitter      "Moon Gun" (Events.Buy, 10 juice). Its LocalScript owns
--                   a while-MouseDown fire loop whose upvalues are env
--                   globals (getsenv): StartFiring / StopFiring /
--                   MouseDown. The loop reads Configuration client-side
--                   (FireRate, Accuracy, Burst.Bullets, Damage), so pinning
--                   those and keeping the loop alive is a real mod.
--
-- Honest damage verdict (measured 2026-10-07, see NOTES.md): NO player
-- weapon awards damage on moon monsters for a normal account - rail all
-- variants, HexSpitter loop fire with verified on-target aim, sword at
-- contact range, synthetic RayHit payloads: all zero. These mods are
-- exactly what a client can own: rate, gates, pellets, volley spread.
-- Damage that lands is the server's call (ships/other content may honor
-- it; monsters so far do not).

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
	-- HexSpitter: GunRapid pins the values its own loop reads (FireRate,
	-- Accuracy, best-effort Damage) and keeps the while-MouseDown loop
	-- alive through getsenv; GunVolley raises Burst.Bullets for multi-
	-- pellet triggers. The loop is started/stopped only by us when we
	-- started it, so a manual hold is never released underneath the user.
	local modRunning = false
	local nextFire = 0
	local nextPin = 0
	local hexStartedEnv: { [string]: any }? = nil

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
		if string.find(low, "spitter", 1, true) or string.find(low, "hex", 1, true) then
			return "hex"
		end
		return nil
	end

	-- The HexSpitter LocalScript keeps its loop control as env globals
	-- (old-style script declarations): StartFiring, StopFiring, MouseDown,
	-- ToolEquipped, Reloading. getsenv reaches them; nothing here needs
	-- focus or any input synthesis (VIM input is flagged gameProcessed and
	-- the tool's handler skips it - measured).
	local function hexEnv(tool: Tool): { [string]: any }?
		local ls = (tool :: Tool):FindFirstChild("LocalScript")
		if not ls then
			return nil
		end
		local ok, env = pcall(getsenv, ls :: Instance)
		if ok and type(env) == "table" and type((env :: any).StartFiring) == "function" then
			return env :: any
		end
		return nil
	end

	local function hexPins(tool: Tool, rapid: boolean, volley: boolean)
		local cfg = (tool :: Tool):FindFirstChild("Configuration")
		if not cfg then
			return
		end
		pcall(function()
			local fr = cfg:FindFirstChild("FireRate")
			if fr and (fr :: any).Value > config.combat.hexFireRate then
				(fr :: any).Value = config.combat.hexFireRate
			end
			if rapid then
				local acc = cfg:FindFirstChild("Accuracy")
				if acc then
					(acc :: any).Value = Vector3.zero
				end
			end
			if volley then
				local burst = cfg:FindFirstChild("Burst")
				local bullets = burst and burst:FindFirstChild("Bullets")
				if bullets and (bullets :: any).MaxValue < config.combat.hexPellets then
					(bullets :: any).MaxValue = config.combat.hexPellets
				end
			end
			-- Best-effort: the value is a DoubleConstrainedValue (max 17).
			-- Server may re-replicate the stock 15 over it; harmless either way.
			local dmg = cfg:FindFirstChild("Damage")
			if dmg and (dmg :: any).Value < (dmg :: any).MaxValue then
				(dmg :: any).Value = (dmg :: any).MaxValue
			end
		end)
	end

	local function modLoop()
		while modRunning do
			local rapid = state.enabled("GunRapid")
			local volley = state.enabled("GunVolley")
			if not rapid and not volley then
				if hexStartedEnv then
					pcall(function()
						(hexStartedEnv :: any).MouseDown = false
					end)
					hexStartedEnv = nil
				end
				task.wait(0.25)
				continue
			end
			if not util.alive() then
				task.wait(0.5)
				continue
			end

			local tool = util.equippedTool()
			local kind = gunKind(tool)
			-- This game re-parents the pickaxe into the character alongside
			-- other tools, so "first tool child" misses the hex. The hex's
			-- own env flag (ToolEquipped, set by its Equipped/Unequipped
			-- handlers) is the ground truth for whether it is active - use
			-- it when the naive lookup does not find a gun.
			if not kind then
				local hexTool = util.character():FindFirstChild("HexSpitter")
				if hexTool then
					local env = hexEnv(hexTool :: Tool)
					if env and env.ToolEquipped == true then
						tool, kind = hexTool :: Tool, "hex"
					end
				end
			end
			if not kind or not tool then
				task.wait(0.3)
				continue
			end

			if kind == "hex" then
				-- Re-pin the values the fire loop reads about once a second
				-- (server replication can roll them back).
				if os.clock() >= nextPin then
					nextPin = os.clock() + 1
					hexPins(tool :: Tool, rapid, volley)
				end
				local env = hexEnv(tool :: Tool)
				if env then
					local active = env.MouseDown == true and (tool :: Tool).Enabled == false
					-- ToolEquipped is the fire loop's own gate: without it,
					-- spawning would churn (the loop would exit instantly).
					if rapid and not active and env.ToolEquipped == true then
						env.MouseDown = true
						task.spawn(env.StartFiring)
						hexStartedEnv = env
					elseif not rapid and hexStartedEnv == env and env.MouseDown then
						-- Only release the loop we started; a manual hold
						-- (input-driven MouseDown) is left alone.
						env.MouseDown = false
						hexStartedEnv = nil
					end
				end
				task.wait(0.2)
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
		if hexStartedEnv then
			pcall(function()
				(hexStartedEnv :: any).MouseDown = false
			end)
			hexStartedEnv = nil
		end
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
