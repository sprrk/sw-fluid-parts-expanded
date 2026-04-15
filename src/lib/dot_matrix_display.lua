-- TODO: Store char map as bitmasks; one int per char
local CHAR_MAP = {
	[""] = {
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
	},
	[" "] = {
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
	},
	["0"] = {
		{ 0, 1, 1, 1, 0 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 0, 1, 1, 1, 0 },
	},
	["1"] = {
		{ 0, 0, 1, 0, 0 },
		{ 0, 1, 1, 0, 0 },
		{ 0, 0, 1, 0, 0 },
		{ 0, 0, 1, 0, 0 },
		{ 0, 0, 1, 0, 0 },
		{ 0, 0, 1, 0, 0 },
		{ 0, 1, 1, 1, 0 },
	},
	["2"] = {
		{ 0, 1, 1, 1, 0 },
		{ 1, 0, 0, 0, 1 },
		{ 0, 0, 0, 0, 1 },
		{ 0, 0, 0, 1, 0 },
		{ 0, 0, 1, 0, 0 },
		{ 0, 1, 0, 0, 0 },
		{ 1, 1, 1, 1, 1 },
	},
	["3"] = {
		{ 0, 1, 1, 1, 0 },
		{ 1, 0, 0, 0, 1 },
		{ 0, 0, 0, 0, 1 },
		{ 0, 0, 1, 1, 0 },
		{ 0, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 0, 1, 1, 1, 0 },
	},
	["4"] = {
		{ 0, 0, 0, 1, 0 },
		{ 0, 0, 1, 1, 0 },
		{ 0, 1, 0, 1, 0 },
		{ 1, 0, 0, 1, 0 },
		{ 1, 1, 1, 1, 1 },
		{ 0, 0, 0, 1, 0 },
		{ 0, 0, 0, 1, 0 },
	},
	["5"] = {
		{ 1, 1, 1, 1, 1 },
		{ 1, 0, 0, 0, 0 },
		{ 1, 0, 0, 0, 0 },
		{ 1, 1, 1, 1, 0 },
		{ 0, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 0, 1, 1, 1, 0 },
	},
	["6"] = {
		{ 0, 1, 1, 1, 0 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 0 },
		{ 1, 1, 1, 1, 0 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 0, 1, 1, 1, 0 },
	},
	["7"] = {
		{ 1, 1, 1, 1, 1 },
		{ 0, 0, 0, 0, 1 },
		{ 0, 0, 0, 0, 1 },
		{ 0, 0, 0, 1, 0 },
		{ 0, 0, 1, 0, 0 },
		{ 0, 1, 0, 0, 0 },
		{ 0, 1, 0, 0, 0 },
	},
	["8"] = {
		{ 0, 1, 1, 1, 0 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 0, 1, 1, 1, 0 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 0, 1, 1, 1, 0 },
	},
	["9"] = {
		{ 0, 1, 1, 1, 0 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 0, 1, 1, 1, 1 },
		{ 0, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 0, 1, 1, 1, 0 },
	},
	["."] = {
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 1, 1, 0, 0 },
		{ 0, 1, 1, 0, 0 },
	},
	["-"] = {
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 1, 1, 1, 1, 1 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0 },
	},
	["E"] = {
		{ 1, 1, 1, 1, 1 },
		{ 1, 0, 0, 0, 0 },
		{ 1, 0, 0, 0, 0 },
		{ 1, 1, 1, 1, 0 },
		{ 1, 0, 0, 0, 0 },
		{ 1, 0, 0, 0, 0 },
		{ 1, 1, 1, 1, 1 },
	},
	["R"] = {
		{ 1, 1, 1, 1, 0 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 0, 0, 0, 1 },
		{ 1, 1, 1, 1, 0 },
		{ 1, 0, 1, 0, 0 },
		{ 1, 0, 0, 1, 0 },
		{ 1, 0, 0, 0, 1 },
	},
}

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
		for row = 1, fontHeight do
			for col = 1, fontWidth do
				if grid[row][col] == 1 then
					if flipped then
						table.insert(
							buffer,
							matrix.translation(x - xOffset - (col - 1) * pixelSize, y, z + (row - 1) * pixelSize)
						)
					else
						table.insert(
							buffer,
							matrix.translation(x + xOffset + (col - 1) * pixelSize, y, z - (row - 1) * pixelSize)
						)
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

	---@param num number
	---@param i integer
	---@return string
	local function digit(num, i)
		local b = tostring(num):byte(i) or 48 -- Default to '0'
		if b == 46 then -- ASCII '.' = 46
			return "."
		else
			return tostring(b - 48) -- ASCII '0' = 48
		end
	end

	local function refresh()
		-- TODO: Performance: Only update characters that have changed

		clear()
		if type(currentValue) == "number" then
			for i = 1, charCount do
				addChar(digit(currentValue, i), i)
			end
		else
			for i = 1, charCount do
				addChar(currentValue:sub(i, i), i)
			end
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
