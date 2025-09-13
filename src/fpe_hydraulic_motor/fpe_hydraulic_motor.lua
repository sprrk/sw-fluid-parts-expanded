-- Component details:
-- Type: hydraulic motor/pump
-- Converts fluid flow into RPS, and the other way around.

-- Research notes:
-- Displacement is constant for fixed-displacement motors, regardless of pressure.
-- Each revolution moves the same amount of liquid.
-- Examples:
-- Skid steer boom: 0.05 L/rev
-- Small/medium skid steer wheel: 0.1 to 0.5 L/rev
-- Large skid steer wheel: 1.0 L/rev
--
-- The pressure differential between the pump/motor's inlet and outlet
-- determines the torque.
-- Higher torque makes the pump more difficult to spin.
-- Higher torque gives the motor more power to spin its shaft.
--
-- The absolute system pressure does not affect the torque, speed or displacement.
-- The motor/pump operates the same at 10 atm and 60 atm.
--
-- Very high pressure differential can cause internal leakage (slip), causing less
-- flow to effectively turn the shaft.
-- Leakage is a volume flow rate (L/s).
-- Increased pressure differential forces more fluid through internal clearances,
-- causing more leakage.
-- Example:
-- 1 L/s flow rate; 10 atm; 5% leakage; 0.95 L/s converted to speed; 0.05 L/s passes through.
-- 1 L/s flow rate; 60 atm; 10% leakage; 0.90 L/s converted to speed; 0.10 L/s passes through.
--
-- Flow rate affects motor/pump speed.
-- Speed depends on displacement.
-- Speed = flow_rate / displacement

-- TODO: Add pressure-compensated flow valve, so that the constant absolute
--       flow rate is guaranteed even if load or pressure changes:
--       - Add number input slot to control internal flow valve
--       - value <= 0 : fully open, no restriction
--       - value > 0: restrict L/s to value

-- NOTE: On how Stormworks implements pressure:
--       Pressure can be measured by checking how full a volume is.
--       Pressure is measured in atm, from 0 to 60.
--       For example, for a volume of 1 liter:
--       - 0% full   = 0.0 L = 0 atm
--       - 50% full  = 0.5 L = 30 atm
--       - 100% full = 1.0 L = 60 atm
--       This is verified to be correct; it matches with the in-game
--       tooltip display readouts.

local DISPLACEMENT = 0.1 -- 0.1L per revolution
local TORQUE_FACTOR = 100.0
local MASS = 0.01 -- Base torque
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

---@return number pressure_diff
local function getFluidPressureDiff()
	-- Get the pressure difference (in atm)
	local pressure_a, _ = component.fluidContentsGetPressure(FLUID_VOLUME_A)
	local pressure_b, _ = component.fluidContentsGetPressure(FLUID_VOLUME_B)
	return pressure_a - pressure_b
end

---@param index integer The index of the volume
---@return number
local function getAmount(index)
	local amount, _ = component.fluidContentsGetVolume(index)
	return amount
end

---@param vol_a number
---@param vol_b number
---@return number the Amount of fluid that is necessary to balance the two volumes
local function getFluidBalanceAmount(vol_a, vol_b)
	return (vol_a - vol_b) * 0.5
end

---@param amount number Desired transfer amount
---@param vol_a number The amount in volume A
---@param vol_b number The amount in volume B
---@return number clamped Amount that respects volume limits
local function clampTransferAmount(amount, vol_a, vol_b)
	-- How much can physically leave the source and fit in the destination?
	local max_a_to_b = math.min(vol_a, FLUID_VOLUME_SIZE - vol_b)
	local max_b_to_a = math.min(vol_b, FLUID_VOLUME_SIZE - vol_a)

	if amount > 0 then
		return math.min(amount, max_a_to_b)
	elseif amount < 0 then
		return math.max(amount, -max_b_to_a)
	else
		return 0
	end
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
---@return number flow_amount (L/tick)
local function rpsToFlowAmount(rps)
	return (rps * DISPLACEMENT) / TICK_RATE
end

---@param flow_amount number (L/tick)
---@return number rps
local function flowAmountToRPS(flow_amount)
	return (flow_amount * TICK_RATE) / DISPLACEMENT
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
	local desired_flow_rate = (amount_a - amount_b) * 0.5

	-- Determine the RPS based on the flow (speed = flow / displacement)
	local desired_rps = (desired_flow_rate / DISPLACEMENT) * SW_FLUID_SCALING

	-- Determine the flow rate based on the external RPS
	local desired_pump_flow_rate = (external_rps * DISPLACEMENT) / SW_FLUID_SCALING -- L/sec

	local target_rps = 0
	local target_flow_rate = 0
	-- local TEST_VAL = 0.5 -- Value of 0.5 seems to give fair results
	-- if desired_pump_flow_rate < desired_flow_rate then
	if math.abs(external_rps) < math.abs(desired_rps) then
		-- External RPS generates less flow than the desired fluid flow rate
		-- The desired fluid flow rate will speed up the RPS

		-- Increase RPS
		target_rps = mid(desired_rps, external_rps)
		-- target_rps = lerp(external_rps, desired_rps, TEST_VAL)
		-- target_rps = desired_rps

		-- Decrease flow
		target_flow_rate = mid(desired_flow_rate, desired_pump_flow_rate)
		-- target_flow_rate = lerp(desired_flow_rate, desired_pump_flow_rate, TEST_VAL)
		-- target_flow_rate = desired_pump_flow_rate
		--elseif desired_pump_flow_rate > desired_flow_rate then
	elseif math.abs(external_rps) > math.abs(desired_rps) then
		-- External RPS generates more flow than the desired fluid flow rate
		-- The desired fluid flow rate will slow down the RPS

		-- Decrease RPS
		target_rps = mid(desired_rps, external_rps)
		-- target_rps = lerp(desired_rps, external_rps, TEST_VAL)
		-- target_rps = external_rps

		-- Increase flow
		target_flow_rate = mid(desired_flow_rate, desired_pump_flow_rate)
		-- target_flow_rate = lerp(desired_pump_flow_rate, desired_flow_rate, TEST_VAL)
		-- target_flow_rate = desired_flow_rate
	end

	-- Determine torque based on the flow rate difference (Stormworks pressure)
	local delta_p = math.abs(desired_flow_rate)
	local torque = MASS + delta_p * TORQUE_FACTOR

	-- Apply the momentum and check how effective the RPS change was
	local rps_after = applyMomentum(target_rps, torque)

	-- Determine the final flow rate based on the updated RPS, so we can move
	-- the correct amount of fluid
	local final_flow_rate = (rps_after * DISPLACEMENT) / SW_FLUID_SCALING -- L/s
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
			[9] = delta_p,
			[10] = torque,
			[11] = rps_after,
			[12] = final_flow_rate,
			[13] = final_flow_rate_per_tick,
		},
	})
end
