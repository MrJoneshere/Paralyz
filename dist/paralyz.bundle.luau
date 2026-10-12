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
		-- Convert threshold: once this many stacks are aboard, the farm
		-- walks them through the ionizer/converter chain. Antimatter is
		-- sold whenever it leads the stack (see util.sellableAnti), so
		-- this no longer gates the sell itself.
		sellAt = 10,
		-- Hold ceiling: with no conversion machines available the farm
		-- keeps stacking plain/ion juice (it is all dumped at round end),
		-- but pauses mining at this many stacks so the backpack can never
		-- clog and dead swings cannot pile up.
		holdCap = 16,
		-- Round length in story seconds (Values.ClientSeconds), measured
		-- from the round-end watcher. 0 = still unknown, which disables
		-- the clock-based dump; the Fim "The End" screen always dumps.
		roundLength = 0,
		-- Dump everything when the clock is within this many seconds of
		-- roundLength (the user's ~30s rule).
		endDumpWindow = 30,
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
		-- Frustum culling ("Lower Usage" toggle): BaseParts the camera
		-- cannot see are skipped by the renderer via
		-- LocalTransparencyModifier. Nothing visible ever changes - no
		-- quality, shadow, lighting or frame-cap touches, by user order.
		cullNearDist = 150, -- inside this: always rendered (no pop-in)
		cullMaxSize = 120, -- bigger than this: never touched (planets)
		cullMarginDeg = 10, -- frustum border absorbing fast camera moves
		cullBudget = 250, -- parts tested per slice (optimizer stays cheap)
		cullSliceSecs = 0.12, -- seconds between slices (fast re-show on turns)
		cullRefreshSecs = 8, -- tracked-part list rebuild interval
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
			setPhase("loading " .. target.label)
			report("moving to " .. target.label .. " - going there to load it", true)
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
				setPhase("loaded " .. target.label)
				report(target.label .. " loaded in person: " .. n .. " rocks", true)
				return true
			end
			planetCool[target.name] = os.clock() + config.farm.planetCooldown
			report(target.label .. ": went there, waited, empty for now - trying another planet", true)
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

	-- Plain juice is only worth mining while an ionizer can walk it to ion
	-- (15 -> 20) and the converter finishes the trip to 74. Same hold
	-- protocol as convertIon: one verified hold per stack, and a hold that
	-- consumes nothing aborts the pass instead of looping on a machine
	-- that is only pretending. The ionizer is phase/buy gated (a planet
	-- gets one when its colony is built), so the prompt resolves fresh on
	-- every call.
	local function ionizePlain(): number
		local prompt = util.ionizerPrompt()
		if not prompt then
			return 0
		end
		local holder = prompt.Parent
		local well = if holder and (holder :: Instance):IsA("BasePart")
			then (holder :: BasePart)
			else if holder then (holder :: any):FindFirstChildWhichIsA("BasePart", true) else nil
		if not well then
			return 0
		end
		setPhase("ionizing plain juice")
		rotateTeleport(CFrame.new(well.Position + Vector3.new(0, 3, 0)))
		task.wait(0.6)
		local ionized = 0
		for _ = 1, math.min(util.plainJuiceCount(), 20) do
			local before = util.plainJuiceCount()
			if before <= 0 then
				break
			end
			pcall(function()
				prompt:InputHoldBegin()
				task.wait((prompt :: ProximityPrompt).HoldDuration + 0.6)
				prompt:InputHoldEnd()
			end)
			task.wait(0.8)
			local after = util.plainJuiceCount()
			if after < before then
				ionized += before - after
			else
				report("ionizer rejected the hold - moving on", true)
				break
			end
		end
		if ionized > 0 then
			report(string.format("ionized %d plain stacks", ionized), true)
		end
		return ionized
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

			-- Sell policy (user's rule): never sell plain/ion juice - it is
			-- held for the conversion machines. Antimatter sells whenever it
			-- leads the stack (the server sells oldest-first - measured in
			-- job "sell-order" - so only the leading run can be sold without
			-- touching a held stack). If the round is about to restart,
			-- everything is dumped before the reset takes it.
			local juiceNow = util.juiceCount()
			if juiceNow > 0 and util.roundEndSoon() then
				local count = util.sellAll()
				if count > 0 then
					sold += count
					report(string.format("round ending - dumped %d stacks (total %d)", count, sold), true)
				end
				lastJuice = util.juiceCount()
				task.wait(0.4)
				continue
			end

			local lead = util.sellableAnti()
			if lead > 0 then
				local count = util.sellAnti()
				if count > 0 then
					sold += count
					report(string.format("sold %d anti-matter (total %d)", count, sold))
				end
				lastJuice = util.juiceCount()
				task.wait(0.3)
				continue
			end

			-- Convert threshold: walk the held stack through both machines
			-- (plain -> ion -> anti), then the anti leads and step 2 sells it.
			if juiceNow >= config.farm.sellAt then
				local converted = 0
				if state.enabled("AutoConvert") then
					if util.plainJuiceCount() > 0 and util.ionizerPrompt() then
						converted += ionizePlain()
					end
					-- Prompt gate: without it convertIon would re-announce
					-- "no converter machine" on every hold pass below the
					-- cap (the old code only ever ran once per threshold
					-- because it sold straight after).
					if util.ionJuiceCount() > 0 and util.converterPrompt() then
						converted += convertIon()
					end
				end
				if converted > 0 then
					lastJuice = util.juiceCount()
					task.wait(0.4)
					continue
				end
				-- Nothing is convertible: keep stacking below the cap (it
				-- all dumps at round end anyway) and pause mining at the cap
				-- so the backpack can never clog.
				if juiceNow >= config.farm.holdCap then
					setPhase(string.format("holding %d stacks - no conversion machine available", juiceNow))
					task.wait(1.5)
					continue
				end
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
						"checking " .. preferred.label .. " (best income) before settling here",
						true
					)
					rotateTeleport(CFrame.new(util.dropToSurface(preferred.centre)))
					setPhase("loading " .. preferred.label)
					task.wait(1)
					local n = util.settleRocks(
						preferred.centre,
						config.farm.loadWait,
						config.farm.streamRadius
					)
					if n > 0 then
						rotateTeleport(CFrame.new(util.dropToSurface(preferred.centre)))
						setPhase("loaded " .. preferred.label)
						report(preferred.label .. " has " .. n .. " rocks - mining the ion field", true)
					else
						planetCool[preferred.name] = os.clock() + config.farm.planetCooldown
						report(preferred.label .. " is empty right now - staying local", true)
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
				-- Yield to the loop only when something must happen: the
				-- hold cap, or a pending dump/sell/convert. A hold below
				-- the cap keeps swinging - that juice is value waiting for
				-- the machines and the round-end dump.
				if util.juiceCount() >= config.farm.holdCap then
					break
				end
				if util.sellActionPending() then
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
	["flystand"] = [==[
--!strict
-- Paralyz / src/flystand.luau
-- Upright character while flying (user request 2026-10-12):
-- "when i fly my character starts to spin... make sure it stands like
-- normal even when flying".
--
-- Diagnosis (live probe during the complaint):
--   * Humanoid was in Enum.HumanoidStateType.Physics with a tipped-over
--     HRP orientation (-49, -164, -105) - the ragdoll/physics state.
--   * In Physics state the rig has no motor control: no walk animation,
--     AutoRotate does nothing, and leftover angular momentum makes the
--     character tumble/spin forever.
--   * The game itself has NO character-fly implementation (the Events.Fly
--     remote has zero client callers) - the user flies via their own
--     hub (IY), which never restores the humanoid state afterwards.
--
-- Fix: an always-on 0.1s watchdog - while alive and unseated, leave
-- Physics/PlatformStand via ChangeState(GettingUp) (character snaps
-- upright, animations resume, AutoRotate faces movement again), and
-- damp any rotational momentum (RotVelocity > 1 rad/s -> scaled down).
-- Ground walking never trips it: a standing character is never in
-- Physics state and its RotVelocity is ~0. Silent - no toast, no keybind.

return function(deps)
	local util = deps.util

	local flystand = {}

	local Players = game:GetService("Players")

	local running = false
	local CHECK = 0.1

	local function watch()
		while running do
			task.wait(CHECK)
			if not running then
				break
			end
			local ok, err = pcall(function()
				local char = Players.LocalPlayer.Character
				if not char then
					return
				end
				local hum = char:FindFirstChildOfClass("Humanoid")
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if not (hum and hrp) or hum.Health <= 0 or hum.SeatPart then
					return
				end
				local state = hum:GetState()
				if state == Enum.HumanoidStateType.Physics or hum.PlatformStand then
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
				local rv = hrp.RotVelocity
				if rv.Magnitude > 1 then
					hrp.RotVelocity = rv * 0.15
				end
			end)
			if not ok then
				warn("[Paralyz] flystand error: " .. tostring(err))
			end
		end
	end

	function flystand.start()
		if running then
			return
		end
		running = true
		task.spawn(watch)
	end

	function flystand.stop()
		running = false
	end

	function flystand.isRunning(): boolean
		return running
	end

	return flystand
end
]==],
	["holdmine"] = [==[
--!strict
-- Paralyz / src/holdmine.luau
-- Hidden hold-to-mine (user decision 2026-10-09): always on, no GUI control.
--
-- The game debounces rapid manual left clicks, so spamming does nothing.
-- This listens for a REAL MouseButton1 press and keeps firing Tool:Activate()
-- on the equipped pickaxe until the button is released - the exact call the
-- auto-farm uses, at the farm's proven swing-clamp floor (0.15s). The user
-- aims normally with their camera; only the click spam is automated.
--
-- Rules:
--   * Pickaxes only (name contains "pickaxe", same test as util.bestPickaxe).
--   * Clicks consumed by GUIs are skipped (gameProcessed) - clicking menu
--     buttons never swings.
--   * The loop dies on release, on focus loss (IsMouseButtonPressed goes
--     false) and on unload, so it can never keep swinging on its own.

return function(deps)
	local util = deps.util

	local holdmine = {}

	local CADENCE = 0.15 -- seconds between Activate calls while holding

	local UIS = game:GetService("UserInputService")
	local holding = false
	local started = false
	local beganConn: RBXScriptConnection? = nil
	local endedConn: RBXScriptConnection? = nil

	local function isPickaxe(tool: Tool): boolean
		return string.find(string.lower(tool.Name), "pickaxe", 1, true) ~= nil
	end

	-- Fires while the button is physically held; swings only when a pickaxe
	-- is equipped, so a tool switch mid-hold simply pauses the mining.
	local function swingLoop()
		while holding and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
			local tool = util.equippedTool()
			if tool and isPickaxe(tool) then
				pcall(function()
					tool:Activate()
				end)
			end
			task.wait(CADENCE)
		end
		holding = false
	end

	function holdmine.start()
		if started then
			return
		end
		started = true
		beganConn = UIS.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or holding then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				holding = true
				task.spawn(swingLoop)
			end
		end)
		endedConn = UIS.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				holding = false
			end
		end)
	end

	function holdmine.stop()
		holding = false
		if beganConn then
			beganConn:Disconnect()
			beganConn = nil
		end
		if endedConn then
			endedConn:Disconnect()
			endedConn = nil
		end
		started = false
	end

	function holdmine.isHolding(): boolean
		return holding
	end

	return holdmine
end
]==],
	["hover"] = [==[
--!strict
-- Paralyz / src/hover.luau
-- F6 hover hold (user request 2026-10-12): "while flying when i stop it
-- doesnt just stop it falls very slowly" - freeze in place mid-air on
-- demand.
--
-- Mechanic: on toggle, parent a BodyVelocity named ParalyzHover to the
-- HumanoidRootPart - velocity (0,0,0) on all axes, MaxForce 1e6, P 1e4.
-- That fully cancels gravity and momentum (their fly has no hold force
-- when idle, so the character used to sink). Toggle off destroys it and
-- normal physics resume exactly where you hang. Works with any flight:
-- their hub's fly, the game's ship, or plain jumping off an asteroid.
--
-- Hidden keybind + toast, like F7/F8. F6 chosen because F9 opens the
-- Roblox dev console. Skipped while seated (never fights a vehicle
-- weld); auto-releases on respawn/character swap. stop() on unload
-- always destroys the force.

return function(deps)
	local util = deps.util

	local hover = {}

	local KEY = Enum.KeyCode.F6

	local UIS = game:GetService("UserInputService")
	local Players = game:GetService("Players")

	local listening = false
	local hovering = false
	local conn: RBXScriptConnection? = nil
	local charConn: RBXScriptConnection? = nil
	local bv: BodyVelocity? = nil

	local function release()
		if bv then
			pcall(function()
				bv:Destroy()
			end)
			bv = nil
		end
	end

	-- Returns false when the character can't hover (seated / missing).
	local function apply(): boolean
		local char = Players.LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum) or hum.Health <= 0 or hum.SeatPart then
			return false
		end
		local v = Instance.new("BodyVelocity")
		v.Name = "ParalyzHover"
		v.Velocity = Vector3.zero
		v.MaxForce = Vector3.new(1000000, 1000000, 1000000)
		v.P = 10000
		v.Parent = hrp
		bv = v
		return true
	end

	local function toggle()
		if hovering then
			hovering = false
			release()
		else
			if not apply() then
				if util and util.notify then
					util.notify("Hover", "can't hover right now (seated or no character)")
				end
				return
			end
			hovering = true
		end
		if util and util.notify then
			util.notify("Hover", hovering and "ON - frozen in place, F6 to release" or "OFF")
		end
	end

	function hover.start()
		if listening then
			return
		end
		listening = true
		-- Not gated on gameProcessed (same lesson as F7/F8): only a
		-- focused text box blocks the key.
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
			if hovering then
				hovering = false
				release()
			end
		end)
	end

	function hover.stop()
		hovering = false
		listening = false
		release()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if charConn then
			charConn:Disconnect()
			charConn = nil
		end
	end

	function hover.isRunning(): boolean
		return listening
	end

	function hover.isHovering(): boolean
		return hovering
	end

	return hover
