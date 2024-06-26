-------------------------------------------------------------------------------
-- Required
-------------------------------------------------------------------------------

local json = require("scripts/json")

-------------------------------------------------------------------------------
-- Location Type
-------------------------------------------------------------------------------

Location = {
	start = 0,
	size = 0,
	be = false,

	stop = function(self)
		return self.start + self.size / 8
	end,

    __eq = function(self, other)
        return self.start == other.start and self.size == other.size and self.be == other.be
    end,

	equals = function(self, other)
		if self.be == true then
			return self.start == other.start
		elseif self.be == false then
			return self:stop() == other:stop()
		end
	end,

	overlaps = function(self, other)
		if self.start == other.start or self:stop() == other:stop() then
			return true
		end
		if self.start > other.start then
			return self.start <= other:stop()
		else
			return other.start <= self:stop()
		end
	end,
}


function Location:new(o)
	memout:print(string.format("making new location for %x", o.start))

	if o.start == nil or o.size == nil or o.be == nil then
        print(o.start, o.size, o.be)
	    print("invalid o")
	    return nil, "Invalid object"
    end

	setmetatable(o, self)
	self.__index = self
	return o
end

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
	local function bound(...)
		return obj[method](obj, ...)
	end

	return bound
end

function dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k, v in pairs(o) do
			if type(k) ~= 'number' then k = '"' .. k .. '"' end
			s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
		end
		return s .. '} '
	else
		return tostring(o)
	end
end

function rev_bytes(int, size) 
    local new_int = 0
    for i = 1, size / 8 do
        new_int = (new_int << 8) + (int & 0xff)
        int = int >> 8
    end
    return new_int
end

function pair_len(table)
	if table == nil then
		return 0
	end

	local length = 0

	for _, _ in pairs(table) do
		length = length + 1
	end

	return length
end

function map(func, table)
    out = {}
    for k, v in pairs(table) do
        out[k] = func(v)
    end
    return out
end

-------------------------------------------------------------------------------
-- Globals
-------------------------------------------------------------------------------

if logger == nil then
	logger = console:createBuffer("main")
end
if memout == nil then
	memout = console:createBuffer("memory")
end
if valout == nil then
	valout = console:createBuffer("values")
end
if pinout == nil then
	pinout = console:createBuffer("pinned")
end

master = {}
guessed_values = {}
known_values = {}
pinned_values = {}

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
	memout:print(string.format("Searching WRAM for addresses containing %d...\n", value))

	local found_locations = {}

	-- Search memory addresses
	for _, span in pairs(MEM_LOCATIONS) do
		search_address_space_full(value, found_locations, span)
	end

	-- Debugging output
	for _, address in pairs(found_locations) do
		local out = string.format("Found %d @%x [%d]\n", value, address.start, address.size)
		memout:print(out)
	end

	found_locations = dealias_locations(found_locations)

	-- Debugging output
	memout:print("Dealiased locations:\n")
	for _, address in pairs(found_locations) do
		local out = string.format("%d @%x [%d]\n", value, address.start, address.size)
		memout:print(out)
	end

	memout:print("Search completed.\n")

	return found_locations
end

function search_address_space_full(value, output_table, addr_span)
    search_address_space(value, output_table, addr_span, 32, false)
    search_address_space(value, output_table, addr_span, 32, true)
    search_address_space(value, output_table, addr_span, 16, false)
    search_address_space(value, output_table, addr_span, 16, true)
    search_address_space(value, output_table, addr_span, 8, false)
end

