require "mailbox"

function main()
	while true do
		print(mailbox.next())
		coroutine.yield()
	end
end

main()
