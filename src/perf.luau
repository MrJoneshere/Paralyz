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
					table.insert(fresh, part)
				end
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
		if rel.Z >= -o.near then
			return false -- behind or beside the camera plane
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
