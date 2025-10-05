---@meta

---@param tick_time number
function onTick(tick_time) end

function onRender() end

function onRemoveFromSimulation() end

---@table component
component = {}

---@param index number
---@param mass number
---@param rps number
---@return number, boolean
function component.slotTorqueApplyMomentum(index, mass, rps) end

---@table matrix
matrix = {}

---@param radians number
---@return table
function matrix.rotationY(radians) end
