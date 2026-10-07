--!strict
-- Paralyz / loader.luau
-- Entry point. Tiny on purpose: it pulls Rayfield Gen2, fetches the modules
-- from this repo (or reads them from the bundle the build script produced),
-- builds the menu, and wires every element through src/state.luau.
--
-- Loadstring one-liner (once the repo is public):
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/MrJoneshere/Paralyz/main/loader.luau"))()

local VERSION = "0.2.0"
local BASE = "https://raw.githubusercontent.com/MrJoneshere/Paralyz/main/src/"

-- The bundler replaces this line with a literal table of module sources.
local PARALYZ_MODULES = {
	["combat"] = [==[
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
]==],
	["config"] = [==[
--!strict
-- Paralyz / src/config.luau
-- Every tunable in one place. Modules read it; nothing in here reads anything else.

return {
	-- Where the loader fetches module sources from when it is not running as a bundle.
	remoteBase = "https://raw.githubusercontent.com/MrJoneshere/Paralyz/main/src/",

	farm = {
		-- Seconds between mine swings. The server answers each swing, so this is also
		-- how fast a rock can actually be consumed.
		swingDelay = 0.35,
		-- Camera stand-off distance from the rock while aiming.
		aimDistance = 35,
		-- Sell once this many MoonJuice stacks are sitting in the Backpack.
		sellAt = 10,
		-- Rocks stream by proximity and in waves: when the folders are empty,
		-- wait this long and look again.
		noRockDelay = 4,
		-- Grace after equipping a tool before the first swing.
		equipDelay = 0.25,

		-- Stance geometry. Measured: the server drops a swing made from more
		-- than ~30 studs of the rock's centre (30 accepted, 37 rejected) and
		-- never rolls the character back, so every stance stays inside
		-- maxRange. The "Hide mining" menu toggle switches from standing on
		-- top of the rock to standing inside its mesh, invisible to others.
		maxRange = 26,
		hideOffset = 4,

		-- Auto-fix chain, in order, when swings go dead: 1) re-equip the
		-- pickaxe, 2) switch to another rock, 3) settle-wait. Any juice
		-- resets the chain. stallSwings is the floor: a run producing juice
		-- scales the threshold to 1.5x the observed swings-per-juice, so a
		-- healthy slow vein (ion on Venus, ~1 per 30 swings) does not read
		-- as a dead tool, while a run with no juice at all - the stuck
		-- pickaxe signature - still fixes at the flat floor.
		stallSwings = 10,
		rockSwitchDelay = 20,
		-- An outside move (event gathering players, cutscene, server warp)
		-- released the stance pin: pause this long before re-planning so
		-- the farm does not teleport out of a story event mid-flight.
		externalPause = 20,

		-- No rocks anywhere near the character: after this many empty waits
		-- the farm probes another planet.
		planetWaits = 3,
		-- Arriving somewhere: rocks stream in a few seconds after the
		-- character lands, so after a teleport the farm waits this long for
		-- the destination to load before deciding it is empty. Travel uses
		-- the same wait to confirm a load.
		loadWait = 15,
		-- How far from the character rocks still count as "here". Rocks from
		-- the previous planet linger while streaming out, and swinging at
		-- them is pointless anyway (the server range rule), so every
		-- proximity question filters by this.
		streamRadius = 2500,
		-- A planet that loaded empty goes on "not right now" for this long.
		-- Never forever: content appears later as phases advance.
		planetCooldown = 45,
		-- Rotation preference: Planet5 drops ion juice, worth ~2x plain
		-- Moon juice once converted (74 vs 15 per stack). rotatePlanet
		-- ranks preferred planets first within the same has-rocks tier,
		-- and probes them first when every planet looks empty. Data, not
		-- logic: add a name here to bias the farm toward it.
		preferPlanets = { Planet5 = true },
		-- Every planet in the world probed and found empty: pause this long
		-- before starting another sweep instead of bouncing map-edge to
		-- map-edge.
		emptyPause = 30,
	},

	esp = {
		players = true,
		monsters = true,
		juice = true,
		rocks = false,
		labels = true, -- the single nearest-target name label
		throughWalls = true, -- Highlight depth mode: AlwaysOnTop vs Occluded
		maxDistance = 3000,
		refresh = 0.25, -- seconds between scans; Highlights follow targets for free
		fill = 0.72, -- Highlight fill transparency (1 = invisible)
		outline = 0.0, -- Highlight outline transparency
		-- Per-layer caps: the pool can never grow past the sum of these.
		limits = { players = 16, monsters = 16, juice = 20, rocks = 30 },
		colors = {
			player = Color3.fromRGB(120, 170, 255),
			monster = Color3.fromRGB(255, 96, 96),
			juice = Color3.fromRGB(255, 214, 96),
			rock = Color3.fromRGB(210, 210, 210),
		},
	},

	combat = {
		-- Keep-distance when Avoid is on: monsters inside this radius trigger a step back.
		avoidRadius = 14,
		-- Gun mods: refire cadence while a mod is armed, and the range the
		-- volley sprays monsters at. Client-side only - server rate limits
		-- and damage math are not writable from here.
		gunDelay = 0.4,
		gunRange = 800,
		-- HexSpitter ("Moon Gun"): its LocalScript fire loop reads these
		-- Configuration values client-side, so pinning them has real effect.
		-- FireRate = seconds between bursts (stock 0.06); the loop is bound
		-- by remote round-trips anyway, so this is a feel knob, not a kick
		-- risk. hexPellets raises Burst.Bullets.MaxValue: more pellets per
		-- trigger at a slower cycle (true volley semantics).
		hexFireRate = 0.02,
		hexPellets = 8,
	},

	travel = {
		-- Fly speed, studs per second is this times 60: 8 -> ~480 studs/s,
		-- which crosses the 10k-stud gaps between planets in a usable time.
		flySpeed = 8,
		-- Hubs are folders of structures that stream with distance: from the
		-- far side of the world their resolve() is nil even though they
		-- exist (measured: Bunker folder present, zero BaseParts loaded at
		-- 11k studs). These are their measured spawn-area coordinates, used
		-- only as "go stand here until it loads" anchors - travel re-resolves
		-- and re-lands after the wait, so stale coords never become landings.
		hubFallbacks = {
			Bunker = Vector3.new(725, 3033, -1332),
			City = Vector3.new(654, 3063, -1230),
		},
	},

	rewards = {
		-- How often the daily/weekly quest list is polled for claims.
		-- Playtime chests are push (event listener), so this only covers
		-- quests -45s keeps Knit calls negligible.
		pollDelay = 45,
		-- A quest pass that takes longer than this is treated as a wedged
		-- RemoteFunction and abandoned (one zombie thread, never more).
		passTimeout = 15,
	},

	perf = {
		fps = 20, -- frame cap while no-render is on
		restoreFps = 0, -- 0 = Roblox default when no-render is off
	},
}
]==],
	["esp"] = [==[
--!strict
-- Paralyz / src/esp.luau
-- Highlight-based ESP with one optional label.
--
-- Kept deliberately boring so it cannot tank a weak GPU:
--   * A pool of Highlight instances capped per layer (config.esp.limits).
--     Highlights are assigned on a slow scan and then cost nothing per
--     frame - Roblox follows the adornee on its own, no redraw loop.
--   * One Drawing label, repositioned every frame to the nearest
--     on-screen target. That is the only per-frame work.
--   * Nothing survives: stop destroys the pool and the folder.

return function(deps)
	local config = deps.config
	local state = deps.state
	local util = deps.util

	local DrawingAny = (getgenv and getgenv().Drawing) or Drawing
	local Players = util.Players
	local RunService = util.RunService
	local esp = {}

	local enabled = false

	-- The single label: text object plus the entries it may pick from.
	local label = nil
	local labelTargets = {}

	------------------------------------------------------------- highlights
	local folder: Folder? = nil
	local pool: { Highlight } = {}

	local totalLimit = config.esp.limits.players
		+ config.esp.limits.monsters
		+ config.esp.limits.juice
		+ config.esp.limits.rocks

	local function ensureFolder(): Folder
		if folder and folder.Parent then
			return folder
		end
		local f = Instance.new("Folder")
		f.Name = "ParalyzESP"
		f.Parent = workspace
		folder = f
		return f
	end

	local function destroyPool()
		for _, hl in ipairs(pool) do
			pcall(function()
				hl:Destroy()
			end)
		end
		pool = {}
		if folder then
			pcall(function()
				folder:Destroy()
			end)
			folder = nil
		end
	end

	-- One pass: hand each live entry the next pooled Highlight, park the
	-- rest. Entries arrive nearest-first and already capped per layer, so
	-- the nearest targets always win a slot.
	local function applyScan(layers)
		local f = ensureFolder()
		local depth = if config.esp.throughWalls
			then Enum.HighlightDepthMode.AlwaysOnTop
			else Enum.HighlightDepthMode.Occluded
		local idx = 1
		for _, layer in ipairs(layers) do
			for _, e in ipairs(layer.entries) do
				if idx > totalLimit then
					break
				end
				if idx > #pool then
					local hl = Instance.new("Highlight")
					hl.Name = "ParalyzESP"
					hl.Parent = f
					table.insert(pool, hl)
				end
				local hl = pool[idx]
				hl.Adornee = e.inst
				hl.FillColor = e.color
				hl.OutlineColor = e.color
				hl.FillTransparency = config.esp.fill
				hl.OutlineTransparency = config.esp.outline
				hl.DepthMode = depth
				hl.Enabled = true
				idx += 1
			end
		end
		for i = idx, #pool do
			pool[i].Enabled = false
			pool[i].Adornee = nil
		end
	end

	--------------------------------------------------------------- scanning
	-- Entries: { inst, pos, text, color, d } nearest-first, capped.

	local function origin(): Vector3
		local root = util.root()
		return root and root.Position or Vector3.zero
	end

	local function slice(list, cap)
		for i = #list, cap + 1, -1 do
			table.remove(list, i)
		end
		return list
	end

	local function scanPlayers()
		local out = {}
		local o = origin()
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= Players.LocalPlayer then
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if char and root and hum and (hum :: Humanoid).Health > 0 then
					local d = util.dist(o, (root :: BasePart).Position)
					if d <= config.esp.maxDistance then
						table.insert(out, {
							inst = char,
							pos = (root :: BasePart).Position,
							text = string.format(
								"%s  %d/%d  [%dm]",
								player.DisplayName,
								math.floor((hum :: Humanoid).Health),
								math.floor((hum :: Humanoid).MaxHealth),
								math.floor(d)
							),
							color = config.esp.colors.player,
							d = d,
						})
					end
				end
			end
		end
		table.sort(out, function(a, b)
			return a.d < b.d
		end)
		return slice(out, config.esp.limits.players)
	end

	local function scanMonsters()
		local out = {}
		local o = origin()
		for _, model in ipairs(util.aliveMonsters()) do
			local pivot = model:GetPivot().Position
			local d = util.dist(o, pivot)
			if d <= config.esp.maxDistance then
				local hum = model:FindFirstChildOfClass("Humanoid")
				table.insert(out, {
					inst = model,
					pos = pivot,
					text = string.format(
						"%s  %d  [%dm]",
						model.Name,
						math.floor(hum and hum.Health or 0),
						math.floor(d)
					),
					color = config.esp.colors.monster,
					d = d,
				})
			end
		end
		table.sort(out, function(a, b)
			return a.d < b.d
		end)
		return slice(out, config.esp.limits.monsters)
	end

	-- MoonJuice tanks lying around the world (tools under Workspace.Unanchored).
	local function scanJuice()
		local out = {}
		local o = origin()
		local unanchored = workspace:FindFirstChild("Unanchored")
		if not unanchored then
			return out
		end
		for _, inst in ipairs(unanchored:GetChildren()) do
			if inst:IsA("Tool") and inst:FindFirstChild("Credits") then
				local part = inst:FindFirstChildWhichIsA("BasePart", true)
				if part then
					local d = util.dist(o, (part :: BasePart).Position)
					if d <= config.esp.maxDistance then
						local credits = inst:FindFirstChild("Credits")
						table.insert(out, {
							inst = part :: BasePart,
							pos = (part :: BasePart).Position,
							text = string.format(
								"Juice %d [%dm]",
								math.floor(credits and (credits :: NumberValue).Value or 0),
								math.floor(d)
							),
							color = config.esp.colors.juice,
							d = d,
						})
					end
				end
			end
		end
		table.sort(out, function(a, b)
			return a.d < b.d
		end)
		return slice(out, config.esp.limits.juice)
	end

	local function scanRocks()
		local out = {}
		local o = origin()
		for _, rock in ipairs(util.minableRocks()) do
			local d = util.dist(o, rock.Position)
			if d <= config.esp.maxDistance then
				table.insert(out, {
					inst = rock,
					pos = rock.Position,
					text = string.format("Rock [%dm]", math.floor(d)),
					color = config.esp.colors.rock,
					d = d,
				})
			end
		end
		table.sort(out, function(a, b)
			return a.d < b.d
		end)
		return slice(out, config.esp.limits.rocks)
	end

	local function scan()
		local layers = {}
		local merged = {}
		if state.enabled("ESPPlayers") then
			local entries = scanPlayers()
			table.insert(layers, { entries = entries })
			for _, e in ipairs(entries) do
				table.insert(merged, e)
			end
		end
		if state.enabled("ESPMonsters") then
			local entries = scanMonsters()
			table.insert(layers, { entries = entries })
			for _, e in ipairs(entries) do
				table.insert(merged, e)
			end
		end
		if state.enabled("ESPJuice") then
			local entries = scanJuice()
			table.insert(layers, { entries = entries })
			for _, e in ipairs(entries) do
				table.insert(merged, e)
			end
		end
		if state.enabled("ESPRocks") then
			local entries = scanRocks()
			table.insert(layers, { entries = entries })
			for _, e in ipairs(entries) do
				table.insert(merged, e)
			end
		end
		applyScan(layers)
		labelTargets = merged
	end

	------------------------------------------------------------------ label
	local function ensureLabel()
		if label or not DrawingAny then
			return label
		end
		local ok, made = pcall(function()
			return DrawingAny.new("Text")
		end)
		if not ok then
			return nil
		end
		made.Size = 14
		made.Center = true
		made.Outline = true
		made.Font = 2 -- Roboto Mono
		made.Visible = false
		label = made
		return label
	end

	--------------------------------------------------------------- run loop
	local scanConn: thread? = nil
	local drawConn: RBXScriptConnection? = nil

	local function start()
		if drawConn then
			return
		end
		ensureLabel()

		drawConn = RunService.RenderStepped:Connect(function()
			local text = label
			if not text then
				return
			end
			if not state.enabled("ESPLabels") then
				text.Visible = false
				return
			end
			local cam = workspace.CurrentCamera
			if not cam then
				text.Visible = false
				return
			end

			-- Nearest on-screen target wins the single label.
			local best, bestScreen
			for _, t in ipairs(labelTargets) do
				local screen, onScreen = cam:WorldToViewportPoint(t.pos)
				if onScreen and screen.Z > 0 then
					if not bestScreen or screen.Z < bestScreen.Z then
						best, bestScreen = t, screen
					end
				end
			end

			if best and bestScreen then
				text.Position = Vector2.new(bestScreen.X, bestScreen.Y)
				text.Text = best.text
				text.Color = best.color
				text.Visible = true
			else
				text.Visible = false
			end
		end)

		scanConn = task.spawn(function()
			while enabled do
				pcall(scan)
				task.wait(config.esp.refresh)
			end
		end)
	end

	local function stop()
		if drawConn then
			drawConn:Disconnect()
			drawConn = nil
		end
		if scanConn then
			pcall(task.cancel, scanConn)
			scanConn = nil
		end
		if label then
			label.Visible = false
		end
		labelTargets = {}
		destroyPool()
	end

	-- Single switch the menu drives.
	function esp.sync()
		local anyOn = state.enabled("ESPPlayers")
			or state.enabled("ESPMonsters")
			or state.enabled("ESPJuice")
			or state.enabled("ESPRocks")

		if anyOn and not enabled then
			enabled = true
			start()
		elseif not anyOn and enabled then
			enabled = false
			stop()
		end
	end

	function esp.stop()
		enabled = false
		stop()
	end

	return esp
end
]==],
	["farm"] = [==[
--!strict
-- Paralyz / src/farm.luau
-- Auto-farm: hold a stance inside the rock's mining range, swing, collect
-- MoonJuice, sell.
--
-- What the server enforces (measured 2026-10-07 with a binary search):
--   * A swing only pays out while the character is within ~30 studs of the
--     targeted rock's centre: 30 accepted, 37 rejected. Farther out the
--     swing is silently dropped - aim, Tool.Activated and the server's own
--     Pickaxe ask all fire, but no juice ever appears.
--   * The character's POSITION is never rolled back, only the swing is
--     dropped, so a per-frame CFrame hold keeps any stance stable.
--   * Rocks stream by proximity: folders fill a few seconds after a player
--     arrives at a planet and empty when nobody is near.
--   * A pickaxe only swings when it was equipped through
--     Humanoid:EquipTool. When swings die, unequip -> wait -> EquipTool
--     revives it (util.reequip); if that fails, switch the rock.
--
-- Stances (config + the "Hide mining" menu toggle):
--   * "top"  - root on the rock's upper surface, visible but in range.
--   * "hide" - root inside the rock mesh: nobody can see the character,
--              same server range, collision managed here while running.
--
-- Testing rule: tests call farm.start({ maxJuice = 5 }) - the run stops once
-- 5 stacks were COLLECTED. The GUI never passes these, shipped runs are
-- unlimited.

return function(deps)
	local config = deps.config
	local state = deps.state
	local util = deps.util

	local farm = {}

	local running = false
	local thread: thread? = nil

	-- Per-frame stance hold: gravity and depenetration beat a single CFrame
	-- write, re-applying every RenderStepped frame is what was proven to hold.
	local holdCF: CFrame? = nil
	local holdConn: RBXScriptConnection? = nil
	-- The stance pin writes root.CFrame every frame, so a large gap between
	-- the pin target and the real position means somebody else moved us:
	-- an event gathering players, a cutscene, a server warp (observed live:
	-- the Io arrival carried the character 16k studs mid-idle). Fighting
	-- those frame by frame breaks the event, so the farm releases the pin
	-- and the aim, pauses, and re-plans from wherever it ended up. The
	-- flag marks the one legitimate large one-frame gap: switching stance
	-- to a far rock (root still stands at the old one until the pin runs).
	local stanceJustSet = false
	local externalUntil = 0

	-- metrics (the menu shows these through farm.stats())
	local cycles = 0 -- swings sent
	local gained = 0 -- juice stacks collected (counted when they land)
	local sold = 0
	local fixes = 0
	local switches = 0
	local lastReport = 0

	-- rocks on cooldown after a stall (rock -> release time)
	local avoided: { [BasePart]: number } = {}
	-- planets loaded but empty right now (name -> release time), and a pause
	-- between full sweeps of the world (see rotatePlanet)
	local planetCool: { [string]: number } = {}
	local rotatePause = 0

	local function report(msg: string, force: boolean?)
		-- Rotation lifecycle messages force their way through: hiding
		-- "moving to X" behind the throttle made every run look like it
		-- declared planets empty without ever going there.
		if force or os.clock() - lastReport > 2 then
			lastReport = os.clock()
			util.notify("Auto-Farm", msg)
		end
	end

	-- Live phase for the menu's stat line, so what the farm is doing is
	-- visible continuously instead of only as fading toasts.
	local phase = "idle"
	local function setPhase(p: string)
		phase = p
	end

	-- Travel teleports must move the hold with them: without this the
	-- per-frame stance pin overwrites the teleport on the next frame, which
	-- is why a manual teleport during a farm run appeared to do nothing
	-- until it was spammed (it only landed when the rotation happened to
	-- rewrite the hold).
	util.onTeleport(function(cf)
		if running then
			holdCF = cf
		end
	end)

	------------------------------------------------------------------ stance
	local function hidden(): boolean
		return state.enabled("HideMining")
	end

	-- Conversion pays for ion (2.5 credits/swing vs the Moon's 1.25); raw
	-- ion sells at 20/stack = 0.67/swing, BELOW the Moon, so the ion
	-- preference (planet ranking + the start-of-run probe) only applies
	-- when the converter will actually run.
	local function preferActive(): boolean
		local prefer = config.farm.preferPlanets
		return prefer ~= nil and next(prefer) ~= nil and state.enabled("AutoConvert")
	end

	-- CFrame to hold while swinging this rock, never farther from the centre
	-- than config.farm.maxRange (the server drops swings past that).
	local function stanceCFrame(rock: BasePart, fromPos: Vector3): CFrame
		if hidden() then
			local dir = fromPos - rock.Position
			dir = if dir.Magnitude > 1 then dir.Unit else Vector3.new(0, 0, 1)
			local off = math.min(config.farm.hideOffset, config.farm.maxRange - 4)
			local pos = rock.Position + dir * off
			return CFrame.lookAt(pos, Vector3.new(rock.Position.X, pos.Y, rock.Position.Z))
		end
		-- Top stance: root on the upper surface (feet at the rock's top).
		-- Rocks taller than the server range sit just under the top instead -
		-- still inside the mesh, still mineable.
		local topY = rock.Size.Y / 2 + 3
		if topY > config.farm.maxRange then
			topY = config.farm.maxRange
		end
		local pos = rock.Position + Vector3.new(0, topY, 0)
		return CFrame.lookAt(pos, Vector3.new(rock.Position.X, pos.Y, rock.Position.Z))
	end

	local function startHold()
		if holdConn then
			return
		end
		holdConn = util.RunService.RenderStepped:Connect(function()
			local cf = holdCF
			if not cf then
				return
			end
			local root = util.root()
			if not root then
				return
			end
			local expectStance = stanceJustSet
			stanceJustSet = false
			if not expectStance and (root.CFrame.Position - cf.Position).Magnitude > 500 then
				-- Somebody else moved us while we were pinning. Adopt the
				-- new position instead of snapping back: release stance and
				-- aim, pause the loop, and re-plan from here afterwards.
				holdCF = nil
				util.stopAim()
				externalUntil = os.clock() + config.farm.externalPause
				if running then
					report("the game moved us - pausing the farm", true)
				end
				return
			end
			root.CFrame = cf
		end)
	end

	local function stopHold()
		holdCF = nil
		if holdConn then
			holdConn:Disconnect()
			holdConn = nil
		end
	end

	-- Hide mode parks the character inside solid rock; without this the
	-- solver ejects it every frame. Only touches collision when the stance
	-- needs it, and always restores the body it changed.
	local collChar: Model? = nil
	local collOff = false

	local function restoreCollision()
		if collChar and collOff and collChar.Parent then
			for _, part in ipairs(collChar:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = true
				end
			end
		end
		collChar = nil
		collOff = false
	end

	local function syncCollision()
		local char = util.character()
		local wantOff = running and hidden()
		if char == collChar and wantOff == collOff then
			return
		end
		restoreCollision()
		if wantOff and char then
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
				end
			end
			collChar = char
			collOff = true
		end
	end

	------------------------------------------------------------------- rocks
	local function pickRock(fromPos: Vector3): BasePart?
		local now = os.clock()
		for rock, untilT in pairs(avoided) do
			if untilT <= now or not rock.Parent then
				avoided[rock] = nil
			end
		end
		local best, bestD
		-- Only rocks that are actually streamed in around the character: the
		-- previous planet's rocks linger in memory while they stream out, and
		-- a stance at one of those would teleport the farm straight back.
		for _, rock in ipairs(util.rocksNear(fromPos, config.farm.streamRadius)) do
			if not avoided[rock] then
				local d = util.dist(fromPos, rock.Position)
				if not bestD or d < bestD then
					best, bestD = rock, d
				end
			end
		end
		return best
	end

	-- Every rock is on cooldown: release the oldest instead of stalling.
	local function releaseOldestAvoided(): boolean
		local oldest, oldestT
		for rock, untilT in pairs(avoided) do
			if not oldestT or untilT < oldestT then
				oldest, oldestT = rock, untilT
			end
		end
		if oldest then
			avoided[oldest] = nil
			return true
		end
		return false
	end

	-- Probe planets one at a time, the way the map actually works: teleport,
	-- WAIT for the destination to load (rocks spawn seconds after you arrive;
	-- judging emptiness from far away - the old behaviour - just bounced the
	-- farm across unloaded space until nothing was loaded anywhere), and only
	-- then decide. Candidates are tried nearest-first, an empty planet cools
	-- down instead of being re-probed forever, and cooled planets come back
	-- later because content appears as phases advance. Returns true when the
	-- character ended up somewhere with rocks.
	-- Rotate with the hold: the per-frame stance hold would otherwise snap
	-- the character straight back to the rock we just left, which made every
	-- planet probe judge emptiness from the OLD position (and read to the
	-- user as "it teleported me somewhere random"). The aim unbinds here
	-- too - not a restore, just a free camera while travelling - and the
	-- next rock re-aims on its own.
	local function rotateTeleport(cf: CFrame)
		util.stopAim()
		holdCF = cf
		local root = util.root()
		if root then
			root.CFrame = cf
		end
		util.teleported(cf)
	end

	local function rotatePlanet(): boolean
		local root = util.root()
		if not root then
			return false
		end
		local now = os.clock()
		for name, untilT in pairs(planetCool) do
			if untilT <= now then
				planetCool[name] = nil
			end
		end
		local scan = util.planetScan()
		if #scan == 0 then
			setPhase("no planets visible - waiting")
			report("no planets are loaded right now - waiting", true)
			return false
		end
		-- Planets we are already standing among: the emptiness is proven by
		-- presence (the farm only rotates when nothing is loaded within
		-- streamRadius), so cool them instead of probing ourselves again.
		for _, p in ipairs(scan) do
			if util.dist(p.centre, root.Position) <= config.farm.streamRadius then
				planetCool[p.name] = now + config.farm.planetCooldown
			end
		end
		local prefer = if preferActive() then config.farm.preferPlanets else nil
		table.sort(scan, function(a, b)
			-- Live rock counts first (meaningful only for planets already
			-- streamed in), then nearest: probing the closest unknown planet
			-- beats hopping to the far edge of the map. Within the same
			-- rocks-tier, preferred planets (config.farm.preferPlanets -
			-- the ion field) win, and when every planet reads empty the
			-- first probe goes there, because that is where the best
			-- income is once content appears.
			if (a.rocks > 0) ~= (b.rocks > 0) then
				return a.rocks > 0
			end
			if prefer then
				local pa = prefer[a.name] == true
				local pb = prefer[b.name] == true
				if pa ~= pb then
					return pa
				end
			end
			return util.dist(a.centre, root.Position) < util.dist(b.centre, root.Position)
		end)

		local tried = 0
		local swept = false -- one full retry pass after clearing cooldowns
		while running and tried < #scan do
			local target = nil
			for _, p in ipairs(scan) do
				if not planetCool[p.name] then
					target = p
					break
				end
			end
			if not target then
				if swept then
					break
				end
				planetCool = {}
				swept = true
				continue
			end
			tried += 1
			rotateTeleport(CFrame.new(util.dropToSurface(target.centre)))
			setPhase("loading " .. target.name)
			report("moving to " .. target.name .. " - going there to load it", true)
			task.wait(1)
			local n = util.settleRocks(target.centre, config.farm.loadWait, config.farm.streamRadius)
			root = util.root()
			if not root then
				return false
			end
			if n > 0 then
				-- Land precisely on the surface now that the load confirmed
				-- rocks here, and pin the hold to the landing spot.
				rotateTeleport(CFrame.new(util.dropToSurface(target.centre)))
				setPhase("loaded " .. target.name)
				report(target.name .. " loaded in person: " .. n .. " rocks", true)
				return true
			end
			planetCool[target.name] = os.clock() + config.farm.planetCooldown
			report(target.name .. ": went there, waited, empty for now - trying another planet", true)
		end
		return false
	end

	-- The auto-fix chain: swings go dead for no visible reason -> heal the
	-- pickaxe, then switch rocks, then settle-wait. Any juice resets it.
	local function autoFix(stage: number, pickaxe: Tool?, rock: BasePart?)
		if stage == 1 and pickaxe then
			if util.reequip(pickaxe) then
				fixes += 1
				report("pickaxe went dead - re-equipped")
				return true
			end
			return false
		end
		if stage == 2 and rock then
			avoided[rock] = os.clock() + config.farm.rockSwitchDelay
			switches += 1
			report("rock stalled - switching")
			return true
		end
		if stage == 3 then
			-- Server-side wedge or a wave transition: give it a few seconds.
			report("swings still dead - settling")
			task.wait(3)
			return true
		end
		return false
	end

	-- Ion juice is worth more as anti matter: walk the stack through the
	-- SpaceStation converter before the sell. Measured: InputHoldBegin/End
	-- DOES trigger the machine (prompt.Triggered fires after the2s hold)
	-- and the machine takes ion only - one hold per stack, each verified
	-- by the ion count dropping; a hold that consumes nothing aborts
	-- instead of looping. Anti matter stacks carry Credits, so the normal
	-- sellAll that follows picks them up.
	local function convertIon(): number
		local prompt = util.converterPrompt()
		if not prompt then
			report("ion juice aboard but no converter machine exists in this world", true)
			return 0
		end
		local holder = prompt.Parent
		local well = if holder and (holder :: Instance):IsA("BasePart")
			then (holder :: BasePart)
			else if holder then (holder :: any):FindFirstChildWhichIsA("BasePart", true) else nil
		if not well then
			return 0
		end
		setPhase("converting ion juice")
		-- Hold-aware teleport: the stance pin would otherwise snap the
		-- character straight back to the rock we left.
		rotateTeleport(CFrame.new(well.Position + Vector3.new(0, 3, 0)))
		task.wait(0.6)
		local converted = 0
		for _ = 1, math.min(util.ionJuiceCount(), 20) do
			local before = util.ionJuiceCount()
			if before <= 0 then
				break
			end
			pcall(function()
				prompt:InputHoldBegin()
				task.wait((prompt :: ProximityPrompt).HoldDuration + 0.6)
				prompt:InputHoldEnd()
			end)
			task.wait(0.8)
			local after = util.ionJuiceCount()
			if after < before then
				converted += before - after
			else
				report("converter rejected the hold - moving on", true)
				break
			end
		end
		if converted > 0 then
			report(string.format("converted %d ion -> anti matter", converted), true)
		end
		return converted
	end

	------------------------------------------------------------------- loop
	local function runLoop(opts)
		local maxCycles = opts and opts.maxCycles
		local maxJuice = opts and opts.maxJuice

		cycles, gained, sold, fixes, switches = 0, 0, 0, 0, 0
		avoided = {}
		planetCool = {}
		rotatePause = 0
		externalUntil = 0
		local stall = 0 -- swings since the last juice
		local fixStage = 0
		local probedPreferred = false -- one best-income probe per run
		local emptyWaits = 0
		local aimFails = 0
		local lastJuice = util.juiceCount()

		local function noteJuice()
			local now = util.juiceCount()
			if now > lastJuice then
				gained += now - lastJuice
				stall = 0
				fixStage = 0
			end
			lastJuice = now
		end

		startHold()

		while running do
			syncCollision()

			if maxJuice and gained >= maxJuice then
				util.notify("Auto-Farm", "test cap reached (" .. gained .. " juice)")
				break
			end
			if maxCycles and cycles >= maxCycles then
				util.notify("Auto-Farm", "test cap reached (" .. cycles .. " swings)")
				break
			end
			if not util.alive() then
				setPhase("waiting to respawn")
				task.wait(1)
				continue
			end
			if os.clock() < externalUntil then
				setPhase("paused - the game moved us")
				task.wait(1)
				continue
			end

			noteJuice()

			-- Sell before the stack fills so the backpack never clogs.
			if util.juiceCount() >= config.farm.sellAt then
				-- Convert first when ion stacks are aboard: the machine
				-- pays more than selling the ion straight.
				if state.enabled("AutoConvert") and util.ionJuiceCount() > 0 then
					convertIon()
				end
				local count = util.sellAll()
				if count > 0 then
					sold += count
					report(string.format("sold %d stacks (total %d)", count, sold))
				end
				lastJuice = util.juiceCount()
				task.wait(0.4)
				continue
			end

			local root = util.root()
			if not root then
				task.wait(0.5)
				continue
			end

			-- One-shot at run start: leave a local vein that pays worse to
			-- verify the ion field. Local rocks only prove THIS planet has
			-- work; they say nothing about the best planet, and a run
			-- started from a stranded position (Mars 0.88/swing, Moon 1.25,
			-- ion 2.5) would otherwise mine the worst planet forever,
			-- because local rocks never trigger rotation. Probes only when
			-- there is local work to leave - a run starting with nothing
			-- loaded reaches the same probe through the normal rotation.
			if not probedPreferred and preferActive() then
				probedPreferred = true
				local prefer = config.farm.preferPlanets
				local preferred
				for _, p in ipairs(util.planetScan()) do
					if prefer[p.name] then
						preferred = p
						break
					end
				end
				if preferred
					and util.dist(preferred.centre, root.Position) > config.farm.streamRadius
					and #util.rocksNear(root.Position, config.farm.streamRadius) > 0
				then
					report(
						"checking " .. preferred.name .. " (best income) before settling here",
						true
					)
					rotateTeleport(CFrame.new(util.dropToSurface(preferred.centre)))
					setPhase("loading " .. preferred.name)
					task.wait(1)
					local n = util.settleRocks(
						preferred.centre,
						config.farm.loadWait,
						config.farm.streamRadius
					)
					if n > 0 then
						rotateTeleport(CFrame.new(util.dropToSurface(preferred.centre)))
						setPhase("loaded " .. preferred.name)
						report(preferred.name .. " has " .. n .. " rocks - mining the ion field", true)
					else
						planetCool[preferred.name] = os.clock() + config.farm.planetCooldown
						report(preferred.name .. " is empty right now - staying local", true)
					end
					continue
				end
			end

			local rock = pickRock(root.Position)
			if not rock then
				local near = #util.rocksNear(root.Position, config.farm.streamRadius)
				if near > 0 and releaseOldestAvoided() then
					setPhase("freeing a stalled rock")
					task.wait(1)
					continue
				end
				emptyWaits += 1
				setPhase("no rocks loaded here (" .. emptyWaits .. "/" .. config.farm.planetWaits .. ")")
				if emptyWaits >= config.farm.planetWaits then
					emptyWaits = 0
					if os.clock() >= rotatePause then
						if rotatePlanet() then
							rotatePause = 0
						else
							rotatePause = os.clock() + config.farm.emptyPause
							report(
								"probed every planet in person and all are empty - resting "
									.. config.farm.emptyPause .. "s",
								true
							)
							setPhase("resting - no planet has rocks")
						end
					else
						setPhase("resting - no planet has rocks")
					end
				end
				task.wait(config.farm.noRockDelay)
				continue
			end
			emptyWaits = 0

			-- Stance: hold it from here on; recomputed whenever we re-enter.
			holdCF = stanceCFrame(rock, root.Position)
			stanceJustSet = true
			syncCollision() -- the hide toggle may have flipped since last pass
			task.wait(0.15)

			local pickaxe = util.bestPickaxe()
			if not pickaxe then
				report("no pickaxe found")
				task.wait(3)
				continue
			end
			if not util.equip(pickaxe) then
				task.wait(1)
				continue
			end
			task.wait(config.farm.equipDelay)

			-- Camera stand-off wider than the rock so the ray through the
			-- cursor lands on its surface no matter where we stand. holdOnFail
			-- keeps mid-run aim failures from snapping the view back and
			-- forth; the release happens once, at stop.
			local half = math.max(rock.Size.X, rock.Size.Y, rock.Size.Z) / 2
			if not util.aimAt(rock.Position, half + 40, true) then
				aimFails += 1
				if aimFails % 6 == 0 then
					-- Same spot from every basis keeps failing: leave this
					-- rock instead of standing there aiming at nothing.
					avoided[rock] = os.clock() + config.farm.rockSwitchDelay
					switches += 1
					report("camera cannot see this rock - moving to another")
				end
				task.wait(math.min(0.3 + aimFails * 0.2, 2))
				continue
			end
			aimFails = 0
			setPhase("mining")

			-- Swing a batch, then re-evaluate: the aim may drift, the rock may
			-- be gone, a test cap may be due.
			local batch = 0
			while running and rock.Parent and batch < 5 do
				if maxCycles and cycles >= maxCycles then
					break
				end
				if maxJuice and gained >= maxJuice then
					break
				end
				if util.juiceCount() >= config.farm.sellAt then
					break
				end

				pcall(function()
					pickaxe:Activate()
				end)
				batch += 1
				cycles += 1
				stall += 1
				task.wait(config.farm.swingDelay)
				noteJuice()
			end

			-- NOTE: no stopAim here on purpose. The aim stays bound across
			-- batches and simply rebinds to the next rock; releasing after
			-- every batch was the lock/restore churn. stopAim happens at
			-- loop end, on rotation, and in farm.stop.

			-- Chain runs only after the swings go dead; juice resets it. A
			-- flat 10 reads as "broken" on a healthy slow vein - ion on
			-- Venus drops ~1 per 30 swings, which fired ~10 false fixes per
			-- 150 swings (each a reequip + churn). Scale the threshold with
			-- the run's observed swings-per-juice instead. No juice at all
			-- - the stuck-pickaxe signature - keeps the fast flat floor.
			local stallLimit = config.farm.stallSwings
			if gained >= 1 then
				stallLimit = math.max(stallLimit, math.ceil((cycles / gained) * 1.5))
			end
			if running and stall >= stallLimit then
				fixStage = fixStage + 1
				if fixStage > 3 then
					fixStage = 1
				end
				if autoFix(fixStage, pickaxe, rock) then
					stall = 0
				else
					fixStage = 0
				end
			end
		end

		util.stopAim()
		stopHold()
		restoreCollision()
		setPhase("stopped")
		running = false
	end

	-- opts: { maxJuice = n, maxCycles = n } for tests. GUI calls farm.start() bare.
	function farm.start(opts)
		if running then
			return false
		end
		running = true
		cycles, gained, sold, fixes, switches = 0, 0, 0, 0, 0
		setPhase("starting")
		thread = task.spawn(runLoop, opts)
		return true
	end

	function farm.stop()
		running = false
		util.stopAim()
		stopHold()
		-- Restore immediately: the loop may still be sleeping out a wait.
		restoreCollision()
	end

	function farm.isRunning(): boolean
		return running
	end

	function farm.stats(): string
		return string.format(
			"%d swings · %d juice · %d sold · %d fixes · %s",
			cycles,
			gained,
			sold,
			fixes + switches,
			phase
		)
	end

	-- Called by the menu whenever the AutoFarm toggle changes.
	function farm.sync()
		if state.enabled("AutoFarm") then
			farm.start()
		else
			farm.stop()
		end
	end

	return farm
end
]==],
	["perf"] = [==[
--!strict
-- Paralyz / src/perf.luau
-- No-render mode: the cheapest safe way to keep a struggling GPU alive.
--
-- Nothing here is a "trick" - it is Roblox's own quality controls driven down
-- from the outside: lowest rendering quality, shadows off, post effects off and
-- a frame cap. The user's RX 590 has already dropped the screen once, so this
-- defaults ON when the hub loads.

return function(deps)
	local config = deps.config

	local Lighting = game:GetService("Lighting")
	local perf = {}

	local saved = nil

	local function snapshot()
		return {
			quality = settings().Rendering.QualityLevel,
			shadows = Lighting.GlobalShadows,
			fps = (getfpscap and getfpscap()) or 0,
			effects = {},
		}
	end

	local function setQuality(level: Enum.QualityLevel)
		local ok = pcall(function()
			settings().Rendering.QualityLevel = level
		end)
		return ok
	end

	-- Turns no-render on or off. Returns a short report string.
	function perf.apply(on: boolean): string
		if on then
			if not saved then
				saved = snapshot()
			end
			setQuality(Enum.QualityLevel.Level01)
			Lighting.GlobalShadows = false

			local disabled = 0
			for _, child in ipairs(Lighting:GetChildren()) do
				-- Bloom/Blur/ColorCorrection/DepthOfField/SunRays all inherit PostEffect.
				if child:IsA("PostEffect") and (child :: any).Enabled then
					(child :: any).Enabled = false
					disabled += 1
				end
			end

			if setfpscap then
				setfpscap(config.perf.fps)
			end

			return string.format(
				"quality=Level01 shadows=off effects=%d fps=%d",
				disabled,
				(getfpscap and getfpscap()) or config.perf.fps
			)
		end

		if saved then
			setQuality(saved.quality)
			Lighting.GlobalShadows = saved.shadows
			if setfpscap then
				setfpscap(saved.fps)
			end
			saved = nil
			return "restored previous graphics settings"
		end
		return "nothing was changed yet"
	end

	function perf.report(): string
		local fps = (getfpscap and getfpscap()) or 0
		return string.format(
			"fpsCap=%d quality=%s shadows=%s",
			fps,
			tostring(settings().Rendering.QualityLevel),
			tostring(Lighting.GlobalShadows)
		)
	end

	return perf
end
]==],
	["rewards"] = [==[
--!strict
-- Paralyz / src/rewards.luau
-- Free income that needs no player input.
--
-- Two paths, both measured safe in earlier sessions:
--   * Playtime: the server pushes Events.PlaytimeReward {Action = "Ready"}
--     on its1800s cycle; answering with Events.PlaytimeClaim:FireServer()
--     pays the chest. Pure listener - no polling, no input.
--   * Daily/Weekly quests: Knit QuestService:GetQuests() (may return a
--     table or a promise - both handled), then ClaimQuest(kind, id) for
--     anything Complete and not Claimed. A Daily claim paid +150 credits
--     when first verified.
--
-- The poll also gives the menu something honest to show: what is ready.

return function(deps)
	local config = deps.config
	local state = deps.state
	local util = deps.util

	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local rewards = {}

	local running = false
	local playtimeConn: RBXScriptConnection? = nil
	local claimedNow = 0
	local lastSummary = "not checked yet"

	------------------------------------------------------------- playtime
	local function startPlaytime()
		if playtimeConn then
			return
		end
		local events = ReplicatedStorage:FindFirstChild("Events")
		local reward = events and events:FindFirstChild("PlaytimeReward")
		local claim = events and events:FindFirstChild("PlaytimeClaim")
		if not (reward and claim) then
			return
		end
		playtimeConn = (reward :: RemoteEvent).OnClientEvent:Connect(function(a1, a2)
			-- Payload shape observed as a table {Action = "Ready"}; accept a
			-- bare "Ready" string too rather than miss the window.
			local ready = (type(a1) == "table" and (a1 :: any).Action == "Ready")
				or a1 == "Ready"
				or (type(a2) == "table" and (a2 :: any).Action == "Ready")
			if not ready then
				return
			end
			pcall(function()
				(claim :: RemoteEvent):FireServer()
			end)
			claimedNow += 1
			util.notify("Playtime", "chest ready - claimed")
		end)
	end

	local function stopPlaytime()
		if playtimeConn then
			playtimeConn:Disconnect()
			playtimeConn = nil
		end
	end

	---------------------------------------------------------------- quests
	local function getQuestService(): any?
		local ok, knit = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
		end)
		if not ok then
			return nil
		end
		local ok2, service = pcall(function()
			return (knit :: any).GetService("QuestService")
		end)
		if not ok2 then
			return nil
		end
		return service
	end

	local function fetchQuests(service: any): { [string]: any }?
		local ok, res = pcall(function()
			return service:GetQuests()
		end)
		if not ok then
			return nil
		end
		-- Knit may hand back a promise; await it inside the same guard.
		if typeof(res) == "Promise" then
			local ok2, val = pcall(function()
				return (res :: any):await()
			end)
			if not ok2 then
				return nil
			end
			res = val
		end
		if type(res) ~= "table" then
			return nil
		end
		return res
	end

	-- One pass: claim everything ready, summarise the rest. Returns the
	-- number of claims fired.
	function rewards.claimReady(): number
		local service = getQuestService()
		if not service then
			return 0
		end
		local quests = fetchQuests(service)
		if not quests then
			return 0
		end
		local claimed = 0
		local ready = 0
		local total = 0
		for _, kind in ipairs({ "Daily", "Weekly" }) do
			local bucket = (quests :: any)[kind]
			if type(bucket) == "table" then
				for _, quest in pairs(bucket) do
					if type(quest) == "table" then
						total += 1
						if (quest :: any).Complete and not (quest :: any).Claimed then
							ready += 1
							local ok = pcall(function()
								service:ClaimQuest(kind, (quest :: any).Id)
							end)
							if ok then
								claimed += 1
								local reward = (quest :: any).Reward
								util.notify(
									"Quest claimed",
									string.format(
										"%s: %s (+%s %s)",
										kind,
										(quest :: any).Name or (quest :: any).Id,
										reward and tostring(reward.Amount) or "?",
										reward and tostring(reward.Type) or "reward"
									)
								)
							end
							task.wait(0.3) -- one claim at a time, politely
						end
					end
				end
			end
		end
		claimedNow += claimed
		lastSummary = ready > 0
				and string.format("%d ready / %d total - claimed %d", ready, total, claimed)
			or string.format("all clear - %d quests tracked", total)
		return claimed
	end

	----------------------------------------------------------------- loop
	-- A RemoteFunction that never returns would freeze this loop inside
	-- pcall forever - pcall catches errors, not hangs, and this game has
	-- proven RFs can wedge (see NOTES: ServerControl). So each pass runs
	-- in its own thread with a completion flag: a pass that does not come
	-- back within config.rewards.passTimeout is abandoned (one zombie
	-- thread, never more) and the loop keeps ticking. A merely-slow pass
	-- self-heals: when it finally returns, it clears the flag and the
	-- normal cadence resumes.
	local passPending = false
	local hangNotified = false

	local function pollLoop()
		while running do
			if state.enabled("AutoRewards") then
				if passPending then
					if not hangNotified then
						hangNotified = true
						util.notify(
							"Rewards",
							"quest pass stopped answering - pausing quest claims (playtime chests still auto-claim)"
						)
					end
				else
					passPending = true
					task.spawn(function()
						pcall(function()
							rewards.claimReady()
						end)
						passPending = false
						hangNotified = false
					end)
					-- Give a healthy pass time to finish in-place so stats
					-- refresh promptly; timeout just moves on to the wait.
					local t0 = os.clock()
					while passPending and os.clock() - t0 < config.rewards.passTimeout do
						task.wait(0.25)
					end
				end
			end
			task.wait(config.rewards.pollDelay)
		end
	end

	function rewards.start(): boolean
		if running then
			return false
		end
		running = true
		startPlaytime()
		task.spawn(pollLoop)
		return true
	end

	function rewards.stop()
		running = false
		stopPlaytime()
	end

	function rewards.sync()
		-- The listener runs regardless (a free chest arriving while the
		-- toggle is off should still be grabbed); the poll only claims
		-- quests while AutoRewards is on.
		if not playtimeConn then
			startPlaytime()
		end
	end

	function rewards.stats(): string
		return string.format("%d claimed - %s", claimedNow, lastSummary)
	end

	return rewards
end
]==],
	["state"] = [==[
--!strict
-- Paralyz / src/state.luau
-- The single owner of every value the menu shows.
--
-- Rule that keeps Rayfield Gen2 sane: exactly one owner per value.
--   * The GUI writes state (element callback -> state.set)
--   * Code writes state (state.set)
--   * state pushes the change back to the GUI with Set(value, true), which
--     deliberately skips the element's callback, so nothing can bounce forever.

local state = {}

local flags: { [string]: any } = {}
local handles: { [string]: any } = {}
local watchers: { [string]: { [any]: (value: any) -> () } } = {}

function state.get(key: string): any
	return flags[key]
end

function state.set(key: string, value: any): any
	flags[key] = value

	-- Reflect into the menu without re-entering its callback.
	local handle = handles[key]
	if handle then
		pcall(function()
			handle:Set(value, true)
		end)
	end

	local bucket = watchers[key]
	if bucket then
		for _, fn in pairs(bucket) do
			task.spawn(pcall, fn, value)
		end
	end

	return value
end

-- Fire watchers without changing the value (used by one-shot buttons).
function state.touch(key: string): any
	local bucket = watchers[key]
	if bucket then
		for _, fn in pairs(bucket) do
			task.spawn(pcall, fn, flags[key])
		end
	end
	return flags[key]
end

-- Called by the ui helpers once an element exists.
function state.bind(key: string, handle: any)
	handles[key] = handle
	if flags[key] ~= nil then
		pcall(function()
			handle:Set(flags[key], true)
		end)
	elseif handle.value ~= nil then
		-- First sight of this element: the UI's own default (or a value restored
		-- before we got here) becomes the state, so the toggle and the truth
		-- never disagree. No watchers yet at this point, so this is a plain seed.
		flags[key] = handle.value
	end
end

-- Subscribe to a key. Returns an unsubscribe function.
function state.on(key: string, fn: (value: any) -> ()): () -> ()
	watchers[key] = watchers[key] or {}
	local slot = {}
	watchers[key][slot] = fn
	return function()
		local bucket = watchers[key]
		if bucket then
			bucket[slot] = nil
		end
	end
end

-- For code that only wants to know "is this feature running".
function state.enabled(key: string): boolean
	return flags[key] == true
end

return state
]==],
	["travel"] = [==[
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
]==],
	["ui"] = [==[
--!strict
-- Paralyz / src/ui.luau
-- Thin, defensive wrappers over Rayfield Gen2.
--
-- Every element is bound to a state key through state.bind(), and every callback
-- writes into state, which is the only owner of the value. Element creation is
-- pcall-wrapped: a constructor Real's Rayfield build does not have (CreateSection
-- is the one that historically bites) degrades to "no heading" instead of killing
-- the whole menu.

return function(deps)
	local state = deps.state

	local ui = {}

	local function guard(what, fn)
		local ok, res = pcall(fn)
		if ok then
			return res
		end
		warn("[Paralyz] ui." .. what .. " failed: " .. tostring(res))
		return nil
	end

	-- A heading above a run of elements. Optional, hence guarded.
	function ui.section(tab, name: string)
		return guard("section", function()
			return tab:CreateSection({ name = name })
		end)
	end

	function ui.toggle(tab, key: string, props)
		props = props or {}
		props.flag = key
		props.callback = function(value)
			state.set(key, value)
		end
		local handle = guard("toggle", function()
			return tab:CreateToggle(props)
		end)
		if handle then
			state.bind(key, handle)
		end
		return handle
	end

	function ui.slider(tab, key: string, props)
		props = props or {}
		props.flag = key
		props.callback = function(value)
			state.set(key, value)
		end
		if not props.range then
			props.range = { 0, 100 }
		end
		local handle = guard("slider", function()
			return tab:CreateSlider(props)
		end)
		if handle then
			state.bind(key, handle)
		end
		return handle
	end

	function ui.dropdown(tab, key: string, props)
		props = props or {}
		props.flag = key
		props.callback = function(value)
			-- Gen2 hands a table back in both modes; unwrap single-select for callers.
			if not props.multiSelect and type(value) == "table" then
				state.set(key, value[1])
			else
				state.set(key, value)
			end
		end
		local handle = guard("dropdown", function()
			return tab:CreateDropdown(props)
		end)
		if handle then
			state.bind(key, handle)
			if not props.multiSelect then
				-- .value is always a table, even in single mode: keep the state
				-- as the bare string the callback would have delivered.
				local current = state.get(key)
				if type(current) == "table" then
					state.set(key, current[1])
				end
			end
		end
		return handle
	end

	-- One-shot action, no state attached.
	function ui.button(tab, props)
		return guard("button", function()
			return tab:CreateButton(props)
		end)
	end

	function ui.keybind(tab, key: string, props)
		props = props or {}
		props.flag = key
		props.callback = function(value)
			state.set(key, value)
		end
		local handle = guard("keybind", function()
			return tab:CreateKeybind(props)
		end)
		if handle then
			state.bind(key, handle)
		end
		return handle
	end

	-- Read-only number (credits, juice on hand). Kept outside state: it is an
	-- observation of the game, not something the player sets.
	function ui.stat(tab, props)
		return guard("stat", function()
			return tab:CreateStat(props)
		end)
	end

	return ui
end
]==],
	["util"] = [==[
--!strict
-- Paralyz / src/util.luau
-- Character, tool, juice, rock and camera-aim helpers shared by every module.

return function(deps)
	local config = deps.config

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")

	local util = {}

	util.Players = Players
	util.ReplicatedStorage = ReplicatedStorage
	util.RunService = RunService

	local LocalPlayer = Players.LocalPlayer

	------------------------------------------------------------------ character
	function util.character()
		return LocalPlayer.Character
	end

	function util.humanoid(): Humanoid?
		local char = util.character()
		return char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	end

	function util.root(): BasePart?
		local char = util.character()
		return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	end

	function util.alive(): boolean
		local hum = util.humanoid()
		return hum ~= nil and hum.Health > 0
	end

	-------------------------------------------------------------------- tools
	local function toolList(): { Instance }
		local char = util.character()
		local out = {}
		for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do
			table.insert(out, t)
		end
		if char then
			for _, t in ipairs(char:GetChildren()) do
				if t:IsA("Tool") then
					table.insert(out, t)
				end
			end
		end
		return out
	end

	function util.findTool(namePattern: string): Tool?
		local needle = string.lower(namePattern)
		for _, t in ipairs(toolList()) do
			if t:IsA("Tool") and string.find(string.lower(t.Name), needle, 1, true) then
				return t
			end
		end
		return nil
	end

	-- Pickaxes, best first: Op > Omega > Diamond > Metal > Iron > plain Pickaxe.
	local PICKAXE_RANK = { "op", "omega", "diamond", "metal", "iron", "pickaxe" }

	function util.bestPickaxe(): Tool?
		local found = {}
		for _, t in ipairs(toolList()) do
			if t:IsA("Tool") and string.find(string.lower(t.Name), "pickaxe", 1, true) then
				table.insert(found, t)
			end
		end
		if #found == 0 then
			return nil
		end
		local best, bestRank = found[1], #PICKAXE_RANK
		for _, t in ipairs(found) do
			local low = string.lower(t.Name)
			for i, key in ipairs(PICKAXE_RANK) do
				if string.find(low, key, 1, true) and i < bestRank then
					best, bestRank = t, i
					break
				end
			end
		end
		return best
	end

	function util.isEquipped(tool: Tool): boolean
		local char = util.character()
		return char ~= nil and tool.Parent == char
	end

	-- Equip through the Humanoid. Never set tool.Parent = char directly:
	-- that leaves a stuck tool whose Tool.Activated never fires, so mining
	-- silently dies. Unequip strays first, then Humanoid:EquipTool - the
	-- sequence the game itself uses (user's fix: unequip -> re-equip).
	function util.equip(tool: Tool, timeout: number?): boolean
		if not tool then
			return false
		end
		if util.isEquipped(tool) then
			return true
		end
		local char = util.character()
		local hum = util.humanoid()
		if not char or not hum then
			return false
		end
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and t ~= tool then
				t.Parent = LocalPlayer.Backpack
			end
		end
		hum:EquipTool(tool)
		local deadline = os.clock() + (timeout or 2)
		while os.clock() < deadline do
			if util.isEquipped(tool) then
				return true
			end
			task.wait(0.05)
		end
		return util.isEquipped(tool)
	end

	-- Full heal for a stuck pickaxe: send it back to the Backpack, let the
	-- character settle, then re-equip through the Humanoid. This is the
	-- only sequence proven to restore Tool.Activated on a stuck tool, and
	-- what the farm loop's auto-fix uses when swings stop landing.
	function util.reequip(tool: Tool, timeout: number?): boolean
		if not tool then
			return false
		end
		local hum = util.humanoid()
		if not hum then
			return false
		end
		tool.Parent = LocalPlayer.Backpack
		task.wait(0.15)
		hum:EquipTool(tool)
		local deadline = os.clock() + (timeout or 2)
		while os.clock() < deadline do
			if util.isEquipped(tool) then
				return true
			end
			task.wait(0.05)
		end
		return util.isEquipped(tool)
	end

	function util.equippedTool(): Tool?
		local char = util.character()
		return char and char:FindFirstChildOfClass("Tool") :: Tool?
	end

	-------------------------------------------------------------------- juice
	-- MoonJuice is carried as ordinary Tools that own a Credits NumberValue;
	-- the sell remote counts them, so this list is the whole currency model.
	function util.juiceTools(): { { tool: Tool, credits: number } }
		local out = {}
		for _, t in ipairs(toolList()) do
			if t:IsA("Tool") then
				local c = t:FindFirstChild("Credits")
				if c and c:IsA("NumberValue") then
					table.insert(out, { tool = t, credits = c.Value })
				end
			end
		end
		return out
	end

	function util.juiceCount(): number
		return #util.juiceTools()
	end

	function util.juiceValue(): number
		local total = 0
		for _, entry in ipairs(util.juiceTools()) do
			total += entry.credits
		end
		return total
	end

	function util.credits(): number
		local stats = LocalPlayer:FindFirstChild("Stats")
		local credits = stats and stats:FindFirstChild("Credits")
		return credits and (credits :: NumberValue).Value or 0
	end

	-- Sells the whole stack. This is the exact call the game's own
	-- "sell everything" button makes, so the server treats it identically.
	function util.sellAll(): number
		local count = util.juiceCount()
		if count == 0 then
			return 0
		end
		local events = ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("SellMoonjuice")
		if remote then
			(remote :: RemoteEvent):FireServer(count, true)
		end
		return count
	end

	-- Ion juice: the anti-matter machine's input. Plain MoonJuice does NOT
	-- match (measured: a verified hold at the converter consumed nothing
	-- with5 plain stacks aboard - the machine is ion-only per its labels).
	function util.ionJuiceCount(): number
		local n = 0
		for _, entry in ipairs(util.juiceTools()) do
			if string.find(string.lower(entry.tool.Name), "ion", 1, true) then
				n += 1
			end
		end
		return n
	end

	-- The only conversion interface in the game: the SpaceStation's
	-- "Insert Moonjuice" prompt (2.0s hold, 10 studs, line of sight).
	-- Buildings phase in and out, so this resolves freshly every call.
	function util.converterPrompt(): ProximityPrompt?
		local planets = workspace:FindFirstChild("Planets")
		if not planets then
			return nil
		end
		for _, planet in ipairs(planets:GetChildren()) do
			local station = planet:FindFirstChild("SpaceStation")
			local machine = station and station:FindFirstChild("ConverterMachine")
			local well = machine and machine:FindFirstChild("PartProximity")
			local prompt = well and well:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt then
				return prompt
			end
		end
		return nil
	end

	-------------------------------------------------------------------- rocks
	-- Rocks live in a folder called "Rocks" somewhere under each planet - on
	-- some planets it is a direct child, on others it hangs off the planet's
	-- Center part - and the server fills it in waves.
	function util.rocks(): { BasePart }
		local out = {}
		local planets = workspace:FindFirstChild("Planets")
		if not planets then
			return out
		end
		for _, planet in ipairs(planets:GetChildren()) do
			for _, inst in ipairs(planet:GetDescendants()) do
				if inst:IsA("Folder") and inst.Name == "Rocks" then
					for _, rock in ipairs((inst :: Folder):GetChildren()) do
						if rock:IsA("BasePart") then
							table.insert(out, rock)
						end
					end
				end
			end
		end
		return out
	end

	function util.minableRocks(): { BasePart }
		local out = {}
		for _, rock in ipairs(util.rocks()) do
			local flag = rock:FindFirstChild("Minable")
			-- Minable=false has been observed on rocks that still accept a swing,
			-- so the flag is reported but never used as a filter by default.
			if flag == nil or flag:IsA("BoolValue") then
				table.insert(out, rock)
			end
		end
		return out
	end

	function util.nearestRock(from: Vector3?): BasePart?
		local origin = from or (util.root() and util.root().Position)
		if not origin then
			return nil
		end
		local best, bestDist
		for _, rock in ipairs(util.minableRocks()) do
			local d = (rock.Position - origin).Magnitude
			if not bestDist or d < bestDist then
				best, bestDist = rock, d
			end
		end
		return best
	end

	-- A part inside some planet's Rocks folder - what the server accepts as
	-- a swing target (aiming at any other part drops the swing, measured).
	function util.isRockPart(inst: Instance?): boolean
		local p: Instance? = inst
		while p and p ~= workspace do
			if p:IsA("Folder") and p.Name == "Rocks" then
				return true
			end
			p = p.Parent
		end
		return false
	end

	-- Rocks within radius of a point: what "loaded around me" means. Rocks
	-- from the planet you just left linger while they stream out, and the
	-- server range rule makes swinging at them useless anyway, so every
	-- proximity question in the farm is asked through this.
	function util.rocksNear(origin: Vector3, radius: number): { BasePart }
		local out = {}
		for _, rock in ipairs(util.rocks()) do
			if (rock.Position - origin).Magnitude <= radius then
				table.insert(out, rock)
			end
		end
		return out
	end

	-- After a teleport, wait until the destination has actually streamed in:
	-- the server spawns rocks a few seconds after the character arrives, and
	-- judging emptiness from far away (the old behaviour) just bounced the
	-- farm across unloaded space. Returns the rock count when the wait ends;
	-- 0 means still empty after `timeout` seconds.
	function util.settleRocks(pos: Vector3, timeout: number, radius: number?): number
		local r = radius or config.farm.streamRadius
		local deadline = os.clock() + timeout
		local origin = pos
		while os.clock() < deadline do
			local root = util.root()
			origin = root and root.Position or pos
			local n = #util.rocksNear(origin, r)
			if n > 0 then
				return n
			end
			task.wait(0.5)
		end
		local root = util.root()
		origin = root and root.Position or pos
		return #util.rocksNear(origin, r)
	end

	-- Where a teleport should land: raycast down from above the point so the
	-- character ends on the surface instead of inside the geometry. The
	-- near ray covers hubs and small structures (and only ever lands in
	-- pos+600..pos-900); planet centres sit INSIDE their own mesh, where a
	-- ray starting inside cannot hit the surface (backfaces), so a miss
	-- retries from high above before giving up.
	function util.dropToSurface(pos: Vector3): Vector3
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { util.character() }
		local hit = workspace:Raycast(pos + Vector3.new(0, 600, 0), Vector3.new(0, -1500, 0), params)
		if hit then
			return hit.Position + Vector3.new(0, 5, 0)
		end
		hit = workspace:Raycast(pos + Vector3.new(0, 5000, 0), Vector3.new(0, -10000, 0), params)
		if hit then
			return hit.Position + Vector3.new(0, 5, 0)
		end
		return pos + Vector3.new(0, 10, 0)
	end

	-- Every teleport in the hub fires this (travel and the farm both call
	-- it): the farm pins the character with a per-frame hold, so a teleport
	-- the hold does not know about gets overwritten on the very next frame.
	-- The farm assigns a listener that moves the hold onto the new spot.
	local teleportListener: ((CFrame) -> ())? = nil

	function util.onTeleport(fn: ((CFrame) -> ()))
		teleportListener = fn
	end

	function util.teleported(cf: CFrame)
		if teleportListener then
			task.spawn(pcall, teleportListener, cf)
		end
	end

	-- Every planet that exists right now: centre plus how many rocks are
	-- streaming at it. Rocks only exist while somebody is near the planet,
	-- so this doubles as "where can I actually mine".
	function util.planetScan(): { { name: string, centre: Vector3, rocks: number } }
		local out = {}
		local planets = workspace:FindFirstChild("Planets")
		if not planets then
			return out
		end
		for _, planet in ipairs(planets:GetChildren()) do
			local centre: Vector3? = nil
			if planet:IsA("BasePart") then
				centre = (planet :: BasePart).Position
			else
				local c = (planet :: any):FindFirstChild("Center")
				if c and c:IsA("BasePart") then
					centre = (c :: BasePart).Position
				else
					local p = (planet :: any):FindFirstChildWhichIsA("BasePart", true)
					centre = p and (p :: BasePart).Position or nil
				end
			end
			if centre then
				local rocks = 0
				for _, inst in ipairs((planet :: any):GetDescendants()) do
					if inst:IsA("Folder") and inst.Name == "Rocks" then
						rocks += #(inst :: Folder):GetChildren()
					end
				end
				table.insert(out, { name = planet.Name, centre = centre, rocks = rocks })
			end
		end
		return out
	end

	-- Converter economy: PumpJack/Pumper buildings ("MoonJuice Tanks Will
	-- Spawn Every 1 Minute"), and the SpaceStation anti-matter machine
	-- (prompt "Insert Moonjuice": 1 Ion MoonJuice -> 1 Anti Matter
	-- MoonJuice, worth more than plain juice). None of these are permanent -
	-- they only exist once somebody spends Events.Buy on them, so phases
	-- bring them and go. This reports what is actually standing in the
	-- world right now; the use-it options wait on live observation.
	function util.converters(): { string }
		local out, seen = {}, {}
		local function add(label: string)
			if not seen[label] then
				seen[label] = true
				table.insert(out, label)
			end
		end
		for _, child in ipairs(workspace:GetChildren()) do
			if string.find(child.Name, "Pump", 1, true) then
				add(child.Name)
			end
		end
		local planets = workspace:FindFirstChild("Planets")
		if planets then
			for _, planet in ipairs(planets:GetChildren()) do
				local station = (planet :: any):FindFirstChild("SpaceStation")
				if station and (station :: any):FindFirstChild("ConverterMachine") then
					add("AntiMatter@" .. planet.Name)
				end
			end
		end
		return out
	end

	------------------------------------------------------------------ monsters
	function util.monsters(): { Model }
		local out = {}
		local unanchored = workspace:FindFirstChild("Unanchored")
		if not unanchored then
			return out
		end
		for _, folderName in ipairs({ "MoonMonsters", "SmallMoonMonsters" }) do
			local folder = unanchored:FindFirstChild(folderName)
			if folder then
				for _, child in ipairs(folder:GetChildren()) do
					if child:IsA("Model") then
						table.insert(out, child)
					end
				end
			end
		end
		return out
	end

	function util.aliveMonsters(): { Model }
		local out = {}
		for _, model in ipairs(util.monsters()) do
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				table.insert(out, model)
			end
		end
		return out
	end

	function util.nearestMonster(from: Vector3?, maxDist: number?): Model?
		local origin = from or (util.root() and util.root().Position)
		if not origin then
			return nil
		end
		local best, bestDist
		for _, model in ipairs(util.aliveMonsters()) do
			local pivot = model:GetPivot().Position
			local d = (pivot - origin).Magnitude
			if (not maxDist or d <= maxDist) and (not bestDist or d < bestDist) then
				best, bestDist = model, d
			end
		end
		return best
	end

	--------------------------------------------------------------------- aim
	-- The game asks the client for Mouse.Target when a tool is activated, so
	-- a swing only pays while the camera's ray through the mouse lands on a
	-- rock the character is in range of (both rules measured: non-rock targets
	-- and >30-stud distance are dropped, and firing the remote directly
	-- without a real Tool.Activated is ignored outright). aimAt therefore
	-- tries several camera bases - side, straight up, far side - and ALWAYS
	-- releases the camera again when every base fails; an unbound-on-fail
	-- solve is what used to leave the view glued to the rock while no swings
	-- happened at all.
	local AIM_BIND = "ParalyzAim"

	function util.stopAim()
		pcall(function()
			RunService:UnbindFromRenderStep(AIM_BIND)
		end)
	end

	local function solveToward(cam: Camera, targetPos: Vector3, base: Vector3): CFrame
		local mouse = LocalPlayer:GetMouse()
		local px = Vector2.new(mouse.X, mouse.Y)
		local cf = CFrame.lookAt(base, targetPos)
		for _ = 1, 12 do
			cam.CFrame = cf
			local ray = cam:ViewportPointToRay(px.X, px.Y)
			local desired = targetPos - ray.Origin
			if desired.Magnitude < 1 then
				break
			end
			desired = desired.Unit
			cf = cf
				* CFrame.lookAt(Vector3.zero, ray.Direction)
					:ToObjectSpace(CFrame.lookAt(Vector3.zero, desired))
		end
		return cf
	end

	-- True when this hit would really be paid out: any rock part within the
	-- server's swing range of the character (a neighbouring rock is a valid
	-- target too - rejecting those was the aim-failure storm), or, for bare
	-- positions such as a monster pivot, a hit close to that point.
	local function aimValid(mt: BasePart?, target: Vector3): boolean
		if not mt then
			return false
		end
		if util.isRockPart(mt) then
			local root = util.root()
			return root ~= nil and util.dist(root.Position, mt.Position) <= config.farm.maxRange + 4
		end
		return util.dist(mt.Position, target) <= 12
	end

	-- holdOnFail: keep the camera where the last attempt left it instead of
	-- snapping it back to the pre-aim view. The farm passes this while it
	-- runs: restore-then-relock every batch was the visible camera churn
	-- (lock, restore, lock, restore). While running the aim simply moves
	-- from target to target; the view is handed back exactly once, when the
	-- farm stops.
	function util.aimAt(targetPos: Vector3?, standOff: number?, holdOnFail: boolean?): boolean
		local target = targetPos or (util.root() and util.root().Position)
		if not target then
			return false
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return false
		end
		local startCF = cam.CFrame
		local so = standOff or config.farm.aimDistance
		local side = startCF.Position - target
		if side.Magnitude < 1 then
			side = Vector3.new(0, 1, 0)
		end
		side = side.Unit
		-- Bases in order of robustness. Straight up is the reliable one:
		-- nothing on the ground can occlude a rock seen from directly above,
		-- and after a long teleport the old single side-basis pointed into
		-- unloaded geometry, which is where the permanent failures came from.
		local bases = {
			target + side * so + Vector3.new(0, 3, 0),
			target + Vector3.new(0, math.max(so, 30), 0),
			target - side * so + Vector3.new(0, 3, 0),
		}
		for _, base in ipairs(bases) do
			local cf = solveToward(cam, target, base)
			util.stopAim()
			RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 1, function()
				cam.CFrame = cf
			end)
			task.wait() -- let the frame land so Mouse.Target refreshes
			if aimValid(util.mouseTarget(), target) then
				return true
			end
			if holdOnFail then
				-- Leave the last attempt bound: the next aim call rebinds
				-- anyway, and a mid-run restore is exactly the snap the user
				-- sees as camera jitter.
				continue
			end
			util.stopAim()
		end
		if holdOnFail then
			return false
		end
		-- Nothing worked and nobody is mid-run: hand the view back exactly as it was.
		cam.CFrame = startCF
		return false
	end

	function util.mouseTarget(): BasePart?
		return LocalPlayer:GetMouse().Target :: BasePart?
	end

	-------------------------------------------------------------------- misc
	function util.dist(a: Vector3, b: Vector3): number
		return (a - b).Magnitude
	end

	function util.lookAt(pos: Vector3)
		local cam = workspace.CurrentCamera
		local root = util.root()
		if cam and root then
			cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
		end
	end

	-- Notification hook the loader installs once the window exists.
	local notifyFn: ((title: string, content: string?) -> ())? = nil

	function util.setNotify(fn)
		notifyFn = fn
	end

	function util.notify(title: string, content: string?)
		if notifyFn then
			task.spawn(pcall, notifyFn, title, content)
		end
	end

	function util.safe(fn, ...)
		local args = table.pack(...)
		local ok, res = pcall(function()
			return fn(table.unpack(args, 1, args.n))
		end)
		if ok then
			return res
		end
		return nil
	end

	return util
end
]==],
}