function search_address_space(value, output_table, addr_span, size, be)
    if be then value = rev_bytes(value, size) end
	for address = addr_span.start, (addr_span.stop - size), 1 do
		if RW_SIZES[size].read(address) == value then
			output_table[#output_table + 1] = Location:new{start=address, size=size, be=be}
		end
	end
end

function dealias_locations(locations)
	local overlap_sets = {}

	for index, location in ipairs(locations) do

		local overlaps = { [1] = location }
		locations[index] = nil

		for other_index, other_location in ipairs(locations) do
			if location:overlaps(other_location) then
				table.insert(overlaps, other_location)
				locations[other_index] = nil
			end
		end

		table.insert(overlap_sets, overlaps)
	end

	local locations = {}

	for index, overlap_set in pairs(overlap_sets) do
		local best_address = get_minimal_overlapping_address(overlap_set)
		table.insert(locations, best_address)
	end

	return locations;
end

function get_minimal_overlapping_address(overlapping_locations)
	local smallest_index = -1
	local smallest_size = 100000
	local minimal_location = nil

	for index, location in pairs(overlapping_locations) do
		if location.size < smallest_size then
			smallest_index = index
			smallest_size = location.size
			minimal_location = location
		end
		if location.size == smallest_size and location.start < minimal_location.start then
			minimal_location = location
		end
	end

	return minimal_location
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
		local str = string.format("Address already found at %x\n", known_values[name].start)
		logger:print(str)
		return
	end

	local addresses = find_addresses(value)

	if guessed_values[name] == nil then
		guessed_values[name] = addresses
	end
	local old_guesses = guessed_values[name]

	local new_guesses = intersection(addresses, old_guesses)

	if pair_len(new_guesses) == 0 then
		logger:print("Unable to find new value in memory. Not updating filtered addresses.\n")
		return
	end

	if pair_len(new_guesses) == 1 then
		local address = new_guesses[next(new_guesses)]
		local hex = string.format("Address for %s found at %x\n", name, address.start)
		logger:print(hex)
		known_values[name] = address
		guessed_values[name] = nil
	else
		local str = string.format("Found %d possibilities\n", #new_guesses)
		logger:print(str)
		guessed_values[name] = new_guesses
	end
end

-- Debug / Demo function that simply searches memory for the desired value and discards the results
function look(value)
	if not is_game_loaded() then
		logger:print("Please load a valid game before attempting to search memory.\n")
		return
	end

	find_addresses(value)
end

function reset_search(name)
	guessed_values[name] = nil
end

function clear_found(name)
	known_values[name] = nil
end

function is_known(query_value_name)
	return known_values[query_value_name] ~= nil
end

function print_unknown_value_name_error(value_name)
	logger:print(
		string.format("No memory address associated with %s."
			.. " Please use 'look_for(\"%s\", CURRENT_VALUE)' to populate known addresses.\n",
			value_name, value_name)
	)
end

function tick_found_values_display()
	valout:clear()

	if pair_len(known_values) == 0 then
		valout:print("Found values:\n")
		valout:print("No known values. Use 'look_for(value_name, current_value)' to begin searching for some...\n")
		return
	end

	valout:print(string.format("Found values (%d):\n", pair_len(known_values)))
	valout:print("NAME\tADDRESS[SIZE]\t\tVALUE\n")

	for value_name, value_location in pairs(known_values) do
		local name = value_name
		local address = value_location.start
		local size = value_location.size
		local current_value = RW_SIZES[size].read(address)

		valout:print(string.format("%s\t0x%x [%d]\t\t%d\n",
			name,
			address,
			size,
			current_value))
	end
end

-------------------------------------------------------------------------------
-- Mutating
-------------------------------------------------------------------------------

function set_value(name, new_value)
	if not is_known(name) then
		print_unknown_value_name_error(name)
		return
	end

	local address = known_values[name].start
	local write_size = known_values[name].size
    if known_values[name].be then new_value = rev_bytes(new_value) end

	memout:print(string.format("Writing %d bytes to %x\n", write_size, address))
	RW_SIZES[write_size].write(address, new_value)
end

function force_size(name, size)
    if RW_SIZES[size] == nil then
        logger:print("Invalid size\n")
        return
    end

    known_values[name].size = size
end

-------------------------------------------------------------------------------
-- Mutating -- Pinning
-------------------------------------------------------------------------------

function pin_value(value_name, new_value)
	if not is_known(value_name) then
		print_unknown_value_name_error(value_name)
		return
	end

	pinned_values[value_name] = new_value
end

function unpin_value(value_name)
	if not is_known(value_name) then
		print_unknown_value_name_error(value_name)
		return
	end
	if not is_pinned(value_name) then
		logger:print(string.format("%s if not a pinned value. Unable to unpin.", value_name))
		return
	end

	pinned_values[value_name] = nil
end

function unpin_all()
	for name, value in pairs(pinned_values) do
		pinned_values[name] = nil
	end
end

function is_pinned(query_value_name)
	return pinned_values[query_value_name] ~= nil
end

function tick_pinned_values()
	for value_name, desired_value in pairs(pinned_values) do
		set_value(value_name, desired_value)
	end

	tick_pinned_display()
end

function tick_pinned_display()
	pinout:clear()

	pinout:print("Pinned values:\n")

	if pair_len(pinned_values) == 0 then
		pinout:print("No pinned values. Use 'pin_value(value_name, value)' to pin found values...")
		return
	end

	pinout:print("NAME\t\tVALUE\n")
	for pinned_value, desired_value in pairs(pinned_values) do
		pinout:print(string.format("%s\t\t%d(0x%x)\n", pinned_value, desired_value, desired_value))
	end
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
		guessed_values = map(bind(Location, "new"), master[emu:getGameCode()].guessed)
		known_values = map(bind(Location, "new"), master[emu:getGameCode()].known)
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
callbacks:add("frame", tick_pinned_values)
callbacks:add("frame", tick_found_values_display)
