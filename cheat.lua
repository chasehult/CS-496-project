local Json = require("scripts/json")

if not Json then
    logger:print("You must run the setup script...\n")
    return
end

if emu == nil then
    logger:print("No game currently loaded...\n")
    return
end

--------
--- Notes: 
-- When searching ram for an value the value can be stored:
-- 	GBA stores memory in LITTLE ENDIAN
-- 	Stores in both IWRAM & EWRAM, some values may be stored in the cart or in the ROM itself
-- 	we need to figure out what types of numbers the processor operates on but we may need varients for signed vs unsign ints/byte/shorts etc
function find_addresses(value)
	-- Debugging output
	logger:print("searching for address\n")

	local found_addresses = {}

	-- Search everything (slow, sanity check)
	search_address_space_full(value, found_addresses, 0x02000000, 0x04000000)

	-- Search IWRAM
	search_address_space_full(value, found_addresses, 0x02000000, 0x0203FFF0)

	-- Search EWRAM 
	search_address_space_full(value, found_addresses, 0x03000000, 0x03007FF0)


	-- Debugging output
	for _, address in ipairs(found_addresses) do
		local out = string.format("found @%x\n", address)
		logger:print(out)
	end

	return found_addresses
end

function search_address_space_full(value, output_table, start_adr, end_adr)
	search_address_space(value, output_table, start_adr, end_adr, 8, read8)
	search_address_space(value, output_table, start_adr, end_adr, 16, read16)
	search_address_space(value, output_table, start_adr, end_adr, 32, read32)
end

function search_address_space(value, output_table, start_adr, end_adr, size, search_function)

	for i = start_adr, end_adr, size do
		local byte = search_function(i)
		if byte == value then
			output_table[#output_table + 1] = i
		end
	end
end

function read8(addr)
	return emu:read8(addr);
end

function read16(addr)
	return emu:read16(addr);
end

function read32(addr)
	return emu:read32(addr);
end
--------

local json = loadfile(script.dir .. "/scripts/json.lua")()

logger = console:createBuffer("stdout")

master = {}
guessed_values = {}
known_values = {}

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

function look_for(name, value)
    if known_values[name] ~= nil then
        local str = string.format("Address already found at %x\n", known_values[name]) 
        logger:print(str)
        return
    end

    local addresses = find_addresses(value)

    if guessed_values[name] == nil then
        guessed_values[name] = addresses
    end
    local old_guesses = guessed_values[name]

    local new_guesses = intersection(addresses, old_guesses)

    if #new_guesses == 0 then
        logger:print("Something went wrong...")
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

function save() 
    master[emu:getGameCode()] = master[emu:getGameCode()] or {}

    master[emu:getGameCode()].guessed = guessed_values
    master[emu:getGameCode()].known = known_values

    local f = io.open(script.dir .. "/data/saved.json", "w+")
    f:write(json.encode(master))
    f:close()

    logger:print("Saved!\n")
end

load_master()