--------------------------------------------------------------- module fetch
local function fetchModule(name: string): any
	local source: string?
	if PARALYZ_MODULES then
		source = PARALYZ_MODULES[name]
		if not source then
			error("[Paralyz] module missing from bundle: " .. name, 2)
		end
	else
		local ok, result = pcall(function()
			return game:HttpGet(BASE .. name .. ".luau")
		end)
		if not ok then
			error("[Paralyz] download failed for " .. name .. ": " .. tostring(result), 2)
		end
		source = result
	end

	local chunk, err = loadstring(source, "Paralyz." .. name)
	if not chunk then
		error("[Paralyz] compile error in " .. name .. ": " .. tostring(err), 2)
	end
	local ok, result = pcall(chunk)
	if not ok then
		error("[Paralyz] error in " .. name .. ": " .. tostring(result), 2)
	end
	return result
end

----------------------------------------------------- tear down a previous run
local previous = (getgenv and getgenv().Paralyz) or nil
if previous and previous.shutdown then
	pcall(previous.shutdown)
end

-------------------------------------------------------------- build the modules
local config = fetchModule("config") -- config and state are data, not factories
local state = fetchModule("state")
local ui = fetchModule("ui")({ state = state })
local util = fetchModule("util")({ config = config })
local perf = fetchModule("perf")({ config = config })
local esp = fetchModule("esp")({ config = config, state = state, util = util })
local farm = fetchModule("farm")({ config = config, state = state, util = util })
local combat = fetchModule("combat")({ config = config, state = state, util = util })
local travel = fetchModule("travel")({ config = config, state = state, util = util })
local rewards = fetchModule("rewards")({ config = config, state = state, util = util })

