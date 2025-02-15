local source = {}
local cmp = require("cmp")
local v = vim

function source:new()
	local s = setmetatable({}, { __index = source })
	s.accounts = nil
	s.payees = nil
	return s
end

function source:get_keyword_pattern()
	return [[\(.\+:\|\d\{4}-\d\{2}-\d\{2}\|[.\+:\)]]
end

-- Remove space at the beginning of the line
local ltrim = function(s)
	return s:match("^%s*(.*)")
end

-- Remove potential squarred brackets
local sbtrim = function(s)
	return s:match("[(.*)]")
end

-- Remove beginning date
local trim_date = function(s)
	return s:match("^%s*%d+-%d+-%d+ [%s*]*(.*)")
end

local split = function(str, sep)
	local t = {}
	for s in string.gmatch(str, "([^" .. sep .. "]+)") do
		table.insert(t, s)
	end
	return t
end

local get_accounts = function(account_path)
	local openPop = assert(io.popen(v.b.hledger_bin .. " accounts -f " .. account_path))
	local output = openPop:read("*all")
	openPop:close()
	local t = split(output, "\n")

	local accounts = {}
	for _, s in pairs(t) do
		table.insert(accounts, {
			label = s,
			kind = cmp.lsp.CompletionItemKind.Property,
		})
	end

	return accounts
end

local get_payees = function(account_path)
	local openPop = assert(io.popen(v.b.hledger_bin .. " payees -f " .. account_path))
	local output = openPop:read("*all")
	openPop:close()
	local t = split(output, "\n")

	local payees = {}
	for _, s in pairs(t) do
		table.insert(payees, {
			label = s,
			kind = cmp.lsp.CompletionItemKind.Operator,
		})
	end

	return payees
end

function source:complete(request, callback)
	-- Check filetype
	if v.bo.filetype ~= "ledger" then
		callback()
		return
	end

	-- Get binary path
	if v.fn.executable("hledger") == 1 then
		v.b.hledger_bin = "hledger"
	elseif v.fn.executable("ledger") == 1 then
		v.b.hledger_bin = "ledger"
	else
		v.api.nvim_echo({
			{ "cmp_hledger", "ErrorMsg" },
			{ " " .. "Can't find hledger or ledger" },
		}, true, {})
		callback()
		return
	end

	-- Retrieve filename
	local account_path = v.api.nvim_buf_get_name(0)
	if not self.accounts then
		self.accounts = get_accounts(account_path)
	end

	if not self.payees then
		self.payees = get_payees(account_path)
	end

	local input = trim_date(request.context.cursor_before_line)

	if input then
		input = input:lower()
		local payees = {}
		for _, item in ipairs(self.payees) do
			if v.startswith(item.label:lower(), input) then
				table.insert(payees, item)
			end
		end
		callback(payees)
	else
		local prefix_mode = false
		input = ltrim(request.context.cursor_before_line):lower()
		local virtual_input = sbtrim(input)
		if virtual_input ~= nil then
			input = virtual_input
		end
		local prefixes = split(input, ":")
		local pattern = ""

		for i, prefix in ipairs(prefixes) do
			if i == 1 then
				pattern = string.format("%s[%%w%%-]*", prefix:lower())
			else
				pattern = string.format("%s:%s[%%w%%-]*", pattern, prefix:lower())
			end
		end
		if #prefixes > 1 and pattern ~= "" then
			prefix_mode = true
		end

		local accounts = {}
		for _, item in ipairs(self.accounts) do
			if prefix_mode then
				if string.match(item.label:lower(), pattern) then
					table.insert(accounts, {
						word = item.label,
						label = item.label,
						kind = item.kind,
						textEdit = {
							filterText = input,
							newText = item.label,
							range = {
								start = {
									line = request.context.cursor.row - 1,
									character = request.offset - string.len(input),
								},
								["end"] = {
									line = request.context.cursor.row - 1,
									character = request.context.cursor.col - 1,
								},
							},
						},
					})
				end
			else
				if v.startswith(item.label:lower(), input) then
					table.insert(accounts, item)
				end
			end
		end
		callback(accounts)
	end
end

-- return source
require("cmp").register_source("ledger", source)
