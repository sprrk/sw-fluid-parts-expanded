local FILTERS_FLUIDS = require("../lib/fluid_filters").ALL_FLUIDS

-- Component details:
-- Type: hydraulic motor
-- Converts fluid flow into RPS, and the other way around (less efficiently).

-- Note: Based on in-game measurements:
-- 0.01   fluid units per tick = 6.00   liter per second
-- 0.01/6 fluid units per tick = 1.00   liter per second
-- 1.00   fluid units per tick = 600.00 liter per second
-- 1/600  fluid units per tick = 1.00   liter per second
local FLUID_TICK_TO_LITER_SECOND_RATIO = 600
local PRESSURE_SCALE = 60

local DISPLACEMENT = 10.0 -- L per revolution
local FLUID_VOLUME_SIZE = 5.0 -- Liters; 1 full voxel is 15.625 L
local MASS = 5
local INERTIA = 1.0
local EFFICIENCY = 0.95

local RPS_SLOT = 0
local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local DATA_OUT_SLOT = 0
local RPS_LIMIT_SLOT = 0

local FLUID_VOLUME_A = 0
local FLUID_VOLUME_B = 1

local initialized = false

---@param a number
---@param b number
---@return number midpoint The midpoint between A and B.
local function mid(a, b)
	return (a + b) * 0.5
end

---@param value number
---@param min number
---@param max number
---@return number
local function clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

-- @param a number
-- @param b number
-- @param t number
-- @return number
local function lerp(a, b, t)
	return a + (b - a) * t
end

---@param slot integer
---@param volume integer
local function resolveFluidVolumeFlow(slot, volume)
	component.slotFluidResolveFlow(
		slot,
		volume,
		0.0, -- pump_pressure
		1.0, -- flow_factor
		false, -- is_one_way_in_to_slot
		false, -- is_one_way_out_of_slot
		FILTERS_FLUIDS,
		-1 -- index_fluid_contents_transfer
	)
end

---@return number rps
local function getRPS()
	-- Note: Stormworks has no slotGetRPS function; this is the only way to get RPS
	local rps, _ = component.slotTorqueApplyMomentum(RPS_SLOT, 0, 0)
	return rps
end

---@param index integer The index of the volume
---@return number
local function getAmount(index)
	local amount, _ = component.fluidContentsGetVolume(index)
	return amount
end

---@param amount number
local function transferFluid(amount)
	if amount > 0 then
		component.fluidContentsTransferVolume(FLUID_VOLUME_A, FLUID_VOLUME_B, amount)
	elseif amount < 0 then
		component.fluidContentsTransferVolume(FLUID_VOLUME_B, FLUID_VOLUME_A, -amount)
	end
end

---@param target_rps number
---@param force number
---@return number rps_after
local function applyMomentum(target_rps, force)
	local rps_after, _ = component.slotTorqueApplyMomentum(RPS_SLOT, force, target_rps)
	return rps_after
end

---@param rps number
---@return number flow_rate (L/sec)
local function rpsToFlowRate(rps)
	return (rps * DISPLACEMENT)
end

---@param flow_rate number (L/sec)
---@return number rps
local function flowRateToRPS(flow_rate)
	return flow_rate / DISPLACEMENT
end

local function initialize()
	component.fluidContentsSetCapacity(FLUID_VOLUME_A, FLUID_VOLUME_SIZE)
	component.fluidContentsSetCapacity(FLUID_VOLUME_B, FLUID_VOLUME_SIZE)
	initialized = true
end

function onTick(tick_time)
	if not initialized then
		initialize()
	end

	local external_rps = getRPS()

	-- Move fluid in and out of the volumes
	resolveFluidVolumeFlow(FLUID_SLOT_A, FLUID_VOLUME_A)
	resolveFluidVolumeFlow(FLUID_SLOT_B, FLUID_VOLUME_B)

	-- Determine flow rate based on external RPS
	local flow_rate = rpsToFlowRate(external_rps) * tick_time * EFFICIENCY -- L/sec

	-- Calculate delta P and equalization flow rate
	local amount_a = getAmount(FLUID_VOLUME_A)
	local amount_b = getAmount(FLUID_VOLUME_B)
	local pressure_a, _ = component.fluidContentsGetPressure(FLUID_VOLUME_A)
	local pressure_b, _ = component.fluidContentsGetPressure(FLUID_VOLUME_B)
	local delta_p = (pressure_a / PRESSURE_SCALE) - (pressure_b / PRESSURE_SCALE)

	-- Move fluid based on external RPS
	transferFluid(flow_rate / FLUID_TICK_TO_LITER_SECOND_RATIO)

	-- Calculate target RPS based on pressure difference
	local torque = delta_p * DISPLACEMENT * EFFICIENCY
	local angular_acceleration = torque / INERTIA
	local delta_rps = angular_acceleration * tick_time
	local target_rps = external_rps + delta_rps

	-- Apply RPS limit
	local rps_limit = component.getInputLogicSlotFloat(RPS_LIMIT_SLOT)
	if rps_limit ~= 0 then
		if rps_limit > 0 then
			target_rps = clamp(target_rps, 0, rps_limit)
		elseif rps_limit < 0 then
			target_rps = clamp(target_rps, rps_limit, 0)
		end
	end

	applyMomentum(target_rps, MASS)

	-- Debug data:
	local pump_mode = not ((external_rps > 0 and delta_p > 0) or (external_rps < 0 and delta_p < 0))

	component.setOutputLogicSlotComposite(DATA_OUT_SLOT, {
		bool_values = {
			[1] = pump_mode,
		},
		float_values = {
			[1] = external_rps,
			[2] = amount_a,
			[3] = amount_b,
			[4] = pressure_a,
			[5] = pressure_b,
			[6] = flow_rate,
			[7] = target_rps,
			[8] = delta_rps,
			[9] = delta_p,
			[10] = torque,
		},
	})
end
