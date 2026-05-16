---@generic T
---@param initialItems (T[])?
---@return Set<T>
local function Set(initialItems)
	local items = {}

	if initialItems then
		for i = 1, #initialItems do
			items[initialItems[i]] = true
		end
	end

	---@class (exact) Set<T>
	local instance = {}

	---@param item T
	function instance:add(item)
		items[item] = true
	end

	---@param item T
	function instance:remove(item)
		items[item] = nil
	end

	---@return T|nil
	function instance:next()
		local item, _ = next(items)
		return item
	end

	---@return T|nil
	function instance:pop()
		-- Note: not guaranteed to be the latest item.

		local item, _ = next(items)
		if item ~= nil then
			items[item] = nil
		end
		return item
	end

	---@return integer
	function instance:len()
		local count = 0
		for _ in pairs(items) do
			count = count + 1
		end
		return count
	end

	function instance:clear()
		for k in pairs(items) do
			items[k] = nil
		end
	end

	---@param item T
	---@return boolean
	function instance:has(item)
		return items[item] ~= nil
	end

	return instance
end

return Set
