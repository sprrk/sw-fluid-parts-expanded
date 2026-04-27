-- Component details:
-- Type: pressure regulator
-- Regulates output pressure by moving fluid from input to output until
-- target pressure is achieved, or pressure is equalized.

local FILTERS = require("../lib/fluid_filters").ALL_LIQUIDS + require("../lib/fluid_filters").ALL_GASES
local PID = require("../lib/pid")
local DotMatrixDisplay = require("../lib/dot_matrix_display")
local clamp = require("sw-lua-lib/extramath/clamp")
local observable = require("sw-lua-lib/observer/simple_observable")

local FLUID_VOLUME_SIZE_BUFFER = 2.0 -- Liters

local ELECTRIC_USAGE = 0.0005

local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local FLUID_SLOT_SENSING_LINE = 2

local COMPOSITE_SLOT = 0
local TARGET_PRESSURE_SLOT = 0
local ELECTRIC_SLOT = 0
local DISPLAY_SLOT = 0

local FLUID_VOLUME_BUFFER = 0

local initialized = false
local powered = false
local backPressureMode = false
local fluidSlotIn = FLUID_SLOT_A
local fluidSlotOut = FLUID_SLOT_B

local targetPressure = 0

---@return boolean
local function useEnergy()
	local chargeFactor, ok = component.slotElectricGetChargeFactor(ELECTRIC_SLOT)
	if ok and chargeFactor > ELECTRIC_USAGE then
		component.slotElectricRemoveCharge(ELECTRIC_SLOT, ELECTRIC_USAGE)
		return true
	else
		return false
	end
end

local display = DotMatrixDisplay({ x = 0, y = 0, z = 0 }, 4)

---@type AdvancedPIDSettings
local pidSettings = {
	Kp = 1.0,
	Ki = 1.0,
	Kd = 0.01,
	min = 0,
	max = 1,
	b = 0.3,
	c = 0,
	derivativeSmoothing = 3,
	antiWindupMode = "backcalculation",
}

local pid = PID(pidSettings)

---@param pressure number
---@return nil
local function run(pressure)
	local flowFactor = pid:run(targetPressure, pressure)

	if backPressureMode then
		flowFactor = clamp(1 - flowFactor, 0, 1)
	end

	component.slotFluidResolveFlowToSlot(
		fluidSlotIn,
		fluidSlotOut,
		0.0, -- pump_pressure
		flowFactor,
		true, -- is_one_way
		FILTERS,
		-1 -- index_fluid_contents_transfer
	)
end

local _, setTargetPressure = observable(0.0, function(v)
	if v < 0 or v > 60 then
		display:setText("ERR")
		targetPressure = 0 -- Disable regulator if input is invalid
	else
		targetPressure = v
		display:setText(v)
	end
end)

local _, setReverseFlowMode = observable(false, function(newValue)
	if newValue then
		fluidSlotIn = FLUID_SLOT_B
		fluidSlotOut = FLUID_SLOT_A
	else
		fluidSlotIn = FLUID_SLOT_A
		fluidSlotOut = FLUID_SLOT_B
	end
end)

local _, setDisplayEnabled = observable(false, function(v)
	display:setEnabled(v)
end)

local _, updatePIDSettings = observable(false, function(newValue, oldValue)
	if not oldValue and newValue then -- Raising edge
		local composite, _ = component.getInputLogicSlotComposite(COMPOSITE_SLOT)
		local floatValues = composite.float_values
		pidSettings.Kp = floatValues[1]
		pidSettings.Ki = floatValues[2]
		pidSettings.Kd = floatValues[3]
		pid:updateSettings(pidSettings)
		pid:reset()
	end
end)

function onTick(_)
	if not initialized then
		component.fluidContentsSetCapacity(FLUID_VOLUME_BUFFER, FLUID_VOLUME_SIZE_BUFFER)
		display:setEnabled(false)
		display:setText(0.00)
		initialized = true
	end

	local composite, compositeOk = component.getInputLogicSlotComposite(COMPOSITE_SLOT)

	if compositeOk then
		local boolValues = composite.bool_values

		display:setFlipped(boolValues[1])
		backPressureMode = boolValues[2]
		setReverseFlowMode(boolValues[3])
		updatePIDSettings(boolValues[4])
	end

	setDisplayEnabled(component.getInputLogicSlotBool(DISPLAY_SLOT))

	powered = useEnergy()
	if powered then
		-- Read pressure from sensing line
		component.slotFluidResolveFlow(
			FLUID_SLOT_SENSING_LINE,
			FLUID_VOLUME_BUFFER,
			0, -- pump_pressure
			1.0, -- flow_factor
			false, -- is_one_way_in_to_slot
			false, -- is_one_way_out_of_slot
			FILTERS,
			-1 -- index_fluid_contents_transfer
		)
		local pressure = component.fluidContentsGetPressure(FLUID_VOLUME_BUFFER)

		local targetPressureInput = component.getInputLogicSlotFloat(TARGET_PRESSURE_SLOT)

		setTargetPressure(targetPressureInput)

		run(pressure)
	end
end

function onRender()
	if not initialized or not powered then
		return
	end

	display:render()
end
