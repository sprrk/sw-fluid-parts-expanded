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

-- Volume of fluid required to turn motor output shaft through one revolution.
-- Unit: cm3 per revolution.
-- Both fixed-displacement and variable-displacement motors exist.
local DISPLACEMENT = 0.1 -- 0.1L per revolution

-- Torque output:
-- Function of system pressure and motor displacement.

-- Breakaway torque:
-- Torque required to get a stationary load turning.

-- Running torque:
-- Indicates torque required to keep a load turning, or the actual torque
-- that a motor can develop to keep a load turning. Often about 90%.

-- Starting torque:
-- Capacity of a hydraulic motor to start a load.

-- Motor speed:
-- Function of motor displacement and volume of fluid delivered to motor.

-- Leakage through the motor, or fluid that passes through the motor
-- without performing work.
local SLIPPAGE = 0.001 -- 0.1% per tick

-- TODO: Fix motor mode RPS being too low compared to pump mode RPS
-- TODO: Fix energy conservation: RPS -> flow -> RPS should be ~90% efficient

-- Component details:
-- Type: hydraulic motor/pump
-- Converts fluid flow into RPS, and the other way around.

-- NOTE: On how Stormworks implements pressure:
--       Pressure can be measured by checking how full a volume is.
--       Pressure is measured in atm, from 0 to 60.
--       For example, for a volume of 1 liter:
--       - 0% full   = 0.0 L = 0 atm
--       - 50% full  = 0.5 L = 30 atm
--       - 100% full = 1.0 L = 60 atm
--       This is verified to be correct; it matches with the in-game
--       tooltip display readouts.

local TICK_RATE = 62 -- 62 ticks per second
local MASS = 10 -- Base torque
local FLUID_MASS = 1.0
local FLUID_VOLUME_SIZE = 1 -- Liters; 1 full voxel is 15.625 L

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
local function setRPS(target_rps, force)
	local mass = 0.1 + MASS * force
	if mass < 0.1 then
		-- Note: We always need at least a tiny bit of mass, otherwise there is
		-- no resistance at all and the system gets wonky
		mass = 0.1
	end
	local rps_after, _ = component.slotTorqueApplyMomentum(RPS_SLOT, mass, target_rps)
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

	-- Calculate pump flow from external RPS
	local pump_flow_per_tick = rpsToFlowAmount(external_rps)
	local pump_flow_clamped = clampTransferAmount(pump_flow_per_tick, amount_a, amount_b)

	-- Apply slippage to pump flow
	local actual_pump_flow = pump_flow_clamped * (1 - SLIPPAGE)

	-- Transfer the fluid (pump drives the system)
	transferFluid(actual_pump_flow)

	-- Motor RPS is determined by the actual flow
	local motor_rps = flowAmountToRPS(actual_pump_flow) * (1 - SLIPPAGE)

	-- Calculate force based on pressure differential
	local pressure_diff = getFluidPressureDiff()
	local base_force = math.abs(pressure_diff) * DISPLACEMENT * FLUID_MASS

	-- Ensure minimum force for movement, but scale with pressure
	local force = math.max(base_force, MASS)

	-- Apply motor RPS to output shaft
	local rps_after = setRPS(motor_rps, force)

	component.setOutputLogicSlotComposite(DATA_OUT_SLOT, {
		bool_values = {},
		float_values = {
			[1] = pump_flow_per_tick,
			[2] = pump_flow_clamped,
			[3] = actual_pump_flow,
			[4] = motor_rps,
			[5] = external_rps,
			[6] = pressure_diff,
			[7] = force,
			[8] = rps_after,
			[9] = amount_a,
			[10] = amount_b,
			[11] = base_force,
			[12] = 0, -- unused
			[13] = 0, -- unused
		},
	})
end
