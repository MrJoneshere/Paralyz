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

	-- A titled text card. Rayfield Gen2's Stat:Set() asserts typeof == 'number',
	-- so a string stat throws every update and the element stays frozen at its
	-- initial value - anything that reports words (farm phase, quest summary,
	-- threat ETA) belongs here instead.
	function ui.text(tab, props)
		return guard("text", function()
			return tab:CreateText(props)
		end)
	end

	return ui
end