--------------------------------------------------------------- Rayfield Gen2
local okRayfield, Rayfield = pcall(function()
	return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)
if not okRayfield or not Rayfield then
	error("[Paralyz] Rayfield Gen2 failed to load: " .. tostring(Rayfield))
end

-- Forward declarations: the Unload button closes over these before their
-- definitions are reached.
local window
local shutdown

window = Rayfield:CreateWindow({
	name = "Paralyz",
	subtitle = "The Moon Wakes Up",
	sidebarLayout = true,
	configuration = {
		autoSave = true,
		autoLoad = true,
		fileName = "Paralyz",
	},
})

util.setNotify(function(title: string, content: string?)
	window:Notify({ title = title, content = content or "", duration = 4 })
end)

pcall(function()
	window:SetProfile(game:GetService("Players").LocalPlayer.DisplayName .. "  ·  Paralyz v" .. VERSION)
end)

--------------------------------------------------------------------- the tabs
local farmTab = window:CreateTab({ name = "Farm" })
local espTab = window:CreateTab({ name = "ESP" })
local travelTab = window:CreateTab({ name = "Travel" })
local combatTab = window:CreateTab({ name = "Combat" })
local settingsTab = window:CreateTab({ name = "Settings" })

-- Farm -------------------------------------------------------------------
ui.section(farmTab, "Auto Farm")

