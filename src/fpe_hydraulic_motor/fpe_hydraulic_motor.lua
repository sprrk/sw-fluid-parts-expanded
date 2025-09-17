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

-- Note: Small impeller has a displacement of ~2.68
local DISPLACEMENT = 2.5 -- L per revolution
local MASS = 0.1 -- Base torque, similar to small impeller
local FLUID_VOLUME_SIZE = 1 -- Liters; 1 full voxel is 15.625 L

local RPS_SLOT = 0
local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local DATA_OUT_SLOT = 0
local FLOW_LIMIT_SLOT = 0

local FLUID_VOLUME_A = 0
local FLUID_VOLUME_B = 1

local initialized = false

---@param a number
---@param b number
---@return number midpoint The midpoint between A and B.
local function mid(a, b)
	return (a + b) * 0.5
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

function onTick(_)
	if not initialized then
		initialize()
	end

	resolveFluidVolumeFlow(FLUID_SLOT_A, FLUID_VOLUME_A)
	resolveFluidVolumeFlow(FLUID_SLOT_B, FLUID_VOLUME_B)

	local flow_limit = component.getInputLogicSlotFloat(FLOW_LIMIT_SLOT) -- L/sec
	flow_limit = math.abs(flow_limit)

	local external_rps = getRPS()
	local amount_a = getAmount(FLUID_VOLUME_A)
	local amount_b = getAmount(FLUID_VOLUME_B)

	-- Determine the flow rate based on the difference between the two volumes
	local desired_flow_rate = (amount_a - amount_b) * 0.5 -- L/tick
	desired_flow_rate = desired_flow_rate * FLUID_TICK_TO_LITER_SECOND_RATIO -- L/sec

	-- Determine the RPS based on the flow (speed = flow / displacement)
	local desired_rps = flowRateToRPS(desired_flow_rate)

	-- Determine the flow rate based on the external RPS
	local desired_pump_flow_rate = rpsToFlowRate(external_rps) -- L/sec

	-- Find the midpoint for the two competing flow rates
	local target_flow_rate = mid(desired_flow_rate, desired_pump_flow_rate)

	-- Limit flow rate
	if flow_limit > 0 and (flow_limit < math.abs(target_flow_rate)) then
		if target_flow_rate > 0 then
			target_flow_rate = flow_limit
		else
			target_flow_rate = -flow_limit
		end
	end

	local target_rps = flowRateToRPS(target_flow_rate)

	-- Apply the momentum and check how effective the RPS change was
	local rps_after = applyMomentum(target_rps, MASS)

	-- Determine the final flow rate based on the updated RPS, so we can move
	-- the correct amount of fluid
	local final_flow_rate = rpsToFlowRate(rps_after) -- L/s
	local final_flow_rate_per_tick = final_flow_rate / FLUID_TICK_TO_LITER_SECOND_RATIO -- L/tick
	transferFluid(final_flow_rate_per_tick)

	component.setOutputLogicSlotComposite(DATA_OUT_SLOT, {
		bool_values = {},
		float_values = {
			[1] = external_rps,
			[2] = amount_a,
			[3] = amount_b,
			[4] = desired_flow_rate,
			[5] = desired_rps,
			[6] = desired_pump_flow_rate,
			[7] = target_rps,
			[8] = target_flow_rate,
			[9] = 0, --delta_p,
			[10] = MASS, -- torque
			[11] = rps_after,
			[12] = final_flow_rate,
			[13] = final_flow_rate_per_tick,
		},
	})
end
