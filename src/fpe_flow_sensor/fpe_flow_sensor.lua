local observable = require("sw-lua-lib/observer/simple_observable")
local DotMatrixDisplay = require("../lib/dot_matrix_display")
local createTimer = require("sw-lua-lib/timer/callback_timer")
local clamp = require("sw-lua-lib/extramath/clamp")
local EMAFilter = require("sw-lua-lib/dsp/exponential_moving_average")

local FILTERS = require("../lib/fluid_filters")
local FILTERS_ALL = FILTERS.ALL
local FLUID_TYPES = require("../lib/fluid_types")

local SETTINGS_SLOT = 0
local ELECTRIC_SLOT = 0
local DISPLAY_SLOT = 0
local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local FLOW_OUTPUT_SLOT = 0
local FLUID_VOLUME = 0
local FLUID_VOLUME_SIZE = 1.0 -- Liters

-- Conversion ratios: Fluid units per tick -> liter per second
local LIQUID_RATIO = 600
local GAS_RATIO = 36000 -- 10 * 60 * 60; 10 * ticks/sec * max atm?

local ELECTRIC_USAGE = 0.0005

local initialized = false
local powered = false
local errorState = false
local direction = 1

local FLUID_FILTER_TO_VOLUME_MAPPING = {
	-- Liquid:
	[FILTERS.WATER] = { type = FLUID_TYPES.WATER, ratio = LIQUID_RATIO },
	[FILTERS.DIESEL] = { type = FLUID_TYPES.DIESEL, ratio = LIQUID_RATIO },
	[FILTERS.JET] = { type = FLUID_TYPES.JET, ratio = LIQUID_RATIO },
	[FILTERS.OIL] = { type = FLUID_TYPES.OIL, ratio = LIQUID_RATIO },
	[FILTERS.SEA_WATER] = { type = FLUID_TYPES.SEA_WATER, ratio = LIQUID_RATIO },
	[FILTERS.SLURRY] = { type = FLUID_TYPES.SLURRY, ratio = LIQUID_RATIO },
	[FILTERS.SATURATED_SLURRY] = { type = FLUID_TYPES.SATURATED_SLURRY, ratio = LIQUID_RATIO },
	-- Gas:
	[FILTERS.AIR] = { type = FLUID_TYPES.AIR, ratio = GAS_RATIO },
	[FILTERS.CO2] = { type = FLUID_TYPES.CO2, ratio = GAS_RATIO },
	[FILTERS.STEAM] = { type = FLUID_TYPES.STEAM, ratio = GAS_RATIO },
	[FILTERS.O2] = { type = FLUID_TYPES.O2, ratio = GAS_RATIO },
	[FILTERS.N2] = { type = FLUID_TYPES.N2, ratio = GAS_RATIO },
	[FILTERS.H2] = { type = FLUID_TYPES.H2, ratio = GAS_RATIO },
}

local display = DotMatrixDisplay({ x = 0, y = 0, z = 0 }, 4)

---@return boolean
local function useEnergy()
	-- TODO: Extract to lib
	local chargeFactor, ok = component.slotElectricGetChargeFactor(ELECTRIC_SLOT)
	if ok and chargeFactor > ELECTRIC_USAGE then
		component.slotElectricRemoveCharge(ELECTRIC_SLOT, ELECTRIC_USAGE)
		return true
	else
		return false
	end
end

---@enum FlowSensorScaleMode
local SCALE_MODE = {
	sec = 1,
	min = 60,
	hour = 60 * 60,
}

