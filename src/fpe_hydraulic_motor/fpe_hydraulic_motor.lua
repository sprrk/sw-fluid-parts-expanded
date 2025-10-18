local FILTERS_LIQUIDS = require("../lib/fluid_filters").ALL_LIQUIDS

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
local FLUID_VOLUME_SIZE = 6.0 -- Liters; 1 full voxel is 15.625 L
local MASS = 2
local VISCOUS_FRICTION = 0.001

local RPS_SLOT = 0
local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local DATA_OUT_SLOT = 0
local RPS_LIMIT_SLOT = 0

local FLUID_VOLUME_A = 0
local FLUID_VOLUME_B = 1

local initialized = false

---@param value number
---@param min number
---@param max number
---@return number
local function clamp(value, min, max)
	return math.max(min, math.min(max, value))
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
		FILTERS_LIQUIDS,
		-1 -- index_fluid_contents_transfer
	)
end

---@param amount number
local function transferFluid(amount)
	if amount > 0 then
		component.fluidContentsTransferVolume(FLUID_VOLUME_A, FLUID_VOLUME_B, amount)
	elseif amount < 0 then
		component.fluidContentsTransferVolume(FLUID_VOLUME_B, FLUID_VOLUME_A, -amount)
	end
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

	local external_rps, _ = component.slotTorqueApplyMomentum(RPS_SLOT, 0, 0)

	-- Move fluid in and out of the volumes
	resolveFluidVolumeFlow(FLUID_SLOT_A, FLUID_VOLUME_A)
	resolveFluidVolumeFlow(FLUID_SLOT_B, FLUID_VOLUME_B)

	-- Calculate delta P and equalization flow rate
	local amount_a, _ = component.fluidContentsGetVolume(FLUID_VOLUME_A)
	local amount_b, _ = component.fluidContentsGetVolume(FLUID_VOLUME_B)
	local pressure_a, _ = component.fluidContentsGetPressure(FLUID_VOLUME_A)
	local pressure_b, _ = component.fluidContentsGetPressure(FLUID_VOLUME_B)
	local delta_p = (pressure_a / PRESSURE_SCALE) - (pressure_b / PRESSURE_SCALE)

	-- Move fluid based on external RPS
	local desired_flow_rate = external_rps * DISPLACEMENT -- L/sec
	local desired_transfer = (desired_flow_rate / FLUID_TICK_TO_LITER_SECOND_RATIO) * tick_time
	local actual_transfer = 0

	if desired_transfer > 0 then -- Positive flow: A → B
		local max_possible = math.min(amount_a, FLUID_VOLUME_SIZE - amount_b)
		actual_transfer = math.min(desired_transfer, max_possible)
	elseif desired_transfer < 0 then -- Negative flow: B → A
		local max_possible = math.min(amount_b, FLUID_VOLUME_SIZE - amount_a)
		actual_transfer = math.max(desired_transfer, -max_possible)
	end

	transferFluid(actual_transfer)

	local flow_efficiency_ratio = 1.0
	if math.abs(desired_transfer) > 0.001 then
		flow_efficiency_ratio = clamp(actual_transfer / desired_transfer, 0, 1)
	end

	-- Calculate torque based on pressure difference
	local torque = delta_p * DISPLACEMENT * flow_efficiency_ratio

	-- Apply hydraulic lock resistance when flow is restricted
	if flow_efficiency_ratio < 1 then
		torque = torque - (external_rps * (1.0 - flow_efficiency_ratio))
	end

	-- Apply friction; faster = more friction
	torque = torque - external_rps * VISCOUS_FRICTION

	-- Calculate delta RPS, corrected for tick lag
	local delta_rps = torque * tick_time

	-- Calculate resulting target RPS
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

	component.slotTorqueApplyMomentum(RPS_SLOT, MASS, target_rps)

	component.setOutputLogicSlotComposite(DATA_OUT_SLOT, {
		float_values = {
			[1] = external_rps,
			[2] = (actual_transfer / tick_time) * FLUID_TICK_TO_LITER_SECOND_RATIO, -- Actual flow rate (L/sec)
			[3] = delta_p,
			[4] = delta_rps,
		},
	})
end
