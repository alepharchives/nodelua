require "mailbox"

local function dump(o)
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

function main()
	while true do
		while true do
			local message = mailbox.next()
			if message == nil then break end
			if 'table' == type(message) then
				local pid = message["pid"]
				local msg = message.data
				if pid then
					mailbox.send(pid, msg)
				end
			end
		end
		coroutine.yield()
	end
end

main()
