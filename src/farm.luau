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