ui.toggle(farmTab, "AutoFarm", {
	name = "Auto Farm",
	description = "Mines the nearest rock, banks the MoonJuice and sells it.",
})

ui.slider(farmTab, "SellAt", {
	name = "Sell at",
	description = "How many MoonJuice stacks to hold before selling.",
	range = { 1, 25 },
	increment = 1,
	value = config.farm.sellAt,
	suffix = " stacks",
})

ui.slider(farmTab, "SwingDelay", {
	name = "Swing delay",
	description = "Seconds between pickaxe swings.",
	range = { 0.15, 2 },
	increment = 0.05,
	value = config.farm.swingDelay,
	suffix = "s",
})

ui.toggle(farmTab, "HideMining", {
	name = "Hide mining",
	description = "Stands the character inside the rock where nobody can see it. The server only accepts swings within ~30 studs of a rock, so staying hidden and staying paid are the same spot. Default ON: visible mining was the source of the far-teleport complaints.",
	value = true,
})

ui.toggle(farmTab, "BlackScreen", {
	name = "Black screen",
	description = "Veils the whole screen - game and menu - with black while the farm runs. Input still passes through, so the toggle stays clickable.",
})

ui.toggle(farmTab, "AutoConvert", {
	name = "Convert before selling",
	description = "Ion juice runs through the SpaceStation anti-matter machine first, then everything sells. Measured: the machine rejects plain juice, so this only makes the trip when ion stacks actually exist.",
	value = true,
})