end
]==],
	["instantprompts"] = [==[
--!strict
-- Paralyz / src/instantprompts.luau
-- Instant proximity prompts - a direct port of Infinite Yield's ;instantpp.
--
-- IY does NOT zero HoldDuration. Its trick: connect
-- ProximityPromptService.PromptButtonHoldBegan and call the executor builtin
-- fireproximityprompt() the moment the player BEGINS holding a prompt, so the
-- hold never has to finish. uninstantpp disconnects; this module exposes the
-- same thing as start/stop behind the Settings -> Instant Prompts toggle.
--
-- Notes:
--   * fireproximityprompt is a Real builtin (confirmed via search-api).
--   * The connection callback is pcall-wrapped so a bad prompt can never kill
--     the connection or spam errors.
--   * start() is idempotent (conn guard), stop() disconnects cleanly - same
--     reconnect-first shape as IY's execCmd("uninstantproximityprompts").

return function(deps)
	local util = deps.util

	local instantprompts = {}

	local PPS = game:GetService("ProximityPromptService")
	local conn: RBXScriptConnection? = nil

	local function fire(prompt: ProximityPrompt)
		pcall(fireproximityprompt, prompt)
	end

	function instantprompts.start()
		if conn then
			return
		end
		if type(fireproximityprompt) ~= "function" then
			if util and util.notify then
				util.notify("Instant Prompts", "this executor has no fireproximityprompt")
			end
			return
		end
		conn = PPS.PromptButtonHoldBegan:Connect(fire)
	end

	function instantprompts.stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	function instantprompts.isRunning(): boolean
		return conn ~= nil
	end

	return instantprompts
end
]==],
	["knowledge"] = [==[
--!strict
-- Paralyz / src/knowledge.luau
-- The Assistant tab's knowledge base: wiki facts + live measurements,
-- distilled from the local KNOWLEDGE.md (the source stays off-repo).
--
-- Structure: flat entry list, each entry self-contained so any single one
-- can be shown in the answer card. Search is a scored substring match over
-- title/keys/body - no dependencies, works offline inside the bundle.

local entries = {
	----------------------------------------------------------- basics
	{
		id = "juice-variants",
		cat = "Basics",
		title = "Juice: the 5 variants",
		keys = "moon juice variants plain ionized antimatter methanized omega",
		body = "Moon Juice is the main currency (Credits is the other). Plain: Moon, Mars, Venus, "
			.. "Charon, Phobos, Deimos, Ganymede rocks. Ionized: Mercury rocks right away, or ionize "
			.. "plain at the Pluto Colony. Antimatter: Space Station converter. Methanized: Titan. "
			.. "Omega: Omega Smelter (Pluto from Kuiper, Earth from Andromeda).",
	},
	{
		id = "juice-worth",
		cat = "Basics",
		title = "Juice: what a mined item is worth",
		keys = "sell value credits fuel worth 20",
		body = "A mined juice item converts to 20L / 10 Fuel / 5 Credits at shops. Measured live "
			.. "2026-10-08: selling the TOOL pays 20 cr for Ionized and 34 cr for Anti Matter. "
			.. "Wiki exchange: 1 Moon Juice -> 5 Credits at the Earth shop.",
	},
	{
		id = "juice-chain",
		cat = "Basics",
		title = "Juice: conversion chain",
		keys = "convert chain ionizer anti matter plain to ion 1:1 machine",
		body = "Plain -> ionized at the Pluto Colony ionizer (1:1, comes with Pluto Colony 300). "
			.. "Ionized -> antimatter at the Space Station converter (500, global pool). Dec 2025: "
			.. "converters no longer require holding an item in - a 2s proximity hold still works "
			.. "(hub measured). Antimatter pays best: 34 cr per stack.",
	},
	{
		id = "juice-passive",
		cat = "Basics",
		title = "Juice: passive producers",
		keys = "pumper pumpjack passive oil tank income per second",
		body = "Buy once per round, they run forever: Moon Juice Pumper 200L (Earth, 2L/s), "
			.. "Pumpjack 375L (1 tank/20-20-20 per min), Ionized Pumper 800L (Venus, 4L/s Venus, "
			.. "2L/s Earth, 1L/s Mars), Mercury Pumpjack 850L (ion tank per min), Omega Pumper 300L. "
			.. "Round restart wipes buildings - pools reset and you re-buy next round.",
	},
	{
		id = "currencies",
		cat = "Basics",
		title = "Currencies & exchange",
		keys = "currency exchange credits moon juice 5 shop",
		body = "Two currencies: Moon Juice and Credits. Exchange: 1 Moon Juice -> 5 Credits at the "
			.. "Earth shop (wiki). Mined juice TOOLS sell for more (Ionized 20 cr, Anti 34 cr "
			.. "measured). Credits persist across round restarts; the carried juice stack does not.",
	},

	----------------------------------------------------------- prices
	{
		id = "shop-earth",
		cat = "Prices",
		title = "Prices: Earth shop",
		keys = "earth shop prices moon gun space station nuke rebuild city",
		body = "Moon Gun 10, Moon Saber 20, Umbra Zone 100, Pumper 200, Demolish Debris 250, "
			.. "Pumpjack 375, Mars Colony 350, Item's Shop 450, Venus Colony 300, Space Station 500, "
			.. "Nuclear Plants 400, Rebuild City 1000, Nuke 200, Anti Matter Nuke 300, Pluck Radar 400, "
			.. "Forcefield 500, Recover Earth 1200, Omega Nuke/Pumper 300, Omega Smelter 350, "
			.. "Collosal Moondrive 2000, FRIEND Moon 1500, Pulsar Forcefield 500 / Laser 1000.",
	},
	{
		id = "shop-venus",
		cat = "Prices",
		title = "Prices: Venus shop",
		keys = "venus shop prices sky bases terraform dyson stargoose mercury colony",
		body = "Moon Gun 10, Moon Saber 20, Sky Bases 500 -> 300 (pre-Vercury), Ionized Pumper 800, "
			.. "Demolish Debris 500 (only when Mercury crashes into Venus), Surface Colony 500, "
			.. "Venusian City 1000, Stargoose Spawner 600, Forcefield 500, Terraform Venus 1500. "
			.. "After Mercury x Iapetus: Mercury Colony 300, Cool Mercury 700, Mercury Pumpjack 850, "
			.. "Terraform Mercury 1500. After Neptune: Dyson Sphere 600.",
	},
	{
		id = "shop-mars",
		cat = "Prices",
		title = "Prices: Mars shop",
		keys = "mars shop prices pluto colony phobos terraform domes",
		body = "Moon Gun 10, Moon Saber 20, Mars Domes 400, Main Colony 700, Terraform Mars 1000 "
			.. "(blocks Project Phobos), Pluto Colony 300 (brings the ionized converter). "
			.. "After Pluto colony: Expand Pluto Colony 500, Terraform Pluto 800 (Pluto never wakes). "
			.. "After Neptune: Project Phobos 500.",
	},
	{
		id = "shop-credits",
		cat = "Prices",
		title = "Prices: Credits shop",
		keys = "credits shop pickaxe sword railgun rocket vip spaceship moondrive",
		body = "Electric Sword 100, Iron Pickaxe 110, Super Sword 300, Metal Pickaxe 325, "
			.. "Railgun 500, Diamond Pickaxe 1000, Rocket Launcher 1500, VIP spaceship 6000, "
			.. "Moondrive 70 (reaches Kuiper, Proxima, Sirius). Gamepasses: Speed Coil 40 R$, "
			.. "Omega Pickaxe 19 R$ - both also obtainable in-game or via dailies.",
	},
	{
		id = "shop-pluto",
		cat = "Prices",
		title = "Prices: Pluto / Kuiper shop",
		keys = "pluto kuiper shop raygun laser omega smelter hyper station prices",
		body = "At the Pluto colony: Moon Gun 10, Moon Saber 20, Moonjuice Pumper Jack 200, "
			.. "Raygun 400 (GUI shows 350, actually 400), Laser 400 (destroy Neptune or WISE 0855), "
			.. "Omega Smelter 500, Omega Laser 500 (kill SIMP0136), Kuiper Space Station 1000 "
			.. "(kill PSO J318 + red giant Betelgeuse), Hyper Laser 600 (kill Betelgeuse).",
	},
	{
		id = "shop-veylora",
		cat = "Prices",
		title = "Prices: Veylora (Andromeda)",
		keys = "veylora andromeda shop dyson duo laser terraform power plants",
		body = "Power Plants 400, Terraform 1000, Dyson Sphere 1000 (starts the Sirius -> Earth "
			.. "event), Duo Laser 700 (destroys Sirius + Sirius Black Hole). Omega nukes live here: "
			.. "Omega Nuke and Omega Pumper 300, Omega Smelter 350.",
	},
	{
		id = "shop-no-shops",
		cat = "Prices",
		title = "Where Mercury & Pluto buy things",
		keys = "mercury pluto no shops venus mars buy upgrades",
		body = "Mercury and Pluto have NO shops of their own - every upgrade for them is bought "
			.. "from the Venus or Mars shop (wiki). Mercury Colony 300 and Terraform Mercury 1500 "
			.. "are on Venus; Pluto Colony 300 and Expand 500 are on Mars.",
	},

	----------------------------------------------------------- endings
	{
		id = "endings-solar-1",
		cat = "Endings",
		title = "Endings: Solar System (1/2)",
		keys = "ending solar survive moon impact nuke gas giants jupiter phobos mars time travel",
		body = "Survive The Moon Impact - Nuke The Moon - Gas Giants Arrival - Sun Wakes Up - "
			.. "Red Giant Sun - Neptune Arrival - Time Travel (forcefield around Ganymede + Time "
			.. "Machine within ~20 min: Theia hits Earth) - Jupiter Ending (Io mishandled: Jupiter "
			.. "eats Earth) - Nuke Jupiter's Moon - Project Phobos - Awakened Mars Ending - "
			.. "Mars Ending (colonize, Jupiter eats Earth).",
	},
	{
		id = "endings-solar-2",
		cat = "Endings",
		title = "Endings: Solar System (2/2)",
		keys = "ending anti matter nuke moons crash interstellar neptune planet x pluto black hole",
		body = "Antimatter Nuke (destroy Neptune) - The Moons Crash - Interstellar (Moon Drive -> "
			.. "Proxima or Sirius) - Enraged Neptune (let it eat Earth) - Neptune's Bodyguard "
			.. "(destroy Triton) - Earth Awakens - Planet X ending (let it eat Earth) - Planet X "
			.. "destroyed (Space Station laser, NOT the nuke) - Pluto Awakens - Black Hole wakes Up "
			.. "(Dyson spheres + Moondrives -> explode Sun -> laser Earth -> kill Black Hole).",
	},
	{
		id = "endings-proxima-kuiper",
		cat = "Endings",
		title = "Endings: Proxima & Kuiper",
		keys = "ending proxima centauri kuiper freedom colonized warrior savior liberator",
		body = "Proxima: Proxima System - Alpha Centauri Collision (upgrade B fully -> C crashes "
			.. "into B) - Alpha Centauri Dead. Kuiper: Freedom! - Colonized - Diplomatic / Enemies "
			.. "Forever - Neptune Ending 2 - Laser - Traitor - Wise 0855 - Liberator - United Kuiper "
			.. "Belt - Savior - Warrior (kill Wise as it eats Pluto - hardest) - SIMP0136 - PSO J318 "
			.. "- Good Kuiper - Betelgeuse / star exterminator.",
	},
	{
		id = "endings-sirius-gorlon",
		cat = "Endings",
		title = "Endings: Sirius & Gorlon",
		keys = "ending sirius gorlon andromeda meltdown freezedown core worker true pulsar",
		body = "Sirius: Artificial Swarm (both Dyson spheres) - Core Activation - Meltdown "
			.. "(black hole >100M C: do NOT unawaken) - Freezedown (<0 C: spam Super Freeze Beam) "
			.. "- Core Worker (1h) - Elite Core Worker (2h). Gorlon/Andromeda: Andromeda - Omega "
			.. "nuke - Lasered - Brown Dwarf - Lord of the Rings - True ending (Pulsar destroys "
			.. "Earth without Forcefield) - Pulsar - Second true (destroy Gorlon) - Sirius - Black "
			.. "Hole - Undefeatable.",
	},

	----------------------------------------------------------- awaken
	{
		id = "awaken-solar",
		cat = "Awaken",
		title = "Awaken: Solar System",
		keys = "awaken sun mercury venus moon mars jupiter saturn neptune conditions",
		body = "Sun: awake from game start (Red Giant when the Mercury-colony laser fires, then "
			.. "explodes). Mercury: after Saturn releases Iapetus toward Venus (needs Venus Colony). "
			.. "Venus: just before Mercury x Iapetus, sleeps after. Moon: 15-min impact timer. "
			.. "Mars: Project Phobos. Jupiter/Saturn/Uranus: after Moon impact. Neptune: after "
			.. "Taxman plucks the gas giants (Proteus is private-server only).",
	},
	{
		id = "awaken-kuiper",
		cat = "Awaken",
		title = "Awaken: Kuiper Belt",
		keys = "awaken pluto charon planet x wise simp pso betelgeuse dwarf planets",
		body = "Pluto: wakes after Charon crashes (post-colony), heads to Mars; nukeable; "
			.. "terraforming PREVENTS awakening. Charon: always awake. Planet X: Space Station "
			.. "exists AND Callisto nuked AND enraged Neptune destroyed. WISE 0855-0714: appears "
			.. "once the Sun starts moving. SIMP 0136: after WISE (Omega Laser). PSO J318: cooks "
			.. "Pluto, Kuiper Space Station laser saves. Betelgeuse: 10-minute window after PSO.",
	},
	{
		id = "awaken-beyond",
		cat = "Awaken",
		title = "Awaken: beyond & Andromeda",
		keys = "awaken proxima sirius black hole sagittarius gorlon pulsar brown dwarf thalaan",
		body = "Proxima C: its moon collides with B (building level 5 on Proxima B). Sirius A/B: "
			.. "stare at Earth after Andromeda - Duo Laser on Veylora kills them; Sirius B first "
			.. "flings itself into Sagittarius A. Black Hole Core: both Sirius stars dead -> "
			.. "expands. Sagittarius A*: 5 minutes to antimatter-laser it after the warp. Thalaan: "
			.. "wakes shortly after landing. Gorlon trio: outer gas giants moving at Earth. Brown "
			.. "Dwarf: after the trio (3 Omega Nukes). Pulsar: after Brown Dwarf.",
	},

	----------------------------------------------------------- story
	{
		id = "story-moon",
		cat = "Story & Planets",
		title = "Story: the Moon",
		keys = "moon crash 15 minutes monsters boss patricia infection bunker",
		body = "The Moon awakens first and needs 15 minutes to hit Earth: volcano, tsunami, "
			.. "MoonInfection, falling satellites, earthquakes. Spawns MoonInfected + Moon Monster "
			.. "every 40-50s; Moon Boss only with >=10 players. Nuke it (fuel found on Mars) for "
			.. "the good path - if nuked, Patricia returns and builds a second Moon that ALWAYS "
			.. "crashes into Earth.",
	},
	{
		id = "story-sequence-1",
		cat = "Story & Planets",
		title = "Full sequence: steps 1-4",
		keys = "story order sequence moon jupiter gas giants neptune planet x earth awakens",
		body = "1) Moon awakens -> humanity nukes it -> Patricia's second Moon crashes into Earth. "
			.. "2) Jupiter/Saturn/Uranus arrive -> nuke Callisto -> Io+Rhea+Oberon launched -> nuke "
			.. "all 3 -> Jupiter eats Earth -> Pluck Radar plucks the gas giants. 3) Neptune arrives "
			.. "-> Proteus + Triton -> antimatter nuke x2 destroys it. 4) Planet X arrives, shoots "
			.. "Moon Juice -> Earth awakens -> Space Station laser destroys Planet X -> Forcefield "
			.. "puts Earth back to sleep.",
	},
	{
		id = "story-sequence-2",
		cat = "Story & Planets",
		title = "Full sequence: steps 5-9",
		keys = "story order dyson sphere sun andromeda omega pulsar sirius black hole veylora",
		body = "5) FRIEND lasers Phobos -> Mars awakens & heads to Earth -> antimatter nuke. "
			.. "6) Dyson Sphere -> Sun angry, moves toward Earth -> Mercury laser turns it red "
			.. "giant -> explodes -> Colossal Moondrives warp Earth -> Sagittarius A* -> antimatter "
			.. "laser -> Andromeda (Gorlon). 7) Galius/Kalius/Ralius -> Omega Nuke x3 -> Brown Dwarf "
			.. "-> nuke x3. 8) Pulsar -> upgraded forcefield survives -> antimatter laser. "
			.. "9) Sirius A/B + Black Hole Core -> Duo Laser on Veylora.",
	},
	{
		id = "planet-venus",
		cat = "Story & Planets",
		title = "Planets: Venus",
		keys = "venus terraform foggy mercury collision sky bases planet3",
		body = "Terraformable, no satellites, between Mercury and Earth. Wakes before Mercury x "
			.. "Iapetus then falls asleep again. If Venus Colony is bought before the gas giants "
			.. "arrive, Mercury can collide with Venus (sky bases destroyed, Friend shop lands). "
			.. "Venus, Mercury and Iapetus never collide with Earth. Surface vision is foggy "
			.. "orange-brown.",
	},
	{
		id = "planet-mars",
		cat = "Story & Planets",
		title = "Planets: Mars",
		keys = "mars phobos deimos awaken project colony planet4 plain juice",
		body = "Satellites Phobos + Deimos (mineable for plain juice). Wakes via Project Phobos "
			.. "(bought on the Mars shop; auto after Planet X destroyed / Dyson Sphere built / "
			.. "Neptune leaves). Awakened Mars heads to Earth - a few minutes of control before it "
			.. "crashes (Awakened Mars Ending). Destroyed by anti-matter nuke -> Dyson Sphere then "
			.. "builds around the Sun. 'Mars has the most awaken versions.'",
	},
	{
		id = "planet-mercury",
		cat = "Story & Planets",
		title = "Planets: Mercury",
		keys = "mercury ionized lava terraform laser red giant planet5 best mining",
		body = "Terraformable, no satellites. Wakes to collide with Venus; Iapetus intercepts -> "
			.. "lava world (or lands on Venus if Venus Colony exists). MINING MERCURY GIVES "
			.. "IONIZED JUICE DIRECTLY - best raw income with no machine needed. Mercury Colony's "
			.. "laser turns the Sun into a red giant (which then explodes).",
	},
	{
		id = "planet-pluto",
		cat = "Story & Planets",
		title = "Planets: Pluto",
		keys = "pluto charon terraform kuiper awaken planet6 colony lava",
		body = "Satellite Charon (always awake; crashes into Pluto after the colony is built - "
			.. "harmless to the colony). If colony built and never terraformed -> awakens, heads to "
			.. "Mars, collision destroys the Mars colony. Terraformed beforehand -> NEVER awakens. "
			.. "Nuke destroys it (explains a completely empty Pluto mid-round). Kuiper path: colony "
			.. "-> expand -> terraform -> FRIEND war -> dwarfs -> Planet X -> ... -> Betelgeuse.",
	},
	{
		id = "planet-earth",
		cat = "Story & Planets",
		title = "Planets: Earth",
		keys = "earth awaken planet x satellite states pangea ice age planet1",
		body = "Between Venus and Mars, one satellite (the Moon), normally cannot awaken. Awakens "
			.. "after Planet X fires Moon Juice into its core; Forcefield puts it back to sleep; "
			.. "stays stationary until destroyed or forced asleep. Visual states: Asleep/Frozen/"
			.. "Lava/Warm/Recovered, Proto Earth, Pangea, Ice Age. Jupiter eats it if the Callisto "
			.. "/Io/Rhea/Oberon chain is mishandled.",
	},

	----------------------------------------------------------- progression
	{
		id = "daily-rewards",
		cat = "Progression",
		title = "Daily rewards",
		keys = "daily reward streak 200 seconds credits rocket launcher pickaxe",
		body = "No streak -> wait 200 seconds, then the daily popup appears. Days: Moon Saber, "
			.. "Iron Pickaxe, Speed Coil, 300 credits, Diamond Pickaxe, Rail Gun, Rocket Launcher. "
			.. "Streak >7 days = 400 credits daily. Miss a day -> lose everything EXCEPT the Rocket "
			.. "Launcher if day 7 was reached. Wiki pages disagree on day 1 vs 2 - verify live.",
	},
	{
		id = "nuke-targets",
		cat = "Progression",
		title = "Nuke targets",
		keys = "nuke anti matter destroy moon pluto mars neptune callisto io rhea oberon",
		body = "Nuke (200): destroys Moon, Pluto, Callisto, Io, Rhea, Oberon. Anti Matter Nuke "
			.. "(300): destroys Mars and enraged Neptune (Triton tanks the first hit). Nuke, Moon "
			.. "Gun and Moon Saber can be bought multiple times. Nuking the Moon = the good path; "
			.. "anti-nuking Mars triggers the Dyson Sphere build.",
	},
	{
		id = "key-builds",
		cat = "Progression",
		title = "Key builds (what unlocks what)",
		keys = "build order venus colony pluto colony space station ionizer unlocks chain",
		body = "Venus Colony 300 unlocks the Mercury chain (Iapetus, Mercury Colony laser). "
			.. "Pluto Colony 300 (Mars shop) brings the IONIZER (plain -> ion). Space Station 500 "
			.. "(global pool) brings the ANTI-matter converter + laser. Mars Colony 350 and Main "
			.. "Colony 700 progress the Mars story. Mercury/Pluto have no shops - buy their stuff "
			.. "from Venus/Mars.",
	},
	{
		id = "round-rules",
		cat = "Progression",
		title = "How a round works",
		keys = "round restart wipes pools fuel credits buildings length fim",
		body = "Live measured: a round restart wipes pools, Fuel, bought buildings and the carried "
			.. "juice stack - CREDITS STAY. Round length varies (measured 2211-3527 seconds, never "
			.. "constant). The Fim overlay plus a frozen story clock mark the end. Dump your juice "
			.. "before the reset - the hub does this automatically.",
	},
	{
		id = "pools",
		cat = "Progression",
		title = "Building pools (how buys work)",
		keys = "pool buy global venus mars fills reset fire server space station",
		body = "Buildings are bought from POOLS (global, Venus, Mars), not personal credits - "
			.. "pools fill as players mine and sell, and reset each round. Rejected buys cost "
			.. "nothing. Measured: SpaceStation global 500, PlutoColony mars 300, Ionized Pumper "
			.. "venus 800, Main Colony mars 700, Venus Sky Bases venus 500->300.",
	},

	----------------------------------------------------------- tips
	{
		id = "tips-income",
		cat = "Tips",
		title = "Best income math",
		keys = "income best mining credits per swing ion mercury moon value",
		body = "Measured: ion conversion pays ~2.5 cr/swing vs the Moon's plain 1.25. Raw ion "
			.. "sells at 20 cr/stack = 0.67/swing, BELOW plain. So run the converter chain: mine "
			.. "where plain -> ion -> anti can complete (Pluto ionizer + Space Station). Mercury "
			.. "surface gives ionized juice straight away when no chain is available.",
	},
	{
		id = "tips-survival",
		cat = "Tips",
		title = "Survival tips",
		keys = "tips survive monsters moon infected bunker gas giants eat ships",
		body = "Moon impact at ~15 min: monsters spawn every 40-50s, Moon Boss only at >=10 "
			.. "players. Eating juice makes you MoonInfected. Items save after death EXCEPT fuels "
			.. "and Moon Juice. Bunker door wait: 100s (was 200). Gas giants eat players who fly "
			.. "too close to Callisto/Titan/Ariel/Oberon; Neptune eats spaceships.",
	},
	{
		id = "tips-machines",
		cat = "Tips",
		title = "Where the machines live",
		keys = "converter hierarchy insert moonjuice hold prompt ionizer station industries",
		body = "Hub-measured: anti converter = <planet>.SpaceStation.ConverterMachine.PartProximity"
			.. " 'Insert Moonjuice' (hold 2s, dist 10); ionizer = same names under a *Industries "
			.. "folder (Pluto's is Planet6.Center.PlutoIndustries). Pumpers are passive - no "
			.. "prompt. Converters no longer need holding since Dec 2025; the hold still works.",
	},
	{
		id = "tips-pickaxes",
		cat = "Tips",
		title = "Pickaxes & weapons",
		keys = "pickaxe iron metal diamond omega best sword saber railgun",
		body = "Credits shop pickaxes: Iron 110, Metal 325, Diamond 1000. Rank order (hub): "
			.. "Op > Omega > Diamond > Metal > Iron > plain. Omega Pickaxe: 1% chance when "
			.. "smelting plain juice in an Omega Smelter (99% = Omega Moon Juice), or 19 R$. "
			.. "Day-2 daily reward grants a melee (wiki conflicts: Saber vs Iron).",
	},
	{
		id = "changelog-recent",
		cat = "Change Log",
		title = "Recent updates",
		keys = "change log update pulsar kuiper lobby sirius proxima planet x",
		body = "2026-05-30 Pulsar - 2026-05-23 PSO / Heat Laser / Lava Pluto - 2026-02-21 Kuiper "
			.. "Belt pt1 - 2026-01-10 Lobby (70-player servers, credits leaderboard, permanent "
			.. "credit items) - 2026-01-04 Sirius/Black Hole - 2025-12-20 Interstellar (Proxima, "
			.. "Oil/Stone/Iron) - 2025-12-07 Planet X (antimatter + Space Station + Diamond "
			.. "Pickaxe & Rocket Launcher in credit shop).",
	},
	{
		id = "changelog-balance",
		cat = "Change Log",
		title = "Balance changes worth knowing",
		keys = "balance converters no hold moon boss nerf ion spawn venus mercury change",
		body = "2025-12-17: Moon Boss HP 10k->5k, Saber cd 2s->1.7s, converters no-hold, ion spawn "
			.. "1.4x, anti 1.3x. 2025-11-18: Sun->Earth 1000s->666s; items save after death except "
			.. "fuels/juice. 2025-11-09: ionized ONLY from Mercury (Venus surface removed). "
			.. "2025-12-02: daily rewards added; Moon Monsters drop Moon Juice.",
	},
	{
		id = "wiki-info",
		cat = "Change Log",
		title = "Game & wiki info",
		keys = "creator cr7siuuu wiki discord horror mr friend antagonists",
		body = "The Moon Wakes Up by Cr7SIUUU, based on the cosmic analogue horror 'The Moon Woke "
			.. "Up' by Mr. Friend. Discord 13+. Wiki: the-moon-wakes-up-roblox.fandom.com. Main "
			.. "antagonist: the Awaken Planets. Key wiki articles: Items, Change Log, Endings, "
			.. "Awaken Planets, Currencies.",
	},
}

local knowledge = {}
knowledge.entries = entries

-- Titles in display order (the dropdown's option list).
function knowledge.topicList()
	local out = {}
	for _, e in ipairs(entries) do
		out[#out + 1] = e.title
	end
	return out
end

function knowledge.get(title)
	for _, e in ipairs(entries) do
		if e.title == title then
			return e.body, e.cat
		end
	end
	return nil, nil
end

function knowledge.random()
	return entries[math.random(1, #entries)]
end

-- Scored search: every query token counts hits in title (x3), keys (x2)
-- and body (x1). Returns up to `limit` entries, best first.
function knowledge.search(query, limit)
	limit = limit or 3
	local q = string.lower(query or "")
	local tokens = {}
	for w in string.gmatch(q, "[%w']+") do
		if #w >= 2 then
			tokens[#tokens + 1] = w
		end
	end
	local scored = {}
	if #tokens > 0 then
		for _, e in ipairs(entries) do
			local title = string.lower(e.title)
			local keys = string.lower(e.keys)
			local body = string.lower(e.body)
			local score = 0
			for _, w in ipairs(tokens) do
				if string.find(title, w, 1, true) then
					score += 3
				end
				if string.find(keys, w, 1, true) then
					score += 2
				end
				if string.find(body, w, 1, true) then
					score += 1
				end
			end
			if score > 0 then
				scored[#scored + 1] = { e = e, score = score }
			end
		end
		table.sort(scored, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.e.title < b.e.title
		end)
	end
	local out = {}
	for i = 1, math.min(limit, #scored) do
		out[#out + 1] = scored[i].e
	end
	return out
end

return knowledge
]==],
	["minekey"] = [==[
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
	local function recover()
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

	local function swingLoop(myGen: number)
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
		while swinging and runId == myGen do
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
				while swinging and runId == myGen and os.clock() - t0 < waitSecs do
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
								task.spawn(recover)
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
			task.spawn(function()
				swingLoop(myGen)
			end)
		else
			anchor = nil
			stopWalk()
		end
		if util and util.notify then
			util.notify("Auto-mine", swinging and "ON - one click per completed swing" or "OFF")
		end
	end

	function minekey.start()
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
		runId = runId + 1
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
		return listening
	end

	function minekey.isSwinging(): boolean
		return swinging
	end

	function minekey.getAnchor()
		return anchor
	end

	return minekey
end
]==],
	["moonjuice_farm"] = [==[
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
]==],
	["noshake"] = [==[
--!strict
-- Paralyz / src/noshake.luau
-- Auto-disable screen shake at script execution (user request 2026-10-12):
-- "whenever the script is executed it waits no time and just turns off
-- screen shake from settings so i dont need to do that, in any place".
-- Quiet by design - no toast, it just happens.
--
-- How the game does it (reverse-engineered read-only, subplace index):
--   * Settings row click [docId 39]:
--       if Display.Text == "Enabled" then
--           Display.Text = "Disabled"
--           Image = <disabled graphic>
--           Events.CameraShake:FireServer(true)   <- the DISABLE action
--       end
--   * The server answers by parenting a NumberValue "Anti Screen Shake"
--     into the player.
--   * PlayerGui ScreenGui.CameraShake [docId 36] skips EVERY shake while
--     that object exists:
--       if not LocalPlayer:FindFirstChild("Anti Screen Shake") then
--           u18:ShakeOnce(...)
--       end
--   * The object is never created by any indexed game script, so it is
--     wiped with the player on rejoin -> the user's manual every-session
--     chore. This module replays their exact manual action instead.
--
-- Implementation: if the object is missing, FireServer(true) - the same
-- remote call the settings button makes - then verify it appeared (3s).
-- If the server never answers, parent the same NumberValue client-side:
-- the only consumer checks presence, so the effect is identical. The row
-- UI (Display "Disabled" + matching image) is synced so the settings menu
-- shows the true state when opened later. Boot-time only: if you later
-- deliberately re-enable shake in settings, this does not fight you.

return function(deps)
	local util = deps.util

	local noshake = {}

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local OBJ = "Anti Screen Shake"
	local DISABLED_IMAGE = "rbxassetid://124658924075155" -- row image when Display = "Disabled"

	local running = false

	local function exists(): boolean
		return Players.LocalPlayer:FindFirstChild(OBJ) ~= nil
	end

	-- Replay the settings row's disable click exactly.
	local function fireDisable(): boolean
		local events = ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("CameraShake")
		if not remote then
			return false
		end
		return pcall(function()
			remote:FireServer(true)
		end)
	end

	-- Fallback: parent the same object locally. CameraShake only checks
	-- presence, so a client-side copy fully blocks the shake event.
	local function makeLocal()
		if exists() then
			return
		end
		pcall(function()
			local v = Instance.new("NumberValue")
			v.Name = OBJ
			v.Value = 0
			v.Parent = Players.LocalPlayer
		end)
	end

	-- Keep the settings row honest: Display "Disabled" + its image, so
	-- opening the menu later shows the real state. Purely cosmetic and
	-- fully guarded - the settings GUI may not exist in every place.
	local function syncRow()
		pcall(function()
			local plrGui = Players.LocalPlayer.PlayerGui
			local gui = plrGui:FindFirstChild("Settings")
			local frame = gui and gui:FindFirstChild("Frame")
			local main = frame and frame:FindFirstChild("settings main frame")
			if not main then
				return
			end
			local label = nil
			for _, d in ipairs(main:GetDescendants()) do
				if string.find(string.lower(d.Name), "shake", 1, true) then
					label = d
					break
				end
			end
			if not label or not label:IsA("GuiObject") then
				return
			end
			local best = nil
			local bestDy = 0.12
			for _, d in ipairs(main:GetChildren()) do
				if d:IsA("Frame") then
					local dy = math.abs(d.Position.Y.Scale - label.Position.Y.Scale)
					if dy <= bestDy then
						best = d
						bestDy = dy
					end
				end
			end
			if not best then
				return
			end
			local btn = nil
			for _, c in ipairs(best:GetDescendants()) do
				if c:IsA("ImageButton") then
					btn = c
					break
				end
			end
			if not btn then
				return
			end
			btn.Image = DISABLED_IMAGE
			local disp = btn:FindFirstChild("Display")
			if disp and disp:IsA("TextLabel") then
				disp.Text = "Disabled"
			end
		end)
	end

	local function ensure()
		if not exists() then
			fireDisable()
			local t0 = os.clock()
			while not exists() and os.clock() - t0 < 3 do
				task.wait(0.1)
			end
			if not exists() then
				makeLocal()
			end
		end
		syncRow()
	end

	-- Called by the loader immediately after module fetch - before the
	-- window even exists ("waits no time").
	function noshake.start()
		if running then
			return
		end
		running = true
		task.spawn(function()
			local ok, err = pcall(ensure)
			if not ok then
				warn("[Paralyz] noshake failed: " .. tostring(err))
			end
		end)
	end

	function noshake.stop()
		running = false
	end

	function noshake.isRunning(): boolean
		return running
	end

	function noshake.isOff(): boolean
		return exists()
	end

	return noshake
end
]==],
	["perf"] = [==[
--!strict
-- Paralyz / src/perf.luau
-- Lower Usage mode = client-side frustum culling (user request 2026-10-12:
-- "an optimizer so good that visually changes NOTHING, but lowers gpu
-- usage like amazing something like fruntum culling... replacing lower
-- usage in settings, removing fps cap thing from there too").
--
-- How it works: every SLICE seconds a slice of the tracked BaseParts is
-- tested against the camera frustum. Parts outside it get
-- LocalTransparencyModifier = 1 (the renderer skips them entirely), parts
-- back in view get 0. Nothing you can see ever changes:
--   * parts within CULL_NEAR studs are always shown (no pop-in around you),
--   * parts bigger than CULL_MAX studs are never touched (planets, maps -
--     a center-based test would wrongly hide a huge part whose middle is
--     off-screen but whose edge you can see),
--   * a MARGIN-degree border around the frustum absorbs fast camera moves,
--   * your own character is never touched (first-person arms stay visible),
--   * quality level, shadows, post effects and frame cap are NEVER touched.
-- Streaming already unloads far folders server-side; this stacks on top by
-- skipping everything the camera cannot see, which is most of the frame on
-- a planet surface. The scan itself is budgeted (a few hundred parts per
-- slice) so the optimizer never costs more than it saves.
--
-- Interface kept: perf.apply(on) toggles, perf.report() describes.

return function(deps)
	local config = deps.config

	local Players = game:GetService("Players")
	local workspace = game:GetService("Workspace")
	local Lighting = game:GetService("Lighting")

	local perf = {}

	local enabled = false
	local runId = 0
	local registry: { BasePart } = {}
	local cursor = 1
	local lastRegistryBuild = 0
	local hidden: { [BasePart]: boolean } = {}
	local hiddenCount = 0
	local trackedCount = 0

	local function opts()
		local p = config.perf or {}
		return {
			near = p.cullNearDist or 150,
			maxSize = p.cullMaxSize or 120,
			marginDeg = p.cullMarginDeg or 10,
			budget = p.cullBudget or 400,
			slice = p.cullSliceSecs or 0.25,
			refresh = p.cullRefreshSecs or 8,
		}
	end

	local function maxDim(part: BasePart): number
		local s = part.Size
		local m = s.X
		if s.Y > m then
			m = s.Y
		end
		if s.Z > m then
			m = s.Z
		end
		return m
	end

	-- Rebuild the tracked-part list (cheap filter; per-slice checks stay exact).
	local function buildRegistry(o)
		local char = Players.LocalPlayer.Character
		local fresh: { BasePart } = {}
		local ok, desc = pcall(function()
			return workspace:GetDescendants()
		end)
		if not ok or type(desc) ~= "table" then
			return
		end
		for _, d in ipairs(desc) do
			if d:IsA("BasePart") then
				local part = d :: BasePart
				local skip = false
				if char and part:IsDescendantOf(char) then
					skip = true -- your own body, always rendered
				end
				if not skip then
					local okSize, big = pcall(maxDim, part)
					if not okSize or (big or 0) > o.maxSize then
						skip = true -- huge geometry: never touch
					end
				end
				if not skip then
					local okTr, tr = pcall(function()
						return part.Transparency
					end)
					if okTr and (tr or 0) >= 1 then
						skip = true -- already invisible: nothing to save
					end
				end
				if not skip then
					table.insert(fresh, part)
				end
			end
		end
		-- Nearest first: near parts refresh every slice, so any pop-in
		-- lag only ever affects far geometry (turning fix).
		local camNow = workspace.CurrentCamera
		if camNow then
			local campos = camNow.CFrame.Position
			pcall(table.sort, fresh, function(a: BasePart, b: BasePart): boolean
				return (a.Position - campos).Magnitude < (b.Position - campos).Magnitude
			end)
		end
		-- Purge destroyed parts from the hidden set (keeps the count honest).
		for part, _ in pairs(hidden) do
			local okAlive = pcall(function()
				return part.Parent ~= nil
			end)
			if not okAlive then
				hidden[part] = nil
				hiddenCount -= 1
			end
		end
		registry = fresh
		trackedCount = #fresh
		if cursor > #fresh then
			cursor = 1
		end
		lastRegistryBuild = os.clock()
	end

	-- True when the part is outside the camera frustum (with margin).
	local function isOutside(part: BasePart, cam: Camera, o): boolean
		local campos = cam.CFrame.Position
		local toPart = part.Position - campos
		local dist = toPart.Magnitude
		if dist <= o.near then
			return false
		end
		if dist < 0.001 then
			return false
		end
		local size = cam.ViewportSize
		if size.Y <= 0 then
			return false
		end
		local aspect = size.X / size.Y
		local halfV = math.rad(cam.FieldOfView / 2 + o.marginDeg)
		local halfH = math.atan(math.tan(math.rad(cam.FieldOfView / 2)) * aspect) + math.rad(o.marginDeg)
		local rel = cam.CFrame:PointToObjectSpace(part.Position)
		if rel.Z > 0 then
			return true -- behind the camera: never visible (this was the
			-- leak - everything behind you kept rendering)
		end
		if rel.Z >= -o.near then
			return false -- beside the near plane: stay shown
		end
		local depth = -rel.Z
		return math.abs(rel.X / depth) > math.tan(halfH) or math.abs(rel.Y / depth) > math.tan(halfV)
	end

	local function setShown(part: BasePart, show: boolean)
		local ok = pcall(function()
			part.LocalTransparencyModifier = show and 0 or 1
		end)
		if not ok then
			return
		end
		if show then
			if hidden[part] then
				hidden[part] = nil
				hiddenCount -= 1
			end
		else
			if not hidden[part] then
				hidden[part] = true
				hiddenCount += 1
			end
		end
	end

	local function restoreAll()
		for part, _ in pairs(hidden) do
			pcall(function()
				part.LocalTransparencyModifier = 0
			end)
		end
		table.clear(hidden)
		hiddenCount = 0
	end

	local function scanSlice(myGen: number)
		if not enabled or runId ~= myGen then
			return
		end
		local o = opts()
		if os.clock() - lastRegistryBuild >= o.refresh or #registry == 0 then
			buildRegistry(o)
		end
		if #registry == 0 then
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local char = Players.LocalPlayer.Character
		local n = #registry
		local done = 0
		while done < o.budget and enabled and runId == myGen do
			if cursor > n then
				cursor = 1
			end
			local part = registry[cursor]
			cursor += 1
			done += 1
			if part ~= nil then
				local ok = pcall(function()
					if part.Parent == nil then
						return -- destroyed since the registry build
					end
					if char and part:IsDescendantOf(char) then
						return -- equipped since the registry build
					end
					setShown(part, not isOutside(part, cam, o))
				end)
				if not ok then
					-- A single bad part must not kill the slice.
				end
			end
		end
	end

	local function loop(myGen: number)
		while enabled and runId == myGen do
			local o = opts()
			local ok, err = pcall(scanSlice, myGen)
			if not ok then
				warn("[Paralyz] perf cull slice error: " .. tostring(err))
			end
			task.wait(o.slice)
		end
	end

	-- Turns Lower Usage on or off. Returns a short report string.
	function perf.apply(on: boolean): string
		if on then
			if enabled then
				return string.format("already on - %d hidden / %d tracked", hiddenCount, trackedCount)
			end
			enabled = true
			runId += 1
			local myGen = runId
			lastRegistryBuild = 0
			task.spawn(function()
				loop(myGen)
			end)
			return "frustum culling on - off-screen parts skip rendering, nothing visible changes"
		end
		if not enabled then
			return "already off"
		end
		enabled = false
		runId += 1
		restoreAll()
		registry = {}
		trackedCount = 0
		cursor = 1
		return "frustum culling off - every part restored"
	end

	function perf.stop()
		enabled = false
		runId += 1
		restoreAll()
		registry = {}
		trackedCount = 0
	end

	function perf.report(): string
		return string.format(
			"culling=%s hidden=%d tracked=%d quality=%s shadows=%s",
			enabled and "on" or "off",
			hiddenCount,
			trackedCount,
			tostring(settings().Rendering.QualityLevel),
			tostring(Lighting.GlobalShadows)
		)
	end

	return perf
end
]==],
	["promptkey"] = [==[
--!strict
-- Paralyz / src/promptkey.luau
-- F8 prompt auto-fire (user request 2026-10-12): while toggled on, the
-- nearest enabled ProximityPrompt in range is fired every 0.1s - bulk
-- converting at the Omega/Ion machines without spamming the key.
--
-- Why a toggle instead of "repeat while the prompt key is held": prompt
-- keys are per-prompt (each prompt carries its own KeyboardKeyCode), and
-- blind auto-repeat on EVERY held prompt would also double-fire purchase
-- prompts (hold-to-buy = multiple buys). A conscious toggle standing at
-- the machine is safe and needs no key detection at all.
--
-- Uses the same fireproximityprompt builtin as instantprompts. Never moves
-- the character. Nearest = closest enabled prompt within its own
-- MaxActivationDistance of the character root.

return function(deps)
	local util = deps.util

	local promptkey = {}

	local KEY = Enum.KeyCode.F8
	local RATE = 0.1 -- seconds between auto-fires

	local UIS = game:GetService("UserInputService")
	local Players = game:GetService("Players")

	local listening = false
	local autofiring = false
	local conn: RBXScriptConnection? = nil

	local function nearestPrompt(): ProximityPrompt?
		local plr = Players.LocalPlayer
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return nil
		end
		local best: ProximityPrompt? = nil
		local bestDist = math.huge
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Enabled and d.MaxActivationDistance > 0 then
				-- Adornee is the prompt's PARENT (BasePart / Attachment / Model).
				local pos = nil
				local par = d.Parent
				if par then
					if par:IsA("BasePart") then
						pos = par.Position
					elseif par:IsA("Attachment") then
						pos = par.WorldPosition
					else
						local bp = par:FindFirstChildWhichIsA("BasePart", true)
						if bp then
							pos = bp.Position
						end
					end
				end
				if pos then
					local dist = (pos - root.Position).Magnitude
					if dist <= d.MaxActivationDistance and dist < bestDist then
						bestDist = dist
						best = d
					end
				end
			end
		end
		return best
	end

	local function fireLoop()
		while autofiring do
			local p = nearestPrompt()
			if p then
				pcall(fireproximityprompt, p)
			end
			task.wait(RATE)
		end
	end

	local function toggle()
		autofiring = not autofiring
		if autofiring then
			task.spawn(fireLoop)
		end
		if util and util.notify then
			util.notify("Prompt auto", autofiring and "ON - firing the nearest prompt 10x/s" or "OFF")
		end
	end

	function promptkey.start()
		if listening then
			return
		end
		if type(fireproximityprompt) ~= "function" then
			if util and util.notify then
				util.notify("Prompt auto", "this executor has no fireproximityprompt")
			end
			return
		end
		listening = true
		-- Not gated on gameProcessed (same lesson as minekey F7): GUIs claim
		-- keys and mark them processed; only a focused text box blocks F8.
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

	function promptkey.stop()
		autofiring = false
		listening = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	function promptkey.isRunning(): boolean
		return listening
	end

	function promptkey.isFiring(): boolean
		return autofiring
	end

	return promptkey
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
	["safezone"] = [==[
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

	-- Position of the prompt holder for a machine prompt (the ionizer and
	-- anti converter both hang their ProximityPrompt off a "PartProximity"
	-- BasePart inside the machine).
	local function promptPos(get: () -> ProximityPrompt?): Vector3?
		local prompt = get()
		if not prompt then
			return nil
		end
		local holder = prompt.Parent
		if holder and holder:IsA("BasePart") then
			return (holder :: BasePart).Position
		end
		local part = holder and (holder :: Instance):FindFirstChildWhichIsA("BasePart", true)
		return part and (part :: BasePart).Position or nil
	end

	-- Live centre of the planet currently hosting the Space Station (the
	-- anti converter rides along with it). Folders do not stream, so this
	-- resolves even when the station's parts are unloaded.
	local function stationPlanetCentre(): Vector3?
		local planets = workspace:FindFirstChild("Planets")
		if planets then
			for _, p in ipairs((planets :: Folder):GetChildren()) do
				if p:FindFirstChild("SpaceStation") then
					local c = (p :: any):FindFirstChild("Center")
					if c and c:IsA("BasePart") then
						return (c :: BasePart).Position
					end
				end
			end
		end
		return planetCentre(1)
	end

	-- A destination is a function, not a coordinate: structures stream with
	-- distance and planets DRIFT across the round, so positions are always
	-- read live. Optional seed() names a living relative of the destination
	-- (usually its planet): when resolve() is nil the teleport goes and
	-- stands on the seed instead - the load then brings the destination
	-- back and the re-resolve finds the real spot. This beats remembered
	-- coordinates, which go stale the moment the planet moves.
	type Dest = {
		name: string,
		group: string,
		resolve: () -> Vector3?,
		seed: (() -> Vector3?)?,
		-- Machine destinations resolve to the prompt holder itself, which
		-- sits UNDER the station's roof deck: dropToSurface would land on
		-- top of the hull, 200+ studs out of the prompt's 10-stud range.
		-- Precise destinations land directly on the resolved position
		-- (same +3 as the farm's convert walks).
		precise: boolean?,
	}

	-- Planet names are the story's names (P1 Earth, P2 Moon, P3 Venus,
	-- P4 Mars, P5 Mercury, P6 Pluto), not the internal PlanetN folders.
	local destinations: { Dest } = {
		{ name = "Bunker", group = "hub", resolve = function() return anchorOf({ "Bunker" }) end, seed = nil },
		{ name = "City", group = "hub", resolve = function() return anchorOf({ "City" }) end, seed = nil },
		{
			name = "Venus City",
			group = "hub",
			resolve = function() return anchorOf({ "VenusCity" }) end,
			seed = function() return planetCentre(3) end,
		},
		{
			name = "Mars City",
			group = "hub",
			resolve = function() return anchorOf({ "MarsCity" }) end,
			seed = function() return planetCentre(4) end,
		},
		{ name = "Sun", group = "landmark", resolve = function() return anchorOf({ "Sun" }) end, seed = nil },
		{
			name = "Space Station",
			group = "station",
			resolve = function()
				local planets = workspace:FindFirstChild("Planets")
				if not planets then
					return nil
				end
				for _, p in ipairs((planets :: Folder):GetChildren()) do
					local station = p:FindFirstChild("SpaceStation")
					local part = station and (station :: Instance):FindFirstChildWhichIsA("BasePart", true)
					if part then
						return (part :: BasePart).Position
					end
				end
				return nil
			end,
			seed = stationPlanetCentre,
		},
		{
			name = "Ionizer",
			group = "ionizer",
			resolve = function() return promptPos(util.ionizerPrompt) end,
			-- The ionizer was measured on Pluto (Planet6.PlutoIndustries).
			seed = function() return planetCentre(6) end,
			precise = true,
		},
		{
			name = "Converter",
			group = "converter",
			resolve = function() return promptPos(util.converterPrompt) end,
			-- The anti converter lives on the Space Station, wherever it orbits.
			seed = stationPlanetCentre,
			precise = true,
		},
		{ name = "Earth", group = "planet", resolve = function() return planetCentre(1) end, seed = nil },
		{ name = "Moon", group = "planet", resolve = function() return planetCentre(2) end, seed = nil },
		{ name = "Venus", group = "planet", resolve = function() return planetCentre(3) end, seed = nil },
		{ name = "Mars", group = "planet", resolve = function() return planetCentre(4) end, seed = nil },
		{ name = "Mercury", group = "planet", resolve = function() return planetCentre(5) end, seed = nil },
		{ name = "Pluto", group = "planet", resolve = function() return planetCentre(6) end, seed = nil },
	}
	travel.destinations = destinations

	-- Saved selections from earlier versions used the internal names.
	local aliases: { [string]: string } = {
		["Planet 1"] = "Earth",
		["Planet 2"] = "Moon",
		["Planet 3"] = "Venus",
		["Planet 4"] = "Mars",
		["Planet 5"] = "Mercury",
		["Planet 6"] = "Pluto",
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

	-- Old saved selections and scripts used the internal "Planet N" names.
	function travel.canonical(name: string): string
		return aliases[name] or name
	end

	-- Set the CFrame and confirm it stuck after a beat: a respawn, a
	-- story cutscene or an external script can swallow a single write,
	-- and the old code only ever verified planet landings.
	local function landVerified(target: Vector3, tries: number, precise: boolean?): boolean
		for _ = 1, tries do
			local root = util.root()
			if not root then
				task.wait(0.4)
				continue
			end
			-- Precise targets (machine prompts under a roof deck) must not
			-- surface-drop: the deck above would swallow the landing.
			local spot = if precise then target + Vector3.new(0, 3, 0) else util.dropToSurface(target)
			local land = CFrame.new(spot)
			root.CFrame = land
			util.teleported(land)
			task.wait(0.25)
			local after = util.root()
			-- "Did the write stick?" is answered against the spot we aimed
			-- at (surface drops land hundreds of studs from a planet's
			-- centre by design); precise targets also demand proximity to
			-- the machine itself, since that is the whole point.
			local stuck = after and util.dist(after.Position, spot) < (if precise then 15 else 400)
			if stuck then
				return true
			end
		end
		return false
	end

	-- Teleport to a named destination. Planet "Center" parts are the planet
	-- itself, so landing uses the shared surface raycast: drop from above
	-- and land on the ground, never inside the geometry. Blind or planet
	-- destinations additionally wait for the load before a verified
	-- re-landing; fresh resolves get a short verify + retry as well.
	function travel.to(name: string): boolean
		name = travel.canonical(name)
		local entry: Dest? = nil
		for _, d in ipairs(travel.destinations) do
			if d.name == name then
				entry = d
				break
			end
		end
		if not entry then
			return false
		end
		local dest: Dest = entry

		local pos = dest.resolve()
		-- blind = we are teleporting without a fresh resolve (seeded or
		-- remembered coordinate): the destination then gets a load wait and
		-- a verified re-landing, exactly like planets do.
		local blind = false
		if not pos and dest.seed then
			-- The destination's living relative (usually its planet) always
			-- knows where the neighbourhood is: planets DRIFT across the
			-- round, so a live centre beats remembered coordinates, and
			-- standing on the planet streams its structures back in.
			pos = dest.seed()
			if pos then
				blind = true
				util.notify("Teleport", dest.name .. " is not loaded - going to its planet first")
			end
		end
		if not pos then
			-- Unloaded but visited this session: go to where it was and let
			-- the load bring it back (checked again after the wait below).
			local cached = known[dest.name]
			if cached then
				pos = cached
				blind = true
				util.notify("Teleport", dest.name .. " is not loaded - going to its last position")
			end
		end
		if not pos then
			-- Never visited this session but the hub has a measured spawn
			-- anchor: standing on it streams the structure back in. Without
			-- this, a hub request from across the world silently fell back
			-- to a different hub (Bunker -> Venus City).
			local seeded = config.travel.hubFallbacks[dest.name]
			if seeded then
				pos = seeded
				blind = true
				util.notify("Teleport", dest.name .. " is not loaded - going to its usual spot")
			end
		end
		if not pos then
			-- Genuinely not in this world phase: fall back to a sibling in
			-- the same group instead of failing outright (fresh resolve, so
			-- no confirm wait needed for the destination we end up at).
			for _, alt in ipairs(travel.destinations) do
				if alt.group == dest.group and alt.name ~= dest.name then
					local altPos = alt.resolve()
					if altPos then
						util.notify(
							"Teleport",
							dest.name .. " is not in this world - going to " .. alt.name
						)
						dest = alt
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
		-- Rough hop first (streams the area while the load wait runs).
		-- Precise targets skip the surface drop - but only when the
		-- position is the machine itself; a blind seed is still a planet
		-- centre, which needs the drop like any planet.
		local rough = if dest.precise and not blind
			then pos + Vector3.new(0, 3, 0)
			else util.dropToSurface(pos)
		root.CFrame = CFrame.new(rough)
		util.teleported(root.CFrame)

		-- The destination may have been teleported to blind, or may be a
		-- planet whose rocks stream in seconds after arrival: wait for the
		-- load, re-resolve in case the real position differs from the
		-- remembered one, and ALWAYS land on the fresh spot afterwards (the
		-- old code skipped this when re-resolving failed, which is exactly
		-- the "it loads but never takes me there" the user had to spam past).
		if blind or dest.group == "planet" then
			local n = 0
			local fresh: Vector3? = nil
			if dest.group == "planet" then
				-- Planets prove their load with rocks.
				n = util.settleRocks(pos, config.farm.loadWait, config.farm.streamRadius)
				fresh = dest.resolve()
			else
				-- Hubs prove it by re-resolving: the folder is always
				-- there, its structure parts only exist once streamed.
				local deadline = os.clock() + config.farm.loadWait
				while os.clock() < deadline do
					fresh = dest.resolve()
					if fresh then
						break
					end
					task.wait(0.5)
				end
			end
			local resolved = fresh ~= nil
			fresh = fresh or pos
			known[dest.name] = fresh
			-- landVerified re-fetches the root each try: the wait is long
			-- enough for a respawn, and a stale BasePart reference silently
			-- does nothing. Precise only when the position came from a
			-- resolve (the machine); a fallback to the seed is a planet
			-- centre and needs the surface drop.
			local landed = landVerified(fresh, 4, dest.precise and resolved)
			local suffix
			if not landed then
				suffix = " - load wait ended but the landing would not stick"
			elseif dest.group == "planet" and n > 0 then
				suffix = " - loaded, " .. n .. " rocks"
			elseif dest.group == "planet" then
				suffix = " - still empty after waiting"
			elseif dest.resolve() then
				suffix = " - loaded"
			else
				suffix = " - did not load, it may not exist in this phase"
			end
			util.notify("Teleport", dest.name .. suffix)
		else
			-- Fresh resolve: still verify, just with a short budget. The
			-- first write above can be swallowed by a respawn or a story
			-- cutscene, and a teleport that silently does nothing is the
			-- worst failure mode this button can have.
			known[dest.name] = pos
			if not landVerified(pos, 2, dest.precise) then
				util.notify("Teleport failed", dest.name .. " - the landing would not stick, try again")
				return false
			end
		end
		return true
	end

	-- Teleport somewhere the menu names but the module does not hardcode,
	-- e.g. "nearest rock".
	function travel.toPosition(pos: Vector3): boolean
		if not util.root() then
			return false
		end
		return landVerified(pos + Vector3.new(0, 6, 0), 3)
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
			local char = util.character()
			local root = util.root()
			local hum = util.humanoid()
			-- The fly loop parks the humanoid in Physics every frame; without
			-- an explicit recovery the character stays frozen and cannot walk
			-- again after the toggle goes off.
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
			end
			if hum then
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				if hum:GetState() == Enum.HumanoidStateType.Physics then
					hum:ChangeState(Enum.HumanoidStateType.Running)
				end
			end
			-- Give collisions back unless the Noclip toggle wants them off.
			if not state.enabled("Noclip") and char then
				for _, part in ipairs(char:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = true
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
-- pcall-wrapped: a constructor Rayfield build does not have (CreateSection
-- is the one that historically bites) degrades to "no heading" instead of killing
-- the whole menu.
--
-- This module is included by loader.luau via deps.ui. It creates the in-game
-- menu (Rayfield Gen2) with tabs for Farm, ESP, Travel, Assistant and Settings.
-- State is shared through the central deps.state object so that every module
-- can read/write the same values without duplicating logic.

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

	function ui.stat(tab, props)
		return guard("stat", function()
			return tab:CreateStat(props)
		end)
	end

	function ui.text(tab, props)
		return guard("text", function()
			return tab:CreateText(props)
		end)
	end

	function ui.textBox(tab, key: string, props)
		props = props or {}
		props.flag = key
		props.callback = function(value)
			state.set(key, value)
		end
		local handle = guard("textBox", function()
			return tab:CreateTextBox(props)
		end)
		if handle then
			state.bind(key, handle)
		end
		return handle
	end

	-- MoonJuice spawner toggle (Farm tab): plain state-setter like every
	-- other helper - the loader's state.on("MoonJuiceFarm") owns start/stop.
	function ui.moonjuicefarm_toggle(tab, key: string, props)
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

	return ui
end]==],
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

	-- The three juice tiers, split by name: plain MoonJuice (15/stack),
	-- "Ionized MoonJuice" (20), "Anti Matter MoonJuice" (74).
	function util.isIon(tool: Instance): boolean
		return string.find(string.lower(tool.Name), "ion", 1, true) ~= nil
	end

	function util.isAnti(tool: Instance): boolean
		return string.find(string.lower(tool.Name), "anti", 1, true) ~= nil
	end

	function util.plainJuiceCount(): number
		local n = 0
		for _, entry in ipairs(util.juiceTools()) do
			if not util.isIon(entry.tool) and not util.isAnti(entry.tool) then
				n += 1
			end
		end
		return n
	end

	function util.antiJuiceCount(): number
		local n = 0
		for _, entry in ipairs(util.juiceTools()) do
			if util.isAnti(entry.tool) then
				n += 1
			end
		end
		return n
	end

	-- How many anti-matter stacks can be sold RIGHT NOW without touching a
	-- non-anti stack. MEASURED (2026-10-07, job "sell-order"): the server
	-- sells the OLDEST tools first, in Backpack insertion order - firing
	-- (1,false) with [MoonJuice, Ionized] aboard removed the MoonJuice, and
	-- the game's own sell preview sums `first N` the same way. So the safe
	-- subset = the leading run of anti-matter tools; anything behind an
	-- older plain/ion stack stays held until it converts (or the round
	-- end dump fires).
	function util.sellableAnti(): number
		local list = util.juiceTools()
		local n = 0
		for i = 1, #list do
			if util.isAnti(list[i].tool) then
				n += 1
			else
				break
			end
		end
		return n
	end

	-- Sells ONLY the leading anti-matter run (the game's own "sell N"
	-- contract: (count, false)). Returns the stacks sold.
	function util.sellAnti(): number
		local n = util.sellableAnti()
		if n == 0 then
			return 0
		end
		local events = ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("SellMoonjuice")
		if remote then
			(remote :: RemoteEvent):FireServer(n, false)
		end
		return n
	end

	-- Is any sell/convert action actually pending right now? Used to decide
	-- whether a swing batch must yield; a plain hold below the cap keeps
	-- mining (stacking for the round-end dump) instead of spinning. The
	-- conversion check mirrors the loop's threshold: below sellAt the
	-- machines are deliberately NOT used yet, so they are not "pending".
	function util.sellActionPending(): boolean
		if util.juiceCount() == 0 then
			return false
		end
		if util.roundEndSoon() then
			return true
		end
		if util.sellableAnti() > 0 then
			return true
		end
		if util.juiceCount() >= config.farm.sellAt then
			if util.ionJuiceCount() > 0 and util.converterPrompt() then
				return true
			end
			if util.plainJuiceCount() > 0 and util.ionizerPrompt() then
				return true
			end
		end
		return false
	end

	---------------------------------------------------------------- round end
	-- Values.ClientSeconds is the story clock; it resets when the round
	-- restarts (measured: 3527 -> 5 after the final story chain).
	function util.storyClock(): number
		local values = ReplicatedStorage:FindFirstChild("Values")
		local cs = values and values:FindFirstChild("ClientSeconds")
		return cs and (cs :: NumberValue).Value or 0
	end

	-- End-of-round signals, MEASURED on the restart the round-end watcher
	-- caught (round ended at ClientSeconds=3527):
	--   * The final story chain arrives over the Text remote shortly before
	--     the hard reset: "THE DYSON SPHERE GOT DESTROYED!" (~20s to go)
	--     and "THE SUN IS MOVING! ..." (~10s). Both are inside the user's
	--     ~30s dump window.
	--   * PlayerGui.Fim ("The End") as generic backup - it NEVER enabled in
	--     the measured round, so it cannot be the only signal.
	--   * config.farm.roundLength clock threshold, disabled (0) until the
	--     watcher proves the length constant - measured rounds ended at
	--     2854 and 3527, so it is NOT constant.
	-- The flag clears itself when the clock rewinds: that is a new round.
	-- Fim ALONE is not an end signal: measured 2026-10-08, the current game
	-- version keeps PlayerGui.Fim enabled from round start (it stayed on the
	-- whole round while the clock climbed past 3000s - a "hide in the
	-- bunker" overlay). Fim only counts together with a STOPPED story clock,
	-- the state measured right before every hard reset (clock freezes, Fim
	-- shows 10-41s, then the wipe) and during the 2026-10-08 server wedge.
	local lastCs = util.storyClock()
	local lastCsAt = os.clock()
	local END_MARKERS = {
		"dyson sphere got destroyed",
		"the sun is moving",
	}
	local endMarker = false
	local endClock = 0
	local endWatch: RBXScriptConnection? = nil

	local function hookEndWatch()
		if endWatch then
			return
		end
		local events = ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("Text")
		if remote then
			endWatch = (remote :: RemoteEvent).OnClientEvent:Connect(function(msg)
				if typeof(msg) ~= "string" then
					return
				end
				local low = string.lower(msg)
				for _, marker in ipairs(END_MARKERS) do
					if string.find(low, marker, 1, true) then
						endMarker = true
						return
					end
				end
			end)
		end
	end
	hookEndWatch()

	-- Called on shutdown/reload so the old bundle's listener cannot keep
	-- setting the flag after a live-reload.
	function util.stop()
		if endWatch then
			endWatch:Disconnect()
			endWatch = nil
		end
	end

	-- The round is about to restart: everything in the backpack is lost, so
	-- the farm dumps the whole stack regardless of tier.
	function util.roundEndSoon(): boolean
		local cs = util.storyClock()
		if cs < endClock then
			-- clock rewind = a fresh round; the old round's warning expires
			endMarker = false
		end
		endClock = cs
		if endMarker then
			return true
		end
		if cs ~= lastCs then
			-- the round is live: the story clock advances, whatever Fim shows
			lastCs = cs
			lastCsAt = os.clock()
			return false
		end
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		local fim = pg and pg:FindFirstChild("Fim")
		if fim and (fim :: ScreenGui).Enabled and os.clock() - lastCsAt >= 8 then
			return true
		end
		local len = config.farm.roundLength
		if len and len > 0 then
			local win = config.farm.endDumpWindow or 30
			if cs >= len - win then
				return true
			end
		end
		return false
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

	-- The ionizer (plain -> ion), measured once Pluto's colony was built:
	--   Planets.Planet6.Center.PlutoIndustries.ConverterMachine.PartProximity
	-- It reuses the anti converter's exact machine and prompt names
	-- ("ConverterMachine" + "Insert Moonjuice", 2s hold, 10 studs), so the
	-- ONLY reliable identity is the structure above: the anti converter
	-- lives under a SpaceStation, the ionizer under a "<Planet>Industries"
	-- folder. Hierarchy probe first (cheap), then a text fallback for
	-- machines whose shape is not known yet (the Venus/Mercury ion pumps).
	-- Short TTL because the probe walks every planet's descendants.
	local function underStation(inst: Instance): boolean
		local cur: Instance? = inst
		while cur do
			if cur.Name == "SpaceStation" then
				return true
			end
			cur = cur.Parent
		end
		return false
	end

	local ionizerCache: ProximityPrompt? = nil
	local ionizerAt = 0
	function util.ionizerPrompt(): ProximityPrompt?
		if os.clock() - ionizerAt < 2 then
			return ionizerCache
		end
		ionizerAt = os.clock()
		ionizerCache = nil
		local planets = workspace:FindFirstChild("Planets")
		if planets then
			for _, planet in ipairs((planets :: Folder):GetChildren()) do
				for _, inst in ipairs((planet :: Instance):GetDescendants()) do
					if inst.Name == "ConverterMachine" and not underStation(inst) then
						local well = inst:FindFirstChild("PartProximity")
						local prompt = well and well:FindFirstChildWhichIsA("ProximityPrompt", true)
						if prompt then
							ionizerCache = prompt
							return ionizerCache
						end
					end
				end
			end
		end
		-- Unknown-hierarchy fallback: name/text match, anti converter
		-- excluded by the SpaceStation check above so "Insert Moonjuice"
		-- on the station can never be mistaken for the ionizer.
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and not underStation(d) then
				local holder = d.Parent
				local machine = holder and holder.Parent
				local hay = string.lower(
					d.ActionText
						.. " "
						.. d.ObjectText
						.. " "
						.. (holder and holder.Name or "")
						.. " "
						.. (machine and machine.Name or "")
				)
				if string.find(hay, "ioniz", 1, true) or string.find(hay, "ionmoon", 1, true) then
					ionizerCache = d
					return ionizerCache
				end
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

	-- The story's planet names (user mapping): the folders are internal
	-- Planet1..Planet6, but everything user-facing shows these.
	local PLANET_LABELS = {
		Planet1 = "Earth",
		Planet2 = "Moon",
		Planet3 = "Venus",
		Planet4 = "Mars",
		Planet5 = "Mercury",
		Planet6 = "Pluto",
	}

	function util.planetLabel(name: string): string
		return PLANET_LABELS[name] or name
	end

	-- Every planet that exists right now: centre plus how many rocks are
	-- streaming at it. Rocks only exist while somebody is near the planet,
	-- so this doubles as "where can I actually mine".
	function util.planetScan(): { { name: string, label: string, centre: Vector3, rocks: number } }
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
				table.insert(out, { name = planet.Name, label = util.planetLabel(planet.Name), centre = centre, rocks = rocks })
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
					add("AntiMatter@" .. util.planetLabel(planet.Name))
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
local travel = fetchModule("travel")({ config = config, state = state, util = util })
local rewards = fetchModule("rewards")({ config = config, state = state, util = util })
local holdmine = fetchModule("holdmine")({ util = util })
local instantprompts = fetchModule("instantprompts")({ util = util })
local minekey = fetchModule("minekey")({ util = util })
local promptkey = fetchModule("promptkey")({ util = util })
local knowledge = fetchModule("knowledge") -- data table, not a factory
-- Screen shake off at boot, before the window even exists ("waits no
-- time"): replays the settings row's disable action until the game's
-- "Anti Screen Shake" object exists; falls back to a local copy. Quiet -
-- no toast. See src/noshake.luau.
local noshake = fetchModule("noshake")({ util = util })
noshake.start()
-- Upright character watchdog: out of Physics state + spin damped every
-- 0.1s so the avatar stands normally even while flying; see src/flystand.luau.
local flystand = fetchModule("flystand")({ util = util })
flystand.start()
-- Hover hold: F6 freezes the character mid-air (cancels gravity + all
-- momentum) - the fix for "fly stops = slow fall"; see src/hover.luau.
local hover = fetchModule("hover")({ util = util })
hover.start()
-- Safe zone: F5 teleports to the emptiest far-away planet platform and
-- back - lets the assistant test drops/dupes while the user is AFK;
-- see src/safezone.luau.
local safezone = fetchModule("safezone")({ util = util })
safezone.start()
-- MoonJuice spawner: direct Tool creation at millisecond spacing + optional
-- Planet1 swing fallback. GUI toggle only (no keybind); see
-- src/moonjuice_farm.luau. Never started automatically.
local moonjuicefarm = fetchModule("moonjuice_farm")({ util = util })

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
local askTab = window:CreateTab({ name = "Assistant" })
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

ui.moonjuicefarm_toggle(farmTab, "MoonJuiceFarm", {
	name = "MoonJuice spawner",
	description = "OFF by default. Spams client-side MoonJuice copies into the backpack (~25ms each) for drop/pickup practice - the server cannot see them, they can never sell. Real juice still comes from mining.",
})

ui.section(farmTab, "Wallet")

local creditsStat = ui.stat(farmTab, { name = "Credits", value = util.credits() })
local juiceStat = ui.stat(farmTab, { name = "MoonJuice on hand", value = util.juiceValue() })
local farmStat = ui.text(farmTab, { name = "Farm", text = "idle" })
local converterStat = ui.text(farmTab, { name = "Converters built", text = "checking..." })
local sellStat = ui.text(farmTab, { name = "Sell policy", text = "checking..." })

ui.section(farmTab, "Income")

ui.toggle(farmTab, "AutoRewards", {
	name = "Auto rewards",
	description = "Claims playtime chests (event push) and any completed daily/weekly quest the moment they are ready. Free income that needs no player input.",
	value = true,
})

local questStat = ui.text(farmTab, { name = "Quests", text = "checking..." })

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

-- A saved "Planet 5" selection predates the real names; map it once so
-- the dropdown never shows an option that is not in its list.
local savedDest = state.get("TeleportDest")
if type(savedDest) ~= "string" then
	savedDest = "City"
else
	savedDest = travel.canonical(savedDest)
	state.set("TeleportDest", savedDest)
end

ui.dropdown(travelTab, "TeleportDest", {
	name = "Destination",
	description = "Planets use their story names (Earth, Moon, Venus, Mars, Mercury, Pluto). Structures appear when they are built.",
	options = travel.destinationNames(),
	value = savedDest,
})

ui.button(travelTab, {
	name = "Teleport",
	description = "Jump to the selected destination and verify the landing.",
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

ui.section(travelTab, "Chain Machines")

local machineStat = ui.text(travelTab, { name = "Machines", text = "reading..." })

ui.button(travelTab, {
	name = "To ionizer",
	description = "Go to the plain->ion machine (comes with Pluto Colony).",
	callback = function()
		if not travel.to("Ionizer") then
			window:Notify({ title = "Travel", content = "No ionizer in this world yet", duration = 3 })
		end
	end,
})

ui.button(travelTab, {
	name = "To converter",
	description = "Go to the ion->antimatter machine (Space Station).",
	callback = function()
		if not travel.to("Converter") then
			window:Notify({ title = "Travel", content = "No converter in this world yet", duration = 3 })
		end
	end,
})

ui.section(travelTab, "World Phase")

local threatStat = ui.text(travelTab, { name = "Next threat", text = "reading..." })

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
	description = "Studs per second = value x 60. 8 is ~480/s, 32 is ~1920/s.",
	range = { 8, 32 },
	increment = 1,
	value = config.travel.flySpeed,
})

-- Settings ---------------------------------------------------------------
ui.section(settingsTab, "Performance")

ui.toggle(settingsTab, "LowerUsage", {
	name = "Lower Usage",
	description = "Frustum culling: parts the camera cannot see skip rendering. Nothing visible ever changes - no quality, shadow, lighting or frame-cap touches.",
	value = false,
})

ui.section(settingsTab, "Quality of Life")

ui.toggle(settingsTab, "InstantPrompts", {
	name = "Instant Prompts",
	description = "Fires any proximity prompt the instant you start holding it - no hold time. Ported from Infinite Yield's instantpp.",
	value = true,
})

ui.section(settingsTab, "Hub")

ui.button(settingsTab, {
	name = "Unload Paralyz",
	description = "Stops every module and destroys the menu.",
	callback = function()
		shutdown()
	end,
})

--------------------------------------------------------------- assistant
-- Knowledge base tab (wiki + live measurements, distilled into
-- src/knowledge.luau). No game state: everything here is safe to browse
-- while playing.

ui.section(askTab, "Game knowledge (wiki + live measurements)")

local answerCard = ui.text(askTab, {
	name = "Answer",
	text = "Pick a topic below or type a question - prices, endings, awaken conditions, story.",
})

local function setAnswer(text: string)
	if answerCard then
		answerCard:Set(text)
	end
end

local function showTitle(title: string)
	local body, cat = knowledge.get(title)
	if body then
		setAnswer(title .. "\n[" .. cat .. "]\n" .. body)
	end
end

ui.dropdown(askTab, "AskTopic", {
	name = "Topic",
	description = "Every entry the assistant knows - grouped from basics to change log.",
	options = knowledge.topicList(),
	value = state.get("AskTopic"),
})
state.on("AskTopic", function(v)
	if type(v) == "string" then
		showTitle(v)
	end
end)

local askBox = ui.textBox(askTab, "AskQuery", {
	name = "Ask anything",
	description = "Keywords beat sentences: 'pluto terraform', 'ionizer', 'endings', 'prices'.",
	placeholder = "type a question, then press Ask...",
})
if askBox then
	ui.button(askTab, {
		name = "Ask",
		description = "Search the knowledge base for the typed question.",
		callback = function()
			local q = state.get("AskQuery")
			if type(q) ~= "string" or q == "" then
				setAnswer("Type a question first (or use the Topic dropdown).")
				return
			end
			local hits = knowledge.search(q, 3)
			if #hits == 0 then
				setAnswer("Nothing matched '" .. q .. "'.\nTry shorter keywords, or pick a topic from the dropdown.")
				return
			end
			local best = hits[1]
			local extra = ""
			if #hits > 1 then
				extra = "\n\nAlso matching: " .. hits[2].title
				if hits[3] then
					extra ..= ", " .. hits[3].title
				end
			end
			setAnswer(best.title .. "\n[" .. best.cat .. "]\n" .. best.body .. extra)
		end,
	})
end

ui.button(askTab, {
	name = "Surprise me",
	description = "Show a random entry from the knowledge base.",
	callback = function()
		local e = knowledge.random()
		showTitle(e.title)
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

local function applyLowerUsage(v)
	local report = perf.apply(v == true)
	window:Notify({ title = "Lower Usage", content = report, duration = 4 })
end

local function applyInstantPrompts(v)
	if v then
		instantprompts.start()
	else
		instantprompts.stop()
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
state.on("InstantPrompts", applyInstantPrompts)

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

state.on("AutoRewards", function()
	rewards.sync()
end)
state.on("BlackScreen", function(value)
	setBlackScreen(value == true)
end)

state.on("LowerUsage", applyLowerUsage)

local function applyMoonJuiceFarm(v)
	if v == true then
		moonjuicefarm.start()
	else
		moonjuicefarm.stop()
	end
end

state.on("MoonJuiceFarm", applyMoonJuiceFarm)

-- The config sliders may already hold values restored by autoLoad, and their
-- callbacks ran before these subscriptions existed: replay them once.
applySellAt(state.get("SellAt"))
applySwingDelay(state.get("SwingDelay"))
applyFlySpeed(state.get("FlySpeed"))
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
-- restored state (e.g. Lower Usage was left on last session).
farm.sync()
esp.sync()
travel.sync()
rewards.sync()
rewards.start()
-- Hidden hold-to-mine: always on, no GUI control (user decision). Holding
-- left click swings the equipped pickaxe; see src/holdmine.luau.
holdmine.start()
-- Keybind auto-mine: F7 toggles continuous swings while a pickaxe is
-- equipped (hidden, toast reports state); see src/minekey.luau.
minekey.start()
-- Prompt auto-fire: F8 toggles 10x/s firing of the nearest in-range
-- ProximityPrompt (hidden, toast reports state); see src/promptkey.luau.
promptkey.start()
-- Off by default (user decision 2026-10-09): they play with the menu open and
-- want the game to look normal. Flip it on when the GPU is struggling.
if state.get("LowerUsage") == nil then
	state.set("LowerUsage", false)
else
	applyLowerUsage(state.get("LowerUsage"))
end
-- MoonJuice spawner: never auto-starts on a fresh boot, but an autoLoad
-- restore of ON is honored so a rejoin resumes spawning.
if state.get("MoonJuiceFarm") == true then
	applyMoonJuiceFarm(true)
end
-- Instant prompts on by default (they asked for it); the toggle seeds from
-- saved config when present, so a saved off stays off.
if state.get("InstantPrompts") == nil then
	state.set("InstantPrompts", true)
else
	applyInstantPrompts(state.get("InstantPrompts"))
end

-------------------------------------------------------------- live stats
task.spawn(function()
	local lastStatErrs: { [string]: boolean } = {}
	-- One guard per stat: a broken updater must not starve the ones after
	-- it (they shared a single pcall, so one throw froze every later stat
	-- at its initial value), and each unique failure is surfaced exactly
	-- once instead of spamming the console every cycle.
	local function update(what: string, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok then
			local msg = what .. ": " .. tostring(err)
			if not lastStatErrs[msg] then
				lastStatErrs[msg] = true
				warn("[Paralyz] live stats - " .. msg)
			end
		end
	end
	while true do
		if window.unloaded then
			break
		end
		if creditsStat then
			update("credits", function()
				creditsStat:Set(util.credits())
			end)
		end
		if juiceStat then
			update("juice", function()
				juiceStat:Set(util.juiceValue())
			end)
		end
		if farmStat then
			update("farm", function()
				farmStat:Set(farm.isRunning() and farm.stats() or "idle")
			end)
		end
		if converterStat then
			update("converters", function()
				local list = util.converters()
				converterStat:Set(#list > 0 and table.concat(list, ", ") or "none built")
			end)
		end
		if sellStat then
			update("sell", function()
				-- Tier breakdown + which machines can eat it + where the
				-- round clock stands. Plain/ion are held by policy; only the
				-- leading anti run sells (oldest-first server semantics).
				local plain = util.plainJuiceCount()
				local ion = util.ionJuiceCount()
				local anti = util.antiJuiceCount()
				local tiers = {}
				if plain > 0 then
					table.insert(tiers, plain .. " plain")
				end
				if ion > 0 then
					table.insert(tiers, ion .. " ion")
				end
				if anti > 0 then
					table.insert(tiers, anti .. " anti")
				end
				local held = #tiers > 0 and table.concat(tiers, ", ") or "empty"
				local machines = {}
				if util.ionizerPrompt() then
					table.insert(machines, "ionizer")
				end
				if util.converterPrompt() then
					table.insert(machines, "converter")
				end
				local mach = #machines > 0 and table.concat(machines, "+") or "none"
				local cs = util.storyClock()
				local clock = string.format(
					"%d:%02d",
					math.floor(cs / 60),
					math.floor(cs % 60)
				)
				sellStat:Set(
					string.format(
						"%s | machines: %s | round %s%s",
						held,
						mach,
						clock,
						util.roundEndSoon() and " - DUMPING" or ""
					)
				)
			end)
		end
		if questStat then
			update("quests", function()
				questStat:Set(rewards.stats())
			end)
		end
		if machineStat then
			update("machines", function()
				-- Where each chain machine lives right now, so the Travel
				-- tab answers "is it built and where" without a teleport.
				local ion = util.ionizerPrompt()
				local conv = util.converterPrompt()
				local function where(prompt: ProximityPrompt?): string
					if not prompt then
						return "missing"
					end
					local planet = string.match(prompt:GetFullName(), "Planet(%d)")
					return planet and util.planetLabel("Planet" .. planet) or "?"
				end
				machineStat:Set("Ionizer: " .. where(ion) .. " | Converter: " .. where(conv))
			end)
		end
		if threatStat then
			update("threat", function()
				-- PlanetTracker warp countdowns: the most urgent active
				-- threat (same pick as the game's own progress bar).
				local text = "none incoming"
				local pt = workspace:FindFirstChild("PlanetTracker")
				if pt then
					local now = workspace:GetServerTimeNow()
					local bestName, bestEta, anyActive
					for _, c in ipairs(pt:GetChildren()) do
						if c:GetAttribute("WarpActive") == true then
							anyActive = c.Name
							local t = c:GetAttribute("WarpTime")
							local s = c:GetAttribute("WarpStart")
							if typeof(t) == "number" and typeof(s) == "number" and t > 0 then
								local eta = (s + t) - now
								if eta > 0 and (not bestEta or eta < bestEta) then
									bestName, bestEta = c.Name, eta
								end
							end
						end
					end
					if bestName then
						text = string.format(
							"%s in %d:%02d",
							bestName,
							math.floor(bestEta / 60),
							math.floor(bestEta % 60)
						)
					elseif anyActive then
						text = anyActive .. " active"
					end
				end
				threatStat:Set(text)
			end)
		end
		task.wait(2)
	end
end)

------------------------------------------------------------------ shutdown
shutdown = function()
	farm.stop()
	esp.stop()
	travel.stop()
	rewards.stop()
	holdmine.stop()
	instantprompts.stop()
	minekey.stop()
	promptkey.stop()
	noshake.stop()
	flystand.stop()
	hover.stop()
	safezone.stop()
	moonjuicefarm.stop()
	util.stopAim()
	util.stop() -- disconnect the round-end Text listener
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
		travel = travel,
		rewards = rewards,
		holdmine = holdmine,
		instantprompts = instantprompts,
		minekey = minekey,
		promptkey = promptkey,
		noshake = noshake,
		flystand = flystand,
		hover = hover,
		safezone = safezone,
		moonjuicefarm = moonjuicefarm,
		knowledge = knowledge,
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
