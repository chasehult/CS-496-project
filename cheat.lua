-------------------------------------------------------------------------------
-- Required
-------------------------------------------------------------------------------

local json = require("scripts/json")
local emu_ms = require("scripts/mgba_memsearch")

-------------------------------------------------------------------------------
-- Globals
-------------------------------------------------------------------------------

logger = console:createBuffer("stdout")
master = {}
guessed_values = {}
known_values = {}
--local json = loadfile(script.dir .. "/scripts/json.lua")

-------------------------------------------------------------------------------
-- Code
-------------------------------------------------------------------------------

function on_game_start()
	-- Load existing data for this game
	load_master()
end

-------------------------------------------------------------------------------
-- Filtering
-------------------------------------------------------------------------------

function look_for(name, value)
	if not is_game_loaded() then
		logger:print("Please load a valid game before attempting to search memory.")
		return
	end

	if known_values[name] ~= nil then
		local str = string.format("Address already found at %x\n", known_values[name])
		logger:print(str)
		return
	end

	local addresses = emu_ms.find_addresses(value)

	if guessed_values[name] == nil then
		guessed_values[name] = addresses
	end
	local old_guesses = guessed_values[name]

	local new_guesses = intersection(addresses, old_guesses)

	if #new_guesses == 0 then
		logger:print("Unable to find new value in memory. Not updating filtered addresses.")
		return
	end

	if #new_guesses == 1 then
		local address = new_guesses[next(new_guesses)]
		local hex = string.format("Address found at %x\n", address)
		logger:print(hex)
		known_values[name] = address
		guessed_values[name] = nil
	else
		local str = string.format("Found %d possibilities\n", #new_guesses)
		logger:print(str)
	end
end

function contains(arr, val)
	for _, v in ipairs(arr) do
		if v == val then
			return true
		end
	end
	return false
end

function intersection(arr1, arr2)
	local intersect = {}
	for _, v in ipairs(arr1) do
		if contains(arr2, v) then
			intersect[#intersect + 1] = v
		end
	end
	return intersect
end

-------------------------------------------------------------------------------
-- Mutating
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- Persistance
-------------------------------------------------------------------------------

function load_master()
	local f = io.open(script.dir .. "/data/saved.json", "r")
	if f == nil then
		local str = string.format("Loading %s for the first time (no save found)\n", emu:getGameTitle())
		logger:print(str)
		return
	end

	local str = string.format("Loading saved data from %s\n", emu:getGameTitle())
	logger:print(str)

	local data = f:read("*a")
	f:close()

	master = json.decode(data)

	if master[emu:getGameCode()] ~= nil then
		guessed_values = master[emu:getGameCode()].guessed
		known_values = master[emu:getGameCode()].known
	end
end

function save()
	master[emu:getGameCode()] = master[emu:getGameCode()] or {}

	master[emu:getGameCode()].guessed = guessed_values
	master[emu:getGameCode()].known = known_values

	local f = io.open(script.dir .. "/data/saved.json", "w+")
	f:write(json.encode(master))
	f:close()

	logger:print("Saved!\n")
end

-------------------------------------------------------------------------------
-- Emulator
-------------------------------------------------------------------------------

function is_game_loaded()
	return emu ~= nil
end

-------------------------------------------------------------------------------
-- Entry Point 
-------------------------------------------------------------------------------

-- Ensure JSON was loaded properly
if not json then
	logger:print("You must run the setup script...\n")
	return
end

-- Ensure memory search was loaded properly
if not emu_ms then
	logger:print("Missing required file 'scripts/mgba_memsearch.lua'.")
	return
end

callbacks:add("start", on_game_start)
