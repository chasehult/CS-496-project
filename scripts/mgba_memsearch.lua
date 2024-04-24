local mgba_memsearch = {}

local tb = console:createBuffer("memsearch_out")

function mgba_memsearch.find_addresses(value)
	-- Debugging output
	tb:print("searching for addresses...\n")

	local found_addresses = {}

	-- Search everything (slow, sanity check, REMOVEME)
	-- search_address_space_full(value, found_addresses, 0x02000000, 0x04000000)

	-- Search IWRAM
	search_address_space_full(value, found_addresses, 0x02000000, 0x0203FFF0)

	-- Search EWRAM 
	search_address_space_full(value, found_addresses, 0x03000000, 0x03007FF0)

	-- Debugging output
	for _, address in ipairs(found_addresses) do
		local out = string.format("found @%x\n", address)
		tb:print(out)
	end

	return found_addresses
end

local function search_address_space_full(value, output_table, start_adr, end_adr)
	search_address_space(value, output_table, start_adr, end_adr, 8, read8)
	search_address_space(value, output_table, start_adr, end_adr, 16, read16)
	search_address_space(value, output_table, start_adr, end_adr, 32, read32)
	search_address_space(value, output_table, start_adr, end_adr, 16, read16_BE)
	search_address_space(value, output_table, start_adr, end_adr, 32, read32_BE)
end

local function search_address_space(value, output_table, start_adr, end_adr, size, search_function)
	for i = start_adr, (end_adr - size), 1 do
		local byte = search_function(i)
		if byte == value then
			output_table[#output_table + 1] = i
		end
	end
end

-- no
local function to_signed(value)
    if n >= 2 ^ 31 then
        return n - 2 ^ 32
    end
    return n
end 

local function read8(addr)
	return emu:read8(addr);
end

local function read16(addr)
	return emu:read16(addr);
end

local function read16_BE(addr)
	return (emu:read8(addr) << 8) | (emu:read8(addr + 1)) 
end

local function read32_BE(addr)
	return read16_BE(addr + 2) << 16 | read16_BE(addr)
end 

local function read32(addr)
	return emu:read32(addr);
end

local function a()
	find_addresses(10)
end

return mgba_memsearch
