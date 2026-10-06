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

			-- Walk/fly to stand-off range before aiming: mining is close range.
			local dist = util.dist(root.Position, rock.Position)
			if dist > config.farm.aimDistance + 10 then
				-- Step the character toward the rock using root velocity so we do
				-- not need a path: open lunar terrain with noclip-friendly gaps.
				local dir = (rock.Position - root.Position).Unit
				root.CFrame = CFrame.lookAt(root.Position, Vector3.new(rock.Position.X, root.Position.Y, rock.Position.Z))
				local steps = math.min(6, math.ceil((dist - config.farm.aimDistance) / 20))
				for _ = 1, steps do
					if not running or not util.alive() then
						break
					end
					root.CFrame = root.CFrame + (dir * 8)
					task.wait(0.05)
				end
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

			local ok = util.aimAt(rock.Position)
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
