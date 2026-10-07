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

		-- Auto-fix chain, in order, after stallSwings swings with no juice:
		-- 1) re-equip the pickaxe, 2) switch to another rock, 3) settle-wait.
		-- Any juice resets the chain.
		stallSwings = 10,
		rockSwitchDelay = 20,

		-- No rocks anywhere in the world: after this many empty waits the farm
		-- teleports to another planet and lets the rocks stream in there.
		planetWaits = 3,
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
		-- Seconds between swings of the auto-attack.
		swingDelay = 0.45,
		-- How close a monster has to be before we swing at it.
		swingRange = 18,
		-- Keep-distance when Avoid is on: monsters inside this radius trigger a step back.
		avoidRadius = 14,
	},

	travel = {
		-- Fly speed, studs per frame multiplier of the camera direction.
		flySpeed = 2.5,
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

	-- metrics (the menu shows these through farm.stats())
	local cycles = 0 -- swings sent
	local gained = 0 -- juice stacks collected (counted when they land)
	local sold = 0
	local fixes = 0
	local switches = 0
	local lastReport = 0

	-- rocks on cooldown after a stall (rock -> release time)
	local avoided: { [BasePart]: number } = {}
	local lastPlanet: string? = nil

	local function report(msg: string)
		if os.clock() - lastReport > 2 then
			lastReport = os.clock()
			util.notify("Auto-Farm", msg)
		end
	end

	------------------------------------------------------------------ stance
	local function hidden(): boolean
		return state.enabled("HideMining")
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
			if cf then
				local root = util.root()
				if root then
					root.CFrame = cf
				end
			end
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
		for _, rock in ipairs(util.rocks()) do
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

	-- No rocks anywhere: the character is out of stream range or the phase
	-- has none. Move to another planet and let the rocks stream in.
	local function rotatePlanet()
		local root = util.root()
		if not root then
			return
		end
		local scan = util.planetScan()
		if #scan == 0 then
			return
		end
		table.sort(scan, function(a, b)
			return a.rocks > b.rocks
		end)
		-- Prefer a planet that already shows rocks and is not where we just
		-- looked, so repeated rotations keep making progress.
		local target = nil
		for _, p in ipairs(scan) do
			if p.rocks > 0 and p.name ~= lastPlanet then
				target = p
				break
			end
		end
		if not target then
			for _, p in ipairs(scan) do
				if p.name ~= lastPlanet then
					target = p
					break
				end
			end
		end
		target = target or scan[1]
		lastPlanet = target.name
		root.CFrame = CFrame.new(util.dropToSurface(target.centre))
		report("no rocks anywhere - moving to " .. target.name)
		task.wait(1)
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

	------------------------------------------------------------------- loop
	local function runLoop(opts)
		local maxCycles = opts and opts.maxCycles
		local maxJuice = opts and opts.maxJuice

		cycles, gained, sold, fixes, switches = 0, 0, 0, 0, 0
		avoided = {}
		lastPlanet = nil
		local stall = 0 -- swings since the last juice
		local fixStage = 0
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
				task.wait(1)
				continue
			end

			noteJuice()

			-- Sell before the stack fills so the backpack never clogs.
			if util.juiceCount() >= config.farm.sellAt then
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

			local rock = pickRock(root.Position)
			if not rock then
				if #util.rocks() > 0 and releaseOldestAvoided() then
					task.wait(1)
					continue
				end
				emptyWaits += 1
				if emptyWaits >= config.farm.planetWaits then
					emptyWaits = 0
					rotatePlanet()
				end
				task.wait(config.farm.noRockDelay)
				continue
			end
			emptyWaits = 0

			-- Stance: hold it from here on; recomputed whenever we re-enter.
			holdCF = stanceCFrame(rock, root.Position)
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
			-- cursor lands on its surface no matter where we stand.
			local half = math.max(rock.Size.X, rock.Size.Y, rock.Size.Z) / 2
			if not util.aimAt(rock.Position, half + 40) then
				aimFails += 1
				if aimFails % 10 == 0 then
					report("aim cannot find the rock (" .. aimFails .. " tries)")
				end
				task.wait(math.min(0.3 + aimFails * 0.2, 2))
				continue
			end
			aimFails = 0

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

			util.stopAim()

			-- Chain runs only after stallSwings dead swings; juice resets it.
			if running and stall >= config.farm.stallSwings then
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
		running = false
	end

	-- opts: { maxJuice = n, maxCycles = n } for tests. GUI calls farm.start() bare.
	function farm.start(opts)
		if running then
			return false
		end
		running = true
		cycles, gained, sold, fixes, switches = 0, 0, 0, 0, 0
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
			"%d swings · %d juice · %d sold · %d fixes",
			cycles,
			gained,
			sold,
			fixes + switches
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

	-- Where a teleport should land: raycast down from above the point so the
	-- character ends on the surface instead of inside the geometry.
	function util.dropToSurface(pos: Vector3): Vector3
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { util.character() }
		local hit = workspace:Raycast(pos + Vector3.new(0, 600, 0), Vector3.new(0, -1500, 0), params)
		if hit then
			return hit.Position + Vector3.new(0, 5, 0)
		end
		return pos + Vector3.new(0, 10, 0)
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
	-- mining only works when the camera's ray through the mouse really lands on
	-- the rock. This solves a camera CFrame that makes that true, then holds it.
	local AIM_BIND = "ParalyzAim"

	function util.stopAim()
		pcall(function()
			RunService:UnbindFromRenderStep(AIM_BIND)
		end)
	end

	local function solveAimCFrame(targetPos: Vector3, standOff: number): CFrame?
		local cam = workspace.CurrentCamera
		if not cam then
			return nil
		end
		local mouse = LocalPlayer:GetMouse()
		local mousePx = Vector2.new(mouse.X, mouse.Y)

		-- Keep the current side of the target so the view never flips.
		local offset = cam.CFrame.Position - targetPos
		if offset.Magnitude < 1 then
			offset = Vector3.new(0, 1, 0)
		end
		local base = targetPos + offset.Unit * standOff + Vector3.new(0, 3, 0)

		local cf = CFrame.lookAt(base, targetPos)
		for _ = 1, 12 do
			cam.CFrame = cf
			local ray = cam:ViewportPointToRay(mousePx.X, mousePx.Y)
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

	-- Returns true when the camera is locked on and the mouse sees the target.
	-- Accepts either the exact part (any hit on it puts the part's own position
	-- under the cursor, which matches to the millimetre) or a bare position
	-- such as a monster pivot, where a small tolerance is right. Comparing the
	-- instance against the Vector3 - the bug this replaced - is always false.
	function util.aimAt(targetPos: Vector3?, standOff: number?): boolean
		local target = targetPos or (util.root() and util.root().Position)
		if not target then
			return false
		end
		local cf = solveAimCFrame(target, standOff or config.farm.aimDistance)
		if not cf then
			return false
		end
		local cam = workspace.CurrentCamera
		util.stopAim()
		RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 1, function()
			cam.CFrame = cf
		end)
		task.wait() -- let the frame land so Mouse.Target refreshes
		local mt = util.mouseTarget()
		if not mt then
			return false
		end
		return (mt.Position - target).Magnitude <= 12
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
	description = "Stands the character inside the rock where nobody can see it. The server only accepts swings within ~30 studs of a rock, so staying hidden and staying paid are the same spot.",
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
	range = { 0.5, 8 },
	increment = 0.5,
	value = config.travel.flySpeed,
})