ui.button(farmTab, {
	name = "Sell everything now",
	description = "Same call the game's own sell button makes.",
	callback = function()
		local sold = util.sellAll()
		window:Notify({
			title = "Sold",
			content = sold > 0 and (sold .. " stacks") or "nothing to sell",
			duration = 3,
		})
	end,
})

ui.section(farmTab, "Wallet")

local creditsStat = ui.stat(farmTab, { name = "Credits", value = util.credits() })
local juiceStat = ui.stat(farmTab, { name = "MoonJuice on hand", value = util.juiceValue() })
local farmStat = ui.stat(farmTab, { name = "Farm", value = "idle" })
local converterStat = ui.stat(farmTab, { name = "Converters built", value = "..." })

ui.section(farmTab, "Income")

ui.toggle(farmTab, "AutoRewards", {
	name = "Auto rewards",
	description = "Claims playtime chests (event push) and any completed daily/weekly quest the moment they are ready. Free income that needs no player input.",
	value = true,
})

local questStat = ui.stat(farmTab, { name = "Quests", value = "checking..." })

-- ESP --------------------------------------------------------------------
ui.section(espTab, "Overlays")

ui.toggle(espTab, "ESPPlayers", {
	name = "Players",
	description = "Name, health and distance.",
	value = config.esp.players,
})
ui.toggle(espTab, "ESPMonsters", {
	name = "Monsters",
	description = "Moonfected and moon monsters.",
	value = config.esp.monsters,
})
ui.toggle(espTab, "ESPJuice", {
	name = "MoonJuice",
	description = "Juice tanks lying in the world.",
	value = config.esp.juice,
})
ui.toggle(espTab, "ESPRocks", {
	name = "Rocks",
	description = "Mineable rocks on every planet.",
	value = config.esp.rocks,
})
ui.toggle(espTab, "ESPLabels", {
	name = "Name labels",
	description = "Draw name, health and distance over the nearest visible target.",
	value = config.esp.labels,
})

