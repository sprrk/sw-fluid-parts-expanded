-- TODO: Store char map as bitmasks; one int per char

local _00000 = { 0, 0, 0, 0, 0 }
local _11111 = { 1, 1, 1, 1, 1 }
local _10001 = { 1, 0, 0, 0, 1 }
local _01110 = { 0, 1, 1, 1, 0 }
local _00100 = { 0, 0, 1, 0, 0 }
local _10000 = { 1, 0, 0, 0, 0 }
local _00001 = { 0, 0, 0, 0, 1 }
local _00010 = { 0, 0, 0, 1, 0 }
local _01000 = { 0, 1, 0, 0, 0 }
local _11110 = { 1, 1, 1, 1, 0 }
local CHAR_MAP = {
	[""] = {
		_00000,
		_00000,
		_00000,
		_00000,
		_00000,
		_00000,
		_00000,
	},
	[" "] = {
		_00000,
		_00000,
		_00000,
		_00000,
		_00000,
		_00000,
		_00000,
	},
	["0"] = {
		_01110,
		_10001,
		_10001,
		_10001,
		_10001,
		_10001,
		_01110,
	},
	["1"] = {
		_00100,
		{ 0, 1, 1, 0, 0 },
		_00100,
		_00100,
		_00100,
		_00100,
		_01110,
	},
	["2"] = {
		_01110,
		_10001,
		_00001,
		_00010,
		_00100,
		_01000,
		_11111,
	},
	["3"] = {
		_01110,
		_10001,
		_00001,
		{ 0, 0, 1, 1, 0 },
		_00001,
		_10001,
		_01110,
	},
	["4"] = {
		_00010,
		{ 0, 0, 1, 1, 0 },
		{ 0, 1, 0, 1, 0 },
		{ 1, 0, 0, 1, 0 },
		_11111,
		_00010,
		_00010,
	},
	["5"] = {
		_11111,
		_10000,
		_10000,
		_11110,
		_00001,
		_10001,
		_01110,
	},
	["6"] = {
		_01110,
		_10001,
		_10000,
		_11110,
		_10001,
		_10001,
		_01110,
	},
	["7"] = {
		_11111,
		_00001,
		_00001,
		_00010,
		_00100,
		_01000,
		_01000,
	},
	["8"] = {
		_01110,
		_10001,
		_10001,
		_01110,
		_10001,
		_10001,
		_01110,
	},
	["9"] = {
		_01110,
		_10001,
		_10001,
		{ 0, 1, 1, 1, 1 },
		_00001,
		_10001,
		_01110,
	},
	["."] = {
		_00000,
		_00000,
		_00000,
		_00000,
		_00000,
		{ 0, 1, 1, 0, 0 },
		{ 0, 1, 1, 0, 0 },
	},
	["-"] = {
		_00000,
		_00000,
		_00000,
		_11111,
		_00000,
		_00000,
		_00000,
	},
	["`"] = { -- Remapped for truncation char; ` is rare
		_00000,
		_00000,
		_00000,
		_00000,
		_00000,
		_00000,
		{ 1, 0, 1, 0, 1 },
	},
	["E"] = {
		_11111,
		_10000,
		_10000,
		_11110,
		_10000,
		_10000,
		_11111,
	},
	["R"] = {
		_11110,
		_10001,
		_10001,
		_11110,
		{ 1, 0, 1, 0, 0 },
		{ 1, 0, 0, 1, 0 },
		_10001,
	},
}

---@param charCount integer
---@param truncateChar string
---@return fun(value: number|integer): string
local function makeNumberFormatter(charCount, truncateChar)
	local strf = string.format

	return function(value)
		local digits = #tostring(math.floor(value))
		local text = strf("%f", value)

		if digits > charCount then
			-- Too large; truncate and replace last char with truncateChar
			return text:sub(1, charCount - 1) .. truncateChar
		elseif digits == charCount - 1 then
			-- This would render a trailing dot; truncate extra
			return text:sub(1, charCount - 1)
		else
			-- Round last decimal properly
			local decimals = math.max(charCount - digits - 1, 0)
			local fmt = strf("%%.%df", decimals)
			return strf(fmt, value)
		end
	end
end

---@class (exact) DotMatrixDisplayOrigin
---@field x number X position
---@field y number Y position
---@field z number Z position

---@param origin DotMatrixDisplayOrigin
---@param charCount integer Amount of characters
---@return DotMatrixDisplay
local function DotMatrixDisplay(origin, charCount)
	---@class DotMatrixDisplay
	local instance = {}

	local x, y, z = origin.x, origin.y, origin.z

	local buffer = {}
	local nBuffer = 0
	local pixelSize = 0.003 -- TODO: Make configurable
	local fontWidth = 5
	local fontHeight = 7
	local charOffset = pixelSize * (fontWidth + 1) -- 1px gap
	local enabled = true
	local flipped = false

	local formatNumber = makeNumberFormatter(charCount, "`")

	---@type string|number
	local currentValue = ""

	local renderMesh0 = component.renderMesh0 -- TODO: Allow configuring render func via arg

	---@param char string
	---@param i integer Char index
	local function addChar(char, i)
		-- TODO: Improve performance: setChar() instead of addChar();
		--       only refresh buffer when necessary

		local xOffset = (i - 1) * charOffset

		local grid = CHAR_MAP[char]

		if not grid then
			-- Fallback to renderable char to prevent index errors
			grid = CHAR_MAP[" "]
		end

		-- Aliases for efficiency
		local matrixTranslation = matrix.translation
		local ti = table.insert

		for row = 1, fontHeight do
			for col = 1, fontWidth do
				if grid[row][col] == 1 then
					if flipped then
						ti(buffer, matrixTranslation(x - xOffset - (col - 1) * pixelSize, y, z + (row - 1) * pixelSize))
					else
						ti(buffer, matrixTranslation(x + xOffset + (col - 1) * pixelSize, y, z - (row - 1) * pixelSize))
					end
				end
			end
		end

		nBuffer = #buffer
	end

	local function clear()
		buffer = {}
		nBuffer = 0
	end

	local function refresh()
		-- TODO: Performance: Only update characters that have changed

		clear()

		local strValue
		if type(currentValue) == "number" then
			strValue = formatNumber(currentValue)
		else
			strValue = currentValue
		end

		for i = 1, charCount do
			addChar(strValue:sub(i, i), i)
		end
	end

	---@param value string|number
	function instance:setText(value)
		if currentValue ~= value then
			currentValue = value

			if enabled then
				refresh()
			end
		end
	end

	function instance:clear()
		clear()
	end

	---@param v boolean
	function instance:setEnabled(v)
		if enabled ~= v then
			enabled = v
			if enabled then
				refresh()
			end
		end
	end

	---@param v boolean
	function instance:setFlipped(v)
		if flipped ~= v then
			flipped = v

			if flipped then
				-- Move x and z to bottom right corner of display
				local pixelCountX = fontWidth * charCount + charCount - 1
				x = origin.x + pixelCountX * pixelSize - pixelSize
				z = origin.z - (fontHeight * pixelSize) + pixelSize
			else
				x, z = origin.x, origin.z
			end

			refresh()
		end
	end

	function instance:render()
		if enabled then
			for i = 1, nBuffer do
				renderMesh0(buffer[i])
			end
		end
	end

	return instance
end

return DotMatrixDisplay
