--!strict
-- Paralyz / src/farm.luau
-- Auto-farm: aim at a rock, swing the pickaxe, collect MoonJuice, sell.
--
-- Confirmed behaviour of the game:
--   1. Aim the camera so Mouse.Target is a part in a planet's Rocks folder.
--   2. Tool:Activate() sends the swing.
--   3. The server answers on Events.Pickaxe (OnClientEvent) and the game's own
--      PickaxeController fires back FireServer(mouse.Target).
--   4. A MoonJuice Tool with a Credits NumberValue shows up in the Backpack.
--   5. Events.SellMoonjuice:FireServer(count, true) sells everything.
--
-- Testing rule: tests pass { maxCycles = 5 }. The GUI never sets maxCycles.

return function(deps)
	local config = deps.config
	local state = deps.state
	local util = deps.util

	local farm = {}

	local running = false
	local thread: thread? = nil
	local cycles = 0
	local sold = 0
	local lastReport = 0

	local function report(msg: string)
		if os.clock() - lastReport > 2 then
			lastReport = os.clock()
			util.notify("Auto-Farm", msg)
		end
	end

	local function runLoop(opts)
		local maxCycles = opts and opts.maxCycles
		cycles = 0

		while running do
			if maxCycles and cycles >= maxCycles then
				util.notify("Auto-Farm", "test cap reached (" .. cycles .. " cycles)")
				break
			end

			if not util.alive() then
				task.wait(1)
				continue
			end

			-- Sell whatever we are holding first so the stack never fills up.
			if util.juiceCount() >= config.farm.sellAt then
				local count = util.sellAll()
				if count > 0 then
					sold += count
					report(string.format("sold %d stacks (total sold %d)", count, sold))
				end
				task.wait(0.4)
				continue
			end

			local rock = util.nearestRock()
			if not rock then
				-- Waves: an empty folder means wait, not broken.
				task.wait(config.farm.noRockDelay)
				continue
			end

			local root = util.root()
			if not root then
				task.wait(0.5)
				continue
			end

			-- Rocks are huge - the "MarsRocks" union is 63 studs across - so the
			-- stand-off must be measured from the rock's EDGE, not its centre.
			-- Standing a fixed distance from the centre parks the character
			-- inside the rock, and a swing fired from inside the geometry never
			-- mines: the server answers the remote but nothing breaks.
			local half = math.max(rock.Size.X, rock.Size.Y, rock.Size.Z) / 2
			local standOff = half + config.farm.edgeMargin
			local dist = util.dist(root.Position, rock.Position)

			if dist > standOff + 6 then
				-- Keep the side we are already on and hop straight there. The
				-- game has no movement check, and creeping 8 studs at a time
				-- across a 300-stud field spends the whole wave walking.
				local side = root.Position - rock.Position
				side = if side.Magnitude > 1 then side.Unit else Vector3.new(0, 0, 1)
				root.CFrame = CFrame.new(rock.Position + side * standOff + Vector3.new(0, 6, 0))
				task.wait(0.35)
				continue
			end

			local pickaxe = util.bestPickaxe()
			if not pickaxe then
				util.notify("Auto-Farm", "no pickaxe found")
				task.wait(3)
				continue
			end
			if not util.equip(pickaxe) then
				task.wait(1)
				continue
			end

			-- Camera stand-off is wider still, so the view starts outside the
			-- rock and the ray through the mouse lands on its surface.
			local ok = util.aimAt(rock.Position, half + 40)
			if not ok then
				task.wait(0.3)
				continue
			end

			-- Swing until this rock is gone, but never more than a handful of
			-- times so a stale rock reference cannot spin forever - and never
			-- past a test cap, so a capped run cannot overshoot it.
			local swings = 0
			while running
				and rock.Parent
				and swings < 5
				and (not maxCycles or cycles < maxCycles)
			do
				pcall(function()
					pickaxe:Activate()
				end)
				swings += 1
				cycles += 1
				task.wait(config.farm.swingDelay)
			end

			util.stopAim()
			task.wait(0.1)
		end

		util.stopAim()
		running = false
	end

	-- opts: { maxCycles = n } for tests. Shipped GUI calls farm.start() bare.
	function farm.start(opts)
		if running then
			return false
		end
		running = true
		cycles = 0
		thread = task.spawn(runLoop, opts)
		return true
	end

	function farm.stop()
		running = false
		util.stopAim()
	end

	function farm.isRunning(): boolean
		return running
	end

	function farm.stats(): string
		return string.format("cycles=%d sold=%d running=%s", cycles, sold, tostring(running))
	end

	-- Called by the menu whenever the AutoFarm toggle or its settings change.
	function farm.sync()
		if state.enabled("AutoFarm") then
			farm.start()
		else
			farm.stop()
		end
	end

	return farm
end
