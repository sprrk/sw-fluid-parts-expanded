-- Component details:
-- Type: hydraulic motor
-- Converts fluid flow into RPS, and the other way around (less efficiently).

-- TODO: Add pressure-compensated flow valve, so that the constant absolute
--       flow rate is guaranteed even if load or pressure changes:
--       - Add number input slot to control internal flow valve
--       - value <= 0 : fully open, no restriction
--       - value > 0: restrict L/s to value

local DISPLACEMENT = 10.0 -- L per revolution
local MASS = 2 -- Base torque, similar to small electric motor
local FLUID_VOLUME_SIZE = 1 -- Liters; 1 full voxel is 15.625 L

local TICK_RATE = 62 -- 62 ticks per second
local SW_FLUID_SCALING = 60 / math.pi

local RPS_SLOT = 0
local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local DATA_OUT_SLOT = 0

local FLUID_VOLUME_A = 0
local FLUID_VOLUME_B = 1

local FILTERS_FLUIDS = (
	1 -- Water
	+ 2 -- Diesel
	+ 4 -- Jet
	+ 32 -- Oil
	+ 64 -- Sea water
	+ 256 -- Slurry
	+ 512 -- Sat. slurry
)
local FILTERS_GASES = (
	8 -- O2
	+ 16 -- CO2
	+ 128 -- Steam
	+ 1024 -- O2
	+ 2048 -- N2
	+ 4096 -- H2
)

local initialized = false

---@param x number
---@return number sign (-1, 0, or 1)
local function sign(x)
	if x > 0 then
		return 1
	elseif x < 0 then
		return -1
	else
		return 0
	end
end

---@param value number
---@param min_val number
---@param max_val number
---@return number clamped_value
local function clamp(value, min_val, max_val)
	return math.max(min_val, math.min(max_val, value))
end

---@param a number
---@param b number
---@param t number
---@return number
local function lerp(a, b, t)
	return a + (b - a) * t
end

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
		-- FILTERS_FLUIDS,
		FILTERS_FLUIDS + FILTERS_GASES,
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
	return (rps * DISPLACEMENT) / SW_FLUID_SCALING
end

---@param flow_rate number (L/sec)
---@return number rps
local function flowRateToRPS(flow_rate)
	return (flow_rate / DISPLACEMENT) * SW_FLUID_SCALING
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

	local external_rps = getRPS()
	local amount_a = getAmount(FLUID_VOLUME_A)
	local amount_b = getAmount(FLUID_VOLUME_B)

	-- Determine the flow rate based on the difference between the two volumes
	local desired_flow_rate = (amount_a - amount_b) * (FLUID_VOLUME_SIZE * 2)
	desired_flow_rate = desired_flow_rate * TICK_RATE -- L/sec

	-- Determine the RPS based on the flow (speed = flow / displacement)
	local desired_rps = flowRateToRPS(desired_flow_rate)

	-- Determine the flow rate based on the external RPS
	local desired_pump_flow_rate = rpsToFlowRate(external_rps) -- L/sec

	-- Find the midpoint for the two competing flow rates
	local target_flow_rate = mid(desired_flow_rate, desired_pump_flow_rate)
	local target_rps = flowRateToRPS(target_flow_rate)

	-- Apply the momentum and check how effective the RPS change was
	local rps_after = applyMomentum(target_rps, MASS)

	-- Determine the final flow rate based on the updated RPS, so we can move
	-- the correct amount of fluid
	local final_flow_rate = rpsToFlowRate(rps_after) -- L/s
	local final_flow_rate_per_tick = final_flow_rate / TICK_RATE -- L/tick
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
			[14] = final_flow_rate * SW_FLUID_SCALING, -- True L/s as shown in-game
		},
	})
end