-- Combat -----------------------------------------------------------------
ui.section(combatTab, "Fighting")

ui.toggle(combatTab, "AutoSwing", {
	name = "Auto swing",
	description = "Swing the best weapon at the closest monster in range.",
})
ui.toggle(combatTab, "Avoid", {
	name = "Keep distance",
	description = "Step away when a monster gets too close.",
})
ui.toggle(combatTab, "GodMode", {
	name = "Damage guard",
	description = "Blocks damage the client applies itself. Server damage cannot be cancelled from here.",
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

state.on("AutoSwing", function()
	combat.sync()
end)
state.on("Avoid", function()
	combat.sync()
end)
state.on("GodMode", function()
	combat.sync()
end)

state.on("NoRender", applyNoRender)
state.on("FpsCap", applyFpsCap)

-- The config sliders may already hold values restored by autoLoad, and their
-- callbacks ran before these subscriptions existed: replay them once.
applySellAt(state.get("SellAt"))
applySwingDelay(state.get("SwingDelay"))
applyFlySpeed(state.get("FlySpeed"))
applyFpsCap(state.get("FpsCap"))

-- First sync: everything defaults off, this just primes the modules with the
-- restored state (e.g. no-render was left on last session).
farm.sync()
esp.sync()
travel.sync()
combat.sync()
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
	util.stopAim()
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
