local mgba_memsearch = {}

local tb = console:createBuffer("memsearch_out")

function mgba_memsearch.find_addresses(value)
	tb:print(string.format("Searching WRAM for addresses containing %d...\n", value))

	local found_addresses = {}

	-- Search IWRAM
	search_address_space_full(value, found_addresses, 0x02000000, 0x0203FFF0)

	-- Search EWRAM 
	search_address_space_full(value, found_addresses, 0x03000000, 0x03007FF0)

	-- Debugging output
	for _, address in ipairs(found_addresses) do
		local out = string.format("Found %d @%x\n", value, address)
		tb:print(out)
	end
	
	tb:print("Search completed.")

	return found_addresses
end

function search_address_space_full(value, output_table, start_adr, end_adr)
	search_address_space(value, output_table, start_adr, end_adr, 8, read8)
	search_address_space(value, output_table, start_adr, end_adr, 16, read16)
	search_address_space(value, output_table, start_adr, end_adr, 32, read32)
	search_address_space(value, output_table, start_adr, end_adr, 16, read16_BE)
	search_address_space(value, output_table, start_adr, end_adr, 32, read32_BE)
end

function search_address_space(value, output_table, start_adr, end_adr, size, search_function)
	for i = start_adr, (end_adr - size), 1 do
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

function read16_BE(addr)
	return (emu:read8(addr) << 8) | (emu:read8(addr + 1)) 
end

function read32_BE(addr)
	return read16_BE(addr + 2) << 16 | read16_BE(addr)
end 

function read32(addr)
	return emu:read32(addr);
end

return mgba_memsearch
