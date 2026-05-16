---@param slot integer
---@param amount number
---@return boolean
local function useElectricCharge(slot, amount)
	local chargeFactor, ok = component.slotElectricGetChargeFactor(slot)
	if ok and chargeFactor > amount then
		component.slotElectricRemoveCharge(slot, amount)
		return true
	else
		return false
	end
end

return useElectricCharge
