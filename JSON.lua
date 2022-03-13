local JSON = {}

function deparseString(str, args)
	-- returns lua string
	-- pre
	assert(type(str) == 'string', 'bad arg #1, not string' .. debug.traceback())
	assert(type(args) == 'table', 'bad arg #2, not table')
	local typeArgs = getTableType(args);
	assert(typeArgs == 'dictionary', 'bad arg #2, not dictionary, got' .. typeArgs)
	local stringType = args.stringType
	assert(stringType == 'single' or stringType == 'multiLined', 'arg2.stringType is invalid, got' .. tostring(stringType))

	if stringType == 'single' then
		local token = args.token
		assert(token == '"' or token == "'", 'bad token')
		args.beginToken = token
		args.endToken = token
	elseif stringType == 'multiLined' then
		local equalSignLength = args.equalSignLength or 0

		assert(type(equalSignLength) == 'number', 'got bad type for equalsignlength')
		assert(equalSignLength >= 0, 'equalSignLength out of range, smaller than 0')
		assert(equalSignLength % 1 == 0, 'not an integer')

		args.beginToken = '[' .. ('='):rep(equalSignLength) .. '['
		args.endToken =   ']' .. ('='):rep(equalSignLength) .. ']'
	else
		error'how'
	end

	-- main
	local result = args.beginToken

	for i = 1, #str do
		local char = str:sub(i, i)

		if stringType == 'single' then
			char = 
				char == args.beginToken and '\\' .. args.beginToken or -- ', "
				char == '\n' 			and '\\n' 					or -- \n
				char == '\\' 			and '\\\\'					or -- \
				char == '\t' 			and '\\t'					or
				-- \t
				char
		elseif stringType == 'multiLined' then
			-- this v
			-- ]====]
			if char == ']' and str:sub(i - #args.beginToken + 1, i) == args.endToken then
				char = '\\]'
			end
		end

		result = result .. char
	end

	result = result .. args.endToken

	return result
end

function getLuaStringInfo(str)
	-- returns a dictionary, stating if the given arg's type of string, the content and string token
	
	-- pre
	assert(type(str) == 'string', 'not a string')

	-- main
	local result = {}

	local firstCharacter = str:sub(1,1)
	local isSingleLined = firstCharacter == '"' or firstCharacter == "'"

	result.stringType = isSingleLined and 'single' or 'multiLined'

	-- main
	--  check the first characters,
	if firstCharacter == '"' or firstCharacter == "'" and not str:find('\n')then
		-- one lined string
		result.content = str:sub(2, #str - 1)
		result.beginToken = firstCharacter
	elseif firstCharacter == '['then
		-- mutlilined string
		local openBracketPos = str:find('%[', 2)
		if openBracketPos then
			local equalSignLength = openBracketPos - 2
			local equalSignStr = ('='):rep(equalSignLength)

			local beginToken, endToken = 
				'[' .. equalSignStr .. '[',
				']' .. equalSignStr .. ']' 
			
			if 
				str:sub(1,openBracketPos)		    == beginToken and
				str:sub(#str - 1 - equalSignLength) == endToken   then

				result.content = str:sub(openBracketPos + 1, #str - equalSignLength - 2)
				result.beginToken = beginToken
				result.endToken = endToken
			end
		end
	end

	-- check if content exists, if not, then it's not a string
	if not result.content then
		result.stringType = 'not a string'
	end

	-- check if endToken exists and if beginToken exists, if beginToken exists but endToken does not, then it suggests that endToken is the same as beginToken
	if result.beginToken and not result.endToken then
		result.endToken = result.beginToken
	end

	-- post
	assert(result.stringType == 'not a string' or result.stringType == 'single' or result.stringType == 'multiLined', 'weird error')
	return result
end

function parseString(str)
	-- pre
	assert(type(str) == "string")
	local info = getLuaStringInfo(str)
	assert(info.stringType ~= 'not a string', 'given string isn\'t format suitable. string=|' .. str .. '|')

	-- main
	local result = ''
	
	local content = info.content
	local i = 0

	-- f
	local function get(a, b)
		b = b or (a and #content) or i
		a = a or i
		return content:sub(a, b)
	end

	local function lGet(a, b)
		assert(a)

		return get(i + a, i + (b or a))
	end

	local function addToResult(a)
		a = a or get()
		result = result .. a
	end

	local function updateI(a)
		i = i + (a or 1)
	end

	local function lPrint()
		print('GOT LPRINT:')
		for j = -5, 5 do
			print('[i=' .. (i + j) .. ', offset=' .. j .. '] = ' .. lGet(j))
		end
	end

	local function lError(msg)
		for i = -5, 5 do
			print('[' .. i .. ']=' .. lGet(i))
		end
		error(msg)
	end

	-- loop
	while true do
		updateI()

		local char = get()

		if char == ''then
			-- end
			break
		elseif char == '\\' then
			updateI()
			if info.stringType == 'single' then
				-- escape seqeuence, works for single line strings, atm
				local char2 = tostring(get())
				
				if char2 == info.beginToken or char2 == '\\' then
					-- regular characters that have escape sequences for some reason
					addToResult()
				elseif char2:match('%l') and ('abfnrtv'):match(char2) then
					-- escape sequences where the result won't give what is expected
					addToResult(
						({
							a = '\a';
							b = '\b';
							f = '\f';
							n = '\n';
							r = '\r';
							t = '\t';
							v = '\v'
						})[('abfnrtv'):match(char2)]
					)
				elseif tonumber(char2) then
					-- handle ES bytes, possible chain can occur, give it it's own while loop
					local bytes = {}

					local onESChain = true

					-- iterating per byte
					while onESChain do
						local numRep = ''

						-- iterating per escape sequence
						for _ = 1, 3 do
							local char = get()

							-- check if the current character is a number
							if tonumber(char) then
								numRep = numRep .. char
								updateI()
							else
								-- otherwise, check if the current character is a \ and if the 
								-- next character is a number, if not then break the while loop

								-- regardless, break the for loop
								lPrint()
								local isEscapeSequence = char == '\\'
								local continueESByte = not not tonumber(lGet(1))
								onESChain =  isEscapeSequence and continueESByte

								updateI(onESChain and 1 or -1)

								break
							end
						end

						if #numRep > 0 then
							table.insert(bytes, tonumber(numRep))
						end
					end
					
					addToResult(string.char(unpack(bytes)))
				else
					lError'weird escape sequence:'
				end
			elseif info.stringType == 'multiLined' then
				-- only one type of escape sequence in multilined strings, if met, then add
				-- ] otherwise, add the raw \
				local endToken = info.endToken
				local isEscapeSequence = lGet(-#endToken, 0) == endToken:sub(1, #endToken - 1) .. '\\]'
				local addedChar = isEscapeSequence and ']' or '\\'

				updateI(isEscapeSequence and 0 or -1)
				

				addToResult(addedChar)
			else
				lError'weird escape sequence:'
			end
		else
			-- add anything else, it's irrelivant
			addToResult()
		end
	end

	return result
end

function getTableType(t)
	-- can return "array", "dictionary", "empty", "mixed" or "spotty array"
	assert(type(t) == 'table', 'BAD ARGUMENT: '.. debug.traceback())

	local result

	local stringIndexed = false
	local numberIndexed = false

	local iterations = 0

	for i in next, t do
		iterations = iterations + 1
		local typeI = type(i)
		
		if not stringIndexed and typeI == 'string'then
			stringIndexed = true
		elseif not numberIndexed and typeI == 'number'then
			numberIndexed = true
		end

		if numberIndexed and stringIndexed then
			-- both true, we got what we came for, break
			break
		end
	end

	-- assign result
	result = 
		result or
		numberIndexed and (
			stringIndexed and 'mixed' or 
			#t == iterations and 'array' or
			'spotty array'
			)or 
		stringIndexed and 'dictionary' or 
		'empty'
	
	assert(result, 'some how not met, nIndexed=' .. tostring(numberIndexed) .. ',sIndexed=' .. tostring(stringIndexed))
	
	return result
end

function JSON:encode(t, hashMap)
	-- pre
	hashMap = hashMap or {}
	assert(
		type(t) == 'table' and 
		type(hashMap) == 'table'
	)
	assert(not hashMap[t], 'circular referencing')
	hashMap[t] = true

	local tType = getTableType(t)
	
	assert(tType ~= 'mixed')

	--[[
		Note:
		Valid index types:
		 * num
		 * str (not both at the same time)

		Valid Value types:
		 * nil
		 * num
		 * str
		 * non-mixed tables
		 * bool
	]]
	local isArray = false
	local isDict = false

	for i, v in next, t do
		local tI = type(i)
		local tV = type(v)
		local iIsNum = tI == 'number'

		assert(
			tV == 'number' or 
			tV == 'boolean' or
			tV == 'nil' or 
			tV == "string" or 
			tV == "table",
			('invalid value type at index: %s, %s'):format(
				tostring(i),
				tV
			)
		)

		assert(
			iIsNum or tI == 'string',
			('invalid index type: %s'):format(tI)
		)

		if not isArray and iIsNum then
			isArray = true
		end

		if not isDict and not iIsNum then
			isDict = true
		end

		assert(not (isArray and isDict), 'mixed table detected')
	end

	if not isArray and not isDict then
		isArray = true
	end

	-- main
	local result = ''

	-- we dont have ..= or += so use this func instead
	local function append(...)result = result .. table.concat({...})end

	append(isArray and '[' or '{') -- table prefix
	
	local i = 1 -- reference index incase of spotty arrays

	local iterationMet = false

	for j, v in next, t do
		-- update iterationMet
		if not iterationMet then
			iterationMet = true
		end

		-- index
		local jT = type(j)

		if jT == 'number' then
			repeat
				i = i + 1

				if i ~= j + 1 then  -- spotty array
					append('null,')
				end
			until i == j + 1
		else
			append(('%s:'):format(
				deparseString(j, 
					{
						stringType = 'single';
						token = '"'
					}
				)
			))
		end

		-- value
		local vT = type(v)

		append(
			vT == 'nil' and 'null' or
			vT == 'table' and JSON:encode(v, hashMap) or 
			vT == 'string' and deparseString(
				v, 
				{
					stringType = 'single';
					token = '"'
				}
			) or
			tostring(v)
		)

		-- separator
		append','
	end

	--detach last separator
	if iterationMet then
		result = result:sub(1, #result - 1)
	end

	append(isArray and ']' or '}') -- table suffix

	return result
end

function JSON:getTokens(s)
	-- pre
	assert(type(s) == 'string')
	s = tostring(s)
	
	-- main
	local result = {}

	local singularChecks = {
		['['] = true;
		[']'] = true;
		['}'] = true;
		['{'] = true;
		[','] = true;
		[':'] = true
	}

	local whitespace = ''
	local tokenStart = 1
	local i = 1

	local function get(a, b)
		-- pre
		assert(type(a) == 'number') 
		
		-- main
		return s:sub(a, b or a)
	end

	local function lget(a, b)
		return not b and 
			get(i, i + (a or 0)) or 
			get(i + (a or b), i + b)
	end

	local function increment(a)
		i = i + (a or 1)
	end

	local function insertToken(tkType)
		table.insert(result, {
			tkType = tkType;
			whitespace = whitespace;
			token = get(tokenStart, i)
		})

		whitespace = ''
	end

	while true do
		-- get whitespace
		while lget():match('%s') do
			whitespace = whitespace .. lget()
			increment()
		end

		-- get token
		tokenStart = i
		
		local tkType = 'undefined'
		local c = lget()
		
		if c == '' then -- eof
			tkType = 'eof'
		elseif singularChecks[c] then -- symbol
			tkType = 'symbol'
		elseif c == '"' then -- index or string type value, but its fine 
			tkType = 'string'

			increment()

			while not lget():match'"' and lget() ~= '' do
				if lget(2) == '\\"' then
					increment()
				end

				increment()
			end

			local tk = get(tokenStart, i)

			assert(tk:sub(#tk) == '"','missing ending quote: ' .. tk)
		elseif c:match'%d' or c == '-' then -- numbers
			tkType = 'number'
			--[[
				accepts:
				 * ints,
				 * doubles
				 * negative numbers
				 * numbers using sci fi notation
				
				must begin with - or a digit
			--]]

			local dotMet = false
			local eMet = false
			local negativeMet = false
			
			while true do
				local c = lget()

				if c == '-' then
					assert(not negativeMet or lget(-1, -1):lower() == 'e', 'unexpected negative')
					negativeMet = true
				elseif c == '.' then
					assert(not dotMet, 'double dot')
					assert(not eMet, 'dot after e')

					dotMet = true
				elseif c:lower() == 'e' then
					assert(not eMet, 'double e')
					eMet = true
				elseif not c:match('%d') then
					increment(-1)
					local tk = get(tokenStart, i)
	
					assert(tk:match('%d'), 'malformed number')
					assert(tonumber(tk), 'malformed number: ' .. tk)

					break
				end

				increment()
			end
		elseif lget(3) == 'null' or lget(3) == 'true' or lget(4) == 'false' then -- reserved keywords
			tkType = 'keyword'

			local offset = lget(4) == 'false' and 4 or 3
			
			increment(offset)
		else
			print(lget)
			error('unexpected char: ' .. lget())
		end

		-- post
		assert(tkType ~= 'undefined')

		insertToken(tkType)

		if tkType == 'eof' then
			break
		end

		increment()
	end

	return result
end

local function parseTable(tks)
	-- pre
	assert(type(tks) == 'table')

	for i, v in next, tks do
		assert(
			type(v) == 'table' and 
				type(v.token) == 'string' and
				type(v.tkType) == 'string' and 
				type(v.whitespace) == 'string',
			('bad tk: %s'):format('' .. i)
		)
	end

	-- main
	local result = {}

	local isArray

	local i = 1

	local function inc(a)
		i = i + (a or 1)
	end

	local function tkError(m)
		-- pre
		m = m or ('error met: traceback: %s'):format(
			debug.traceback()
		)

		-- main
		for j = -3, 3 do
			local tk = tks[i + j]
			
			if tk then
				print(
					('[%s] = (%s, %s)'):format(
						j,
						tk.tkType,
						tk.token
					)

				)
			end
		end

		error(m)
	end

	local function tkAssert(b, m)
		if not b then
			tkError(m)
		end
	end

	local currentIndex
	
	while i <= #tks do
		local tk = tks[i]

		local token = tk.token
		local tkType = tk.tkType
		-- whitespace = tk.whitespace


		if i == #tks - 1 then -- check ending token
			tkAssert(
				isArray and token == ']' or token == '}' , 
				'invalid ending table token'
			)
		elseif isArray == nil then -- get table type
			isArray = token == '['

			assert(isArray or token == '{', 'opening table token unmet')

			if isArray then
				currentIndex = 0
			end
		elseif tkType == 'eof' then -- ending token suggest we break
			break
		else
			-- iterate down the list
			if not isArray then -- object check
				-- check index
				assert(tkType == 'string', 'expected valid object index, got ' .. token)

				currentIndex = parseString(token)
				inc(1)

				-- separator check
				assert(tks[i].token == ':')

				inc(1)
			end

			-- index for direct assignment
			currentIndex = isArray and currentIndex + 1 or currentIndex

			-- value check
			local valueTk = tks[i]
			local vTkType = valueTk.tkType
			local vToken = valueTk.token

			local value = 
				vTkType == 'string' and parseString(vToken) or -- strings
				vTkType == 'number' and tonumber(vToken) or    -- numbers
				vTkType == 'keyword' and vToken == 'true'      -- keywords, both true and false
				
			-- extras that can't be simply stated with a psuedo ternary

			local vIsArray = vToken == '['

			if vTkType == 'keyword' and vToken == 'null' then -- null
				value = nil
			elseif vIsArray or vToken == '{' then -- objects and arrays
				local vTkLvl = 0;
				local tableStart = i

				repeat
					local tkc = tks[i]
					local tkcToken = tkc.token

					if tkcToken == (vIsArray and '[' or '{') then
						vTkLvl = vTkLvl + 1
					elseif tkcToken == (vIsArray and ']' or '}') then
						vTkLvl = vTkLvl - 1
					end
					
					inc()
				until vTkLvl == 0

				inc(-1)

				local tableEnd = i

				local newTks = {unpack(tks, tableStart, tableEnd)}
				local endingTk = newTks[#newTks]
				
				if endingTk and endingTk.tkType ~= 'eof' then
					table.insert(newTks, {
						tkType = 'eof',
						token = '',
						whitespace = ''
					})
				end

				value = parseTable(newTks)
			end

			-- set
			result[currentIndex] = value

			-- increment and check due to separator
			inc()
			assert(
				tks[i].token == ',' or i == #tks or i == #tks - 1 and tks[#tks].tkType == 'eof',
				('expected ending tk or ",", got %s on index %s. total tks: #%s'):format(
					tks[i].token,
					i,
					#tks
				)
			)
		end

		inc()
	end

	return result
end

function JSON:decode(s)
	-- pre
	assert(type(s) == 'string')

	-- main
	local tokens = JSON:getTokens(s)
	local result = parseTable(tokens)

	return result, tokens
end

function JSON:minify(s)
	-- pre
	assert(type(s) == 'string')

	JSON:decode(s)

	-- main
	local result = ''

	for _, v in next, JSON:getTokens(s) do
		result = result .. v.token
	end

	return result
end

function JSON:beautify(s, indenter, indents)
	-- pre
	indenter = indenter or '    '
	indents = indents or 0
	assert(
		type(s) == 'string' and 
		type(indenter) == 'string' and not indenter:match'[%S\n]' and 
		type(indents) == 'number'
	)
	indenter = tostring(indenter)

	local _, tokens = JSON:decode(s) -- syntax checking done already, can be done here

	-- main
	local result = ''

	local i = 1

	local function inc(a)
		i = i + (a or 1)
	end

	local function concat(...)
		result = result .. table.concat{...}
	end

	local function get(a)
		return tokens[a]
	end

	local function lget(a)
		return get(i + (a or 0))
	end

	repeat
		local tk = lget()
		local token = tk.token

		-- indent check 1
		if token == '}' or token == ']' then
			indents = indents - 1 
		end

		-- concat whitespace, exception being empty tables
		local prevToken = lget(-1) and lget(-1).token
		local isEmptyToken = 
			prevToken == '[' and token == ']' or 
			prevToken == '{' and token == '}'

		if not isEmptyToken then
			concat(indenter:rep(indents))
		end

		-- indent check 2
		if token == '[' or token == '{' then
			indents = indents + 1
		end

		-- dictionary check
		if tk.tkType == 'string' and lget(1).token == ':' then
			concat(token, ' : ')
			inc(2)
		end

		-- value 
		concat(lget().token)

		-- comma check
		if lget(1).token == ',' then
			concat(',')
			inc()
		end

		-- line break
		local nextToken = lget(1) and lget(1).token
		token = lget().token
		if indents ~= 0 and not (nextToken == ']' and token == '[' or
			nextToken =='}' and token == '{')
		then
			concat('\n')
		end

		inc()
	until indents == 0


	return result
end

return JSON