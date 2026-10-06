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