-- Travel -----------------------------------------------------------------
ui.section(travelTab, "Teleport")

ui.dropdown(travelTab, "TeleportDest", {
	name = "Destination",
	description = "Places that exist in the current world phase.",
	options = travel.destinationNames(),
	value = "City",
})

ui.button(travelTab, {
	name = "Teleport",
	description = "Jump to the selected destination.",
	callback = function()
		local dest = state.get("TeleportDest") or "City"
		travel.to(dest)
	end,
})

ui.button(travelTab, {
	name = "To nearest rock",
	description = "Land right next to the closest rock.",
	callback = function()
		local rock = util.nearestRock()
		if rock then
			travel.toPosition(rock.Position)
		else
			window:Notify({ title = "Travel", content = "No rocks in the world right now", duration = 3 })
		end
	end,
})

ui.section(travelTab, "Movement")

ui.toggle(travelTab, "Noclip", {
	name = "Noclip",
	description = "Walk through terrain and walls.",
})
ui.toggle(travelTab, "Fly", {
	name = "Fly",
	description = "WASD + Space/Ctrl, camera relative.",
})
ui.slider(travelTab, "FlySpeed", {
	name = "Fly speed",
	description = "Studs per second = value x 60. 8 is ~480/s.",
	range = { 0.5, 16 },
	increment = 0.5,
	value = config.travel.flySpeed,
})

