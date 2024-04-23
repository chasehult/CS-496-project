MAX_ADDRESS = 10000000

tb = console:createBuffer("test-output")


function find_addresses(value)
	tb:print("searching for address\n")

	local found_addresses = {}

	--- Search VRAM
	search_address_space_full(value, found_addresses, 0x06000000, 0x07000000)

	--- TODO: Search other addressess + map addresses based on loaded cart

	for _, address in ipairs(found_addresses) do
		local out = string.format("found @%x\n", address)
		tb:print(out)
	end
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

function a()
	find_addresses(10)
end

function poll_demo()
	print("poll active!")
	-- tb:print("poll!")
	-- emu:read32(0x0E000FF8)
end

-- core:read16(0)

demo = callbacks:add("frame", poll_demo)
-- callbacks:remove(demo)
