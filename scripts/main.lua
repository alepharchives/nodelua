
require "mailbox"

mailbox.async_id = 0
mailbox.async_callbacks = {}
local function sendasync(pid, msg, callback)
	local callback_id = mailbox.async_id + 1
	local address = mailbox.address()
	mailbox.async_id = callback_id
	mailbox.async_callbacks[callback_id] = callback;
	mailbox.send(pid, {sender={address, callback_id}, data={message=msg}} )
end
mailbox.sendasync = sendasync

function main()
	local inbox = {}
	local update_function = nil
	local shutdown_function = nil;

	local mail_sorter = {}
	function mail_sorter.mail(message) 
		table.insert(inbox, message.data) 
	end
	function mail_sorter.load(message) 
		package.path = message.path .. "/" .. message.module .. "/?.lua;" .. message.path .. "/" .. message.module .. "/?/init.lua"

		local behavior = assert(require(message.module))
		if( behavior ) then
			if( "function" == type(behavior.update) ) then
				update_function = behavior.update
			end
			if( "function" == type(behavior.shutdown) ) then
				shutdown_function = behavior.shutdown
			end
		end
	end
	function mail_sorter.reply(message)
		local callback_id = message.callback_id
		local reply = message.reply
		local callback = mailbox.async_callbacks[callback_id];
		mailbox.async_callbacks[callback_id] = nil;
		callback(reply);
	end

	while true do
		inbox = {}
		while true do
			local message = mailbox.next()
			if message == nil then break end

			-- check for certain types of message (load, kill, etc)
			-- save the message into a table to give the script
			mail_sorter[message.type](message)
		end

		-- run the script if we have one, giving it the messages
		if( update_function ) then
			assert(pcall(update_function, inbox))
		end

		-- somehow let the script send messages

		if( mailbox.shutting_down() ) then
			if( shutdown_function ) then 
				shutdown_function()
			end
			return;
		end

		coroutine.yield()
	end
end

main()
