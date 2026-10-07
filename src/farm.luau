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
