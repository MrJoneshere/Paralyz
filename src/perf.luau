--!strict
-- Paralyz / src/perf.luau
-- Lower Usage mode: the cheapest safe way to keep a struggling GPU alive.
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

	-- Turns Lower Usage on or off. Returns a short report string.
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