-- Combat -----------------------------------------------------------------
ui.section(combatTab, "Keep distance")

ui.toggle(combatTab, "Avoid", {
	name = "Keep distance",
	description = "Step away when a monster gets too close.",
})

ui.section(combatTab, "Gun mods")

ui.toggle(combatTab, "GunRapid", {
	name = "No cooldown",
	description = "Rail/Rocket refire as fast as the server answers. Moon Gun (HexSpitter): keeps its own fire loop running, perfect accuracy, damage pinned to max. You aim - the mod never moves your camera.",
})
ui.toggle(combatTab, "GunVolley", {
	name = "Volley",
	description = "Every rail shot sprays every monster in range; the Moon Gun switches to multi-pellet bursts. Bigger hitbox client-side - what the server kills is its call.",
})

-- Settings ---------------------------------------------------------------
ui.section(settingsTab, "Performance")

ui.toggle(settingsTab, "NoRender", {
	name = "No-render mode",
	description = "Lowest quality, no shadows, no post effects, capped FPS. Protects the GPU.",
	value = true,
})
ui.slider(settingsTab, "FpsCap", {
	name = "FPS cap",
	description = "Frame cap while no-render is on.",
	range = { 10, 60 },
	increment = 5,
	value = config.perf.fps,
	suffix = " fps",
})

