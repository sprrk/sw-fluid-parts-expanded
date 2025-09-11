-- TODO: Fix motor mode RPS being too low compared to pump mode RPS
-- TODO: Also consider fluid flow for force instead of only pressure?
-- TODO: Fix rapid oscillation due to RPS feedback
-- TODO: Fix energy conservation: RPS -> flow -> RPS should be ~80% efficient
-- TODO: Add data output for mechanical load estimate / torque feedback
-- TODO: Add configurable limit for max. flow in L/s
-- TODO: Tune so that 1 L/s is about 100 RPS and vice-versa
-- TODO: Implement efficiency losses
-- TODO: Handle gases:
--       - either handle them as a regular fluid,
--       - or let them pass freely through the component without affecting flow/rps
--       - or pass them to a third fluid slot, as a gas relief valve
--       - or just delete gases
--       - note: we need to figure out how real hydraulic motors handle gases in the system

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
local MASS = 6 -- Base torque; twice that of a small electric motor
local FLUID_MASS = 1.0
local RPS_FACTOR = 100
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
	local mass = MASS * force
	local rps_after, _ = component.slotTorqueApplyMomentum(RPS_SLOT, mass, target_rps)
	return rps_after
end

---@param rps number
---@return number
local function rpsToFlowAmount(rps)
	--return (rps / TICK_RATE) / RPS_FACTOR -- RPS -> rotation per tick -> fluid per tick
	return rps / TICK_RATE
end

---@param flow_amount number
---@return number
local function flowAmountToRPS(flow_amount)
	-- return flow_amount * TICK_RATE * RPS_FACTOR -- Fluid per tick -> Fluid per second -> RPS
	return flow_amount * TICK_RATE
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

	-- Resolve the fluid flow for the volumes connected to the slots
	-- so that the amounts and pressures are in sync with the input/output slots
	resolveFluidVolumeFlow(FLUID_SLOT_A, FLUID_VOLUME_A)
	resolveFluidVolumeFlow(FLUID_SLOT_B, FLUID_VOLUME_B)

	local external_rps = getRPS()

	-- TODO: Fix:
	--       - If external_rps is zero, and is still zero after we've called setRPS(net_rps),
	--         then this means a huge load is attached that is preventing the motor from moving.
	--         This should completely block fluid flow, but currently fluid still passes through.
	--         We should store the rps_after value in a rps_prev_tick variable, and use that
	--         to calculate the load.

	local amount_a = getAmount(FLUID_VOLUME_A)
	local amount_b = getAmount(FLUID_VOLUME_B)
	local balance_amount = getFluidBalanceAmount(amount_a, amount_b)

	-- Calculate the pump flow generated by the external RPS
	local pump_rps = external_rps
	local pump_amount = rpsToFlowAmount(pump_rps)
	local pump_amount_clamped = clampTransferAmount(pump_amount, amount_a, amount_b)
	local pump_rps_clamped = rpsToFlowAmount(pump_amount_clamped)
	-- TODO: Use difference between pump_rps and pump_amount_clamped to slow down external_rps

	local net_amount = balance_amount - pump_amount_clamped

	-- Calculate the motor RPS generated by the fluid balance flow
	-- local motor_rps = flowAmountToRPS(balance_amount)
	-- local motor_rps = flowAmountToRPS(net_amount)

	-- Calculate net amounts to cancel out opposing forces and to factor in helping forces
	-- local net_rps = motor_rps - pump_rps_clamped
	-- local net_rps = motor_rps

	local motor_amount = balance_amount
	local motor_amount_clamped = clampTransferAmount(motor_amount, amount_a, amount_b)
	local motor_rps = flowAmountToRPS(motor_amount_clamped)
	local net_rps = motor_rps - pump_rps_clamped

	-- TODO: Fix: Add flow constraint; the amount added/removed can never exceed the limits
	--       of the volumes.
	--
	--       For example, if the external_rps causes the pump_amount to exceed the possible pump amount,
	--       then the pumped amount should be limited to that max. amount, and the RPS should be slowed
	--       down to fit in that constraint as well.
	--
	--       When transferring fluid from volume A, then:
	--       - the amount can never be more than what volume A can contain
	--       - and the amount can never be more than what volume B contains
	--       And when transferring fluid from volume B, then:
	--       - the amount can never be more than what volume B can contain
	--       - and the amount can never be more than what volume A contains
	--
	--       So, this means:
	--       - The RPS of the shaft is limited by the amount of fluid that can be transferred.
	--       - The max. amount of fluid that is transferred by the shaft's pumping action is limited by the
	--         size of the volumes and the amounts in the volumes.

	transferFluid(net_amount)
	local amount_a_after = getAmount(FLUID_VOLUME_A)
	local amount_b_after = getAmount(FLUID_VOLUME_B)
	local balance_after = getFluidBalanceAmount(amount_a_after, amount_b_after)

	-- Calculate the force/torque/mass/inertia, based on the amount of fluid (pressure) in the system
	local force = ((amount_a + amount_b) / 2) * FLUID_MASS

	local rps_after = setRPS(net_rps, force)

	component.setOutputLogicSlotComposite(DATA_OUT_SLOT, {
		bool_values = {},
		float_values = {
			[1] = balance_amount,
			[2] = pump_amount,
			[3] = motor_rps,
			[4] = pump_rps,
			[5] = net_rps,
			[6] = net_amount,
			[7] = nil, --target_rps,
			[8] = rps_after,
			[9] = balance_after,
			[10] = amount_a,
			[11] = amount_b,
			[12] = amount_a_after,
			[13] = amount_b_after,
		},
	})
end
