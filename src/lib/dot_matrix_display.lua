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

---@param x number X position
---@param y number Y position
---@param z number Z position
---@param charCount integer Amount of characters
---@return DotMatrixDisplay
local function DotMatrixDisplay(x, y, z, charCount)
	---@class DotMatrixDisplay
	local instance = {}

	-- TODO: Add arg to flip display / rotate 180 degrees

	local buffer = {}
	local nBuffer = 0
	local pixelSize = 0.003 -- TODO: Make configurable
	local charOffset = pixelSize * 6 -- 5px wide, 1px gap
	local enabled = true
	local renderMesh0 = component.renderMesh0 -- TODO: Allow configuring render func via arg

	---@param char string
	---@param i integer Char index
	---@return nil
	function instance:addChar(char, i)
		-- TODO: Improve performance: setChar() instead of addChar();
		--       only refresh buffer when necessary

		local xOffset = x + (i - 1) * charOffset

		local grid = CHAR_MAP[char]
		for row = 1, 7 do
			for col = 1, 5 do
				if grid[row][col] == 1 then
					table.insert(
						buffer,
						matrix.translation(xOffset + (col - 1) * pixelSize, y, z - (row - 1) * pixelSize)
					)
				end
			end
		end

		nBuffer = #buffer
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

	---@param value string|number
	function instance:setText(value)
		self:clear()
		if type(value) == "number" then
			for i = 1, charCount do
				self:addChar(digit(value, i), i)
			end
		else
			for i = 1, charCount do
				self:addChar(value:sub(i, i), i)
			end
		end
	end

	function instance:clear()
		buffer = {}
		nBuffer = 0
	end

	---@param v boolean
	---@return nil
	function instance:setEnabled(v)
		enabled = v
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
