-------------------------------------------------------------------------------
-- Required
-------------------------------------------------------------------------------

local json = require("scripts/json")

-------------------------------------------------------------------------------
-- Utils
-------------------------------------------------------------------------------

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
            table.insert(intersect, v)
        end
    end
    return intersect
end

function bind(obj, method)
    function bound(...) 
        return obj[method](obj, ...)
    end
    return bound
end

function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end


-------------------------------------------------------------------------------
-- Globals
-------------------------------------------------------------------------------

logger = console:createBuffer("stdout")
master = {}
guessed_values = {}
known_values = {}
--local json = loadfile(script.dir .. "/scripts/json.lua")

RW_SIZES = {
    [8] = {
        read = bind(emu, "read8"),
        write = bind(emu, "write8")
    },
    [16] = {
        read = bind(emu, "read16"),
        write = bind(emu, "write16")
    },
    [32] = {
        read = bind(emu, "read32"),
        write = bind(emu, "write32")
    }
}

MEM_LOCATIONS = {
    IWRAM = {
        start = 0x02000000,
        stop = 0x0203FFF0
    },
    EWRAM = {
        start = 0x03000000,
        stop = 0x03007FF0
    }
}

-------------------------------------------------------------------------------
-- Code
-------------------------------------------------------------------------------

function on_game_start()
    -- Load existing data for this game
    load_master()
end

-------------------------------------------------------------------------------
-- Memory Search
-------------------------------------------------------------------------------

function find_addresses(value)
    logger:print(string.format("Searching WRAM for addresses containing %d...\n", value))

    local found_addresses = {}

    for _, span in pairs(MEM_LOCATIONS) do
        search_address_space_full(value, found_addresses, span)
    end

    -- Debugging output
    for _, address in pairs(found_addresses) do
        local out = string.format("Found %d @%x\n", value, address)
        logger:print(out)
    end
    
    logger:print("Search completed.\n")

    return found_addresses
end

function search_address_space_full(value, output_table, span)
    search_address_space(value, output_table, span, 32)
    search_address_space(value, output_table, span, 16)
    search_address_space(value, output_table, span, 8)
    -- TODO: Support Big Endian
end

function search_address_space(value, output_table, span, size, be)
    for address = span.start, (span.stop - size), 1 do
        if RW_SIZES[size].read(address) == value then
            table.insert(output_table, address)
        end
    end
end

-------------------------------------------------------------------------------
-- Filtering
-------------------------------------------------------------------------------

function look_for(name, value)
	if not is_game_loaded() then
		logger:print("Please load a valid game before attempting to search memory.\n")
		return
	end

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
		logger:print("Unable to find new value in memory. Not updating filtered addresses.\n")
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
        guessed_values[name] = new_guesses
	end


end

-------------------------------------------------------------------------------
-- Mutating
-------------------------------------------------------------------------------

function set_value(name, write_mode, new_value)
	if known_values[name] == nil then 
		logger:print(
			string.format("No memory address associated with %s."
                       .. " Please use 'look_for(\"%s\", CURRENT_VALUE)' to populate known addresses.\n",
				          name, name)
			)
		return
	end 

	if RW_SIZES[write_mode] == nil then
	   logger:print("Please enter a valid write mode (8/16/32)\n")
	   return
	end

	local address = known_values[name]
    logger:print(string.format("Writing %d bytes to %x\n", write_mode, address))
	RW_SIZES[write_mode].write(address, new_value)
end

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

on_game_start()
callbacks:add("start", on_game_start)