---@param volumeIndex integer
---@param volumeSize number
---@param slotIn integer
---@param slotOut integer
---@return FlowSensor
local function FlowSensor(volumeIndex, volumeSize, slotIn, slotOut)
	---@class (exact) FlowSensor
	local instance = {}

	local flowRate = 0
	local scale = 1
	local enabled = false
	local smooth, updateSmoothing, resetSmoothing = EMAFilter({ alpha = 0.3 })
	local getVolumeContents = component.fluidContentsGetFluidTypeVolume

	function instance:init()
		component.fluidContentsSetCapacity(volumeIndex, volumeSize)
	end

	---@param fluidType integer
	---@param ratio number
	---@return number
	local function getAmount(fluidType, ratio)
		return (getVolumeContents(volumeIndex, fluidType) or 0) * ratio
	end

	---@return number flow Flow rate in L/s
	local function measureFlow()
		return 0.0
	end

	---@param alpha number EMA smoothing alpha [0..1]
	function instance:setSmoothing(alpha)
		updateSmoothing({ alpha = clamp(alpha, 0, 1) })
		resetSmoothing()
	end

	---@param scaleMode FlowSensorScaleMode Scaling mode for output values
	function instance:setScaleMode(scaleMode)
		scale = scaleMode
	end

	---@param bitmask integer Fluid type bitmask
	---@return boolean success
	--- Set the fluid types to measure.
	function instance:setFluidTypes(bitmask)
		if bitmask < 0 then
			-- Error: Invalid bitmask
			return false
		end

		local fluids = {}

		-- Extract the fluid types and ratios from the bitmask
		for filter, fluidData in pairs(FLUID_FILTER_TO_VOLUME_MAPPING) do
			if bitmask % (filter * 2) >= filter then -- Check if filter bit is in bitmask
				table.insert(fluids, fluidData)
			end
		end

		-- Pre-compile the measurement functions
		local funcs = {}
		for i = 1, #fluids do
			local fluid = fluids[i]
			local fluidType = fluid.type
			local fluidRatio = fluid.ratio
			local f = function()
				return getAmount(fluidType, fluidRatio)
			end
			table.insert(funcs, f)
		end

		measureFlow = function()
			local total = 0
			for i = 1, #funcs do
				total = total + funcs[i]()
			end
			return total
		end

		return true
	end

	---@param enable boolean
	function instance:setEnabled(enable)
		if enabled ~= enable then
			enabled = enable
			if not enabled then
				-- Reset smoothing and flow rate so values are correct when re-enabled
				flowRate = 0
				resetSmoothing()
			end
		end
	end

	function instance:resolveFlow()
		component.slotFluidResolveFlowToSlot(
			slotIn,
			slotOut,
			0, -- pump_pressure
			1, -- flow_factor
			false,
			FILTERS_ALL,
			volumeIndex
		)

		if enabled then
			flowRate = smooth(measureFlow())
		end
	end

	---@return number
	function instance:getFlowRate()
		return flowRate * scale
	end

	return instance
end

local flowSensor = FlowSensor(FLUID_VOLUME, FLUID_VOLUME_SIZE, FLUID_SLOT_A, FLUID_SLOT_B)

local _defaultText = "" ---@type string|number
local _, setDisplayText = observable(_defaultText, function(text)
	if powered then
		display:setText(text)
	end
end)

local _, setFluidTypeBitmask = observable(0, function(bitmask)
	local ok = flowSensor:setFluidTypes(bitmask)
	-- TODO: Improve error state handling; allow multiple errors
	errorState = not ok
end)

local function updateDisplay()
	if not errorState then
		setDisplayText(flowSensor:getFlowRate() * direction)
	else
		setDisplayText("ERR")
	end
end

local function makeDisplayUpdateTimer(fps)
	local interval = math.floor(62 / clamp(fps, 1, 62))

	return createTimer(interval, updateDisplay)
end

local displayUpdateTimer = makeDisplayUpdateTimer(2)

local _, setDisplayFPS = observable(2, function(fps)
	-- Rebuild the timer whenever the FPS setting changes
	displayUpdateTimer = makeDisplayUpdateTimer(fps)
end)

local _, setSmoothing = observable(0.3, function(alpha)
	flowSensor:setSmoothing(alpha)
end)

local _, setScaleMode = observable(SCALE_MODE.sec, function(newScale)
	local scale
	if newScale == 1 then
		scale = SCALE_MODE.sec
	elseif newScale == 2 then
		scale = SCALE_MODE.min
	elseif newScale == 3 then
		scale = SCALE_MODE.hour
	else
		-- TODO: Display 'ERR'
		return
	end
	flowSensor:setScaleMode(scale)
end)

local function updateSettings()
	local composite, ok = component.getInputLogicSlotComposite(SETTINGS_SLOT)
	if not ok then
		return
	end

	local boolValues = composite.bool_values

	display:setFlipped(boolValues[1])

	if boolValues[2] then -- Reverse mode
		direction = -1
	else
		direction = 1
	end

	local floats = composite.float_values
	setFluidTypeBitmask(floats[1])
	setSmoothing(floats[2])
	setScaleMode(floats[3])
	setDisplayFPS(floats[4])
end

function onTick(_)
	if not initialized then
		flowSensor:init()
		initialized = true
	end

	-- TODO: Display 'ERR' when fluid type bitmask is not set

	updateSettings()

	powered = useEnergy()

	flowSensor:setEnabled(powered)
	flowSensor:resolveFlow()

	display:setEnabled(powered and component.getInputLogicSlotBool(DISPLAY_SLOT))

	component.setOutputLogicSlotFloat(FLOW_OUTPUT_SLOT, flowSensor:getFlowRate())
end

function onRender()
	if initialized and powered then
		displayUpdateTimer()
		display:render()
	end
end