ui.section(settingsTab, "Hub")

ui.button(settingsTab, {
	name = "Unload Paralyz",
	description = "Stops every module and destroys the menu.",
	callback = function()
		shutdown()
	end,
})

------------------------------------------------------------------- wiring
local function applySellAt(v)
	if typeof(v) == "number" then
		config.farm.sellAt = math.clamp(math.floor(v), 1, 25)
	end
end

local function applySwingDelay(v)
	if typeof(v) == "number" then
		config.farm.swingDelay = math.clamp(v, 0.15, 2)
	end
end

local function applyFlySpeed(v)
	if typeof(v) == "number" then
		config.travel.flySpeed = v
	end
end

local function applyNoRender(v)
	local report = perf.apply(v == true)
	window:Notify({ title = "No-render", content = report, duration = 4 })
end

local function applyFpsCap(v)
	if typeof(v) ~= "number" then
		return
	end
	config.perf.fps = v
	if state.get("NoRender") and setfpscap then
		pcall(setfpscap, v)
	end
end

-- Black screen: a full-viewport veil above everything (Rayfield included).
-- Frames are transparent to input unless Active, so the menu stays clickable
-- underneath even while the screen looks dead.
local blackGui: ScreenGui? = nil

local function setBlackScreen(on: boolean)
	if on then
		if not blackGui then
			local gui = Instance.new("ScreenGui")
			gui.Name = "ParalyzBlackout"
			gui.DisplayOrder = 9999999
			gui.IgnoreGuiInset = true
			gui.ResetOnSpawn = false
			gui.Parent = game:GetService("CoreGui")
			local frame = Instance.new("Frame")
			frame.Name = "Veil"
			frame.Size = UDim2.fromScale(1, 1)
			frame.BackgroundColor3 = Color3.new(0, 0, 0)
			frame.BorderSizePixel = 0
			frame.Parent = gui
			blackGui = gui
		end
		blackGui.Enabled = true
	elseif blackGui then
		blackGui.Enabled = false
	end
end

state.on("AutoFarm", function()
	farm.sync()
end)
state.on("SellAt", applySellAt)
state.on("SwingDelay", applySwingDelay)

state.on("ESPPlayers", function()
	esp.sync()
end)
state.on("ESPMonsters", function()
	esp.sync()
end)
state.on("ESPJuice", function()
	esp.sync()
end)
state.on("ESPRocks", function()
	esp.sync()
end)
state.on("ESPLabels", function()
	esp.sync()
end)

state.on("Noclip", function()
	travel.sync()
end)
state.on("Fly", function()
	travel.sync()
end)
state.on("FlySpeed", applyFlySpeed)

state.on("Avoid", function()
	combat.sync()
end)
state.on("GunRapid", function()
	combat.sync()
end)
state.on("GunVolley", function()
	combat.sync()
end)

state.on("AutoRewards", function()
	rewards.sync()
end)
state.on("BlackScreen", function(value)
	setBlackScreen(value == true)
end)

state.on("NoRender", applyNoRender)
state.on("FpsCap", applyFpsCap)

-- The config sliders may already hold values restored by autoLoad, and their
-- callbacks ran before these subscriptions existed: replay them once.
applySellAt(state.get("SellAt"))
applySwingDelay(state.get("SwingDelay"))
applyFlySpeed(state.get("FlySpeed"))
applyFpsCap(state.get("FpsCap"))
setBlackScreen(state.get("BlackScreen") == true)

-- Hidden mining is the default way to farm (user decision): make it true on
-- every boot unless the user turns it off during the session. Rayfield
-- applies its autoLoad restore AFTER the menu exists, and the saved config
-- still holds a false from the far-teleport debugging session, so the seed
-- above can lose the race - re-assert once after the restore has landed.
state.set("HideMining", true)
task.delay(1.5, function()
	if state.get("HideMining") ~= true then
		state.set("HideMining", true)
	end
end)

-- First sync: everything defaults off, this just primes the modules with the
-- restored state (e.g. no-render was left on last session).
farm.sync()
esp.sync()
travel.sync()
combat.sync()
rewards.sync()
rewards.start()
if state.get("NoRender") == nil then
	state.set("NoRender", true)
else
	applyNoRender(state.get("NoRender"))
end

-------------------------------------------------------------- live stats
task.spawn(function()
	while true do
		if window.unloaded then
			break
		end
		pcall(function()
			if creditsStat then
				creditsStat:Set(util.credits())
			end
			if juiceStat then
				juiceStat:Set(util.juiceValue())
			end
			if farmStat then
				farmStat:Set(farm.isRunning() and farm.stats() or "idle")
			end
			if converterStat then
				local list = util.converters()
				converterStat:Set(#list > 0 and table.concat(list, ", ") or "none built")
			end
			if questStat then
				questStat:Set(rewards.stats())
			end
		end)
		task.wait(2)
	end
end)

------------------------------------------------------------------ shutdown
shutdown = function()
	farm.stop()
	combat.stop()
	esp.stop()
	travel.stop()
	rewards.stop()
	util.stopAim()
	if blackGui then
		pcall(function()
			blackGui:Destroy()
		end)
		blackGui = nil
	end
	if window and not window.unloaded then
		pcall(function()
			window:Unload()
		end)
	end
	if getgenv then
		getgenv().Paralyz = nil
	end
end

if getgenv then
	getgenv().Paralyz = {
		version = VERSION,
		shutdown = shutdown,
		window = window,
		config = config,
		state = state,
		util = util,
		perf = perf,
		esp = esp,
		farm = farm,
		combat = combat,
		travel = travel,
		rewards = rewards,
	}
end

window:Notify({
	title = "Paralyz",
	content = "v" .. VERSION .. " loaded",
	duration = 3,
})

return {
	version = VERSION,
	window = window,
	state = state,
	shutdown = shutdown,
}
