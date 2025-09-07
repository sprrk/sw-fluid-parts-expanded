---@meta

---@param tick_time number
function onTick(tick_time) end

---@table component
component = {}

---@param index number
---@param mass number
---@param rps number
---@return number, boolean
function component.slotTorqueApplyMomentum(index, mass, rps) end

function onRemoveFromSimulation() end
