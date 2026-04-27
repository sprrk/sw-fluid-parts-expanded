---@alias AdvancedPIDAntiWindupMode
---| "clamp"           -- Default: bounds integral to available headroom
---| "backcalculation" -- Reset integral to exact saturation value
---| "freeze"          -- Stop integral update during saturation

---@class AdvancedPIDSettings
---@field Kp number Proportional gain. Higher = faster response, more oscillation
---@field Ki number Integral gain. Higher = faster steady-state error elimination, more windup
---@field Kd number Derivative gain. Higher = more damping, more noise sensitivity
---@field min number Output lower bound (saturation limit)
---@field max number Output upper bound (saturation limit). Must be > min
---@field b number? Setpoint weight on P, range [0..1] (default: 1). Use 0 for no kick on SP change, 1 for tracking
---@field c number? Setpoint weight on D, range [0..1] (default: 0). Use 0 for no kick on SP change (recommended), 1 for rare cases
---@field derivativeSmoothing number? Derivative smoothing in ticks, 1=instant/noisy, higher=smoother/slower (default: 3)
---@field antiWindupMode AdvancedPIDAntiWindupMode? Anti-windup strategy (default: "clamp")

---@param settings AdvancedPIDSettings
---@return AdvancedPID
--- A PID controller. Example usage:
--- local pid = PID({ Kp = 0.5, Ki = 1.0, Kd = 0.01, min = 0, max = 1, b = 0.3, c = 0, derivativeSmoothing = 3 })
--- local output = pid:run(setpoint, processVariable)
local function AdvancedPID(settings)
	---@class (exact) AdvancedPID
	local instance = {}

	local integral = 0
	local prevErrorForD = nil -- stores (c*sp - pv) from previous call
	local prevFilteredDerivative = 0
	local derivativeAlpha ---@type number

	local _min, _max = math.min, math.max

	local DT = 1 / 62 -- The game normally runs at 62 ticks per second.

	local Kp ---@type number
	local Ki ---@type number
	local Kd ---@type number
	local min ---@type number
	local max ---@type number
	local b ---@type number
	local c ---@type number
	local derivativeSmoothing ---@type number
	local antiWindupMode ---@type AdvancedPIDAntiWindupMode

	---@param newSettings AdvancedPIDSettings
	function instance:updateSettings(newSettings)
		Kp = newSettings.Kp
		Ki = newSettings.Ki
		Kd = newSettings.Kd
		min = newSettings.min
		max = newSettings.max
		b = newSettings.b or 1
		c = newSettings.c or 0
		derivativeSmoothing = _max(1, settings.derivativeSmoothing or 3)
		antiWindupMode = newSettings.antiWindupMode or "clamp"

		derivativeAlpha = 1 / (1 + derivativeSmoothing)
	end

	instance:updateSettings(settings) -- Initialize settings immediately on creation

	function instance:reset()
		integral = 0
		prevErrorForD = nil
		prevFilteredDerivative = 0
	end

	---@param sp number Setpoint
	---@param pv number Process variable
	---@return number proportional Proportional term
	local function _calculateProportional(sp, pv)
		-- Proportional term with setpoint weighting
		return Kp * b * (sp - pv)
	end

	---@param sp number Setpoint
	---@param pv number Process variable
	---@return number derivative Derivative term
	local function _calculateDerivative(sp, pv)
		-- Weighted error for derivative term: c*sp - pv
		-- When c=0: derivative acts on -pv (measurement only, no kick)
		-- When c=1: derivative acts on sp-pv = error (kick on SP change)
		local weightedErrorForD = c * sp - pv

		if prevErrorForD == nil then
			-- Initialize on first call to avoid derivative spike
			prevErrorForD = weightedErrorForD
		end

		local rawDerivative = (weightedErrorForD - prevErrorForD) / DT
		prevErrorForD = weightedErrorForD

		local filteredDerivative = prevFilteredDerivative + derivativeAlpha * (rawDerivative - prevFilteredDerivative)
		prevFilteredDerivative = filteredDerivative

		return Kd * filteredDerivative
	end

	---@param error number Error
	---@param proportional number Calculated P
	---@param derivative number Calculated D
	---@return number integral Integral term
	local function _calculateIntegralClamp(error, proportional, derivative)
		-- Output without integral for anti-windup clamping
		local outputWithoutIntegral = proportional + derivative

		-- Clamp integral to keep total output in bounds
		local integralMin = min - outputWithoutIntegral
		local integralMax = max - outputWithoutIntegral
		local newIntegral = integral + Ki * error * DT
		return _max(integralMin, _min(integralMax, newIntegral))
	end

	---@param error number Error
	---@param proportional number Calculated P
	---@param derivative number Calculated D
	---@return number integral Integral term
	local function _calculateIntegralBackcalculation(error, proportional, derivative)
		local output = proportional + integral + derivative

		if output > max then
			return max - proportional - derivative
		elseif output < min then
			return min - proportional - derivative
		else
			return integral + Ki * error * DT
		end
	end

	---@param error number Error
	---@param proportional number Calculated P
	---@param derivative number Calculated D
	---@return number integral Integral term
	local function _calculateIntegralFreeze(error, proportional, derivative)
		local output = proportional + integral + derivative

		if output > max or output < min then
			return integral -- frozen
		else
			return integral + Ki * error * DT
		end
	end

	---@param mode AdvancedPIDAntiWindupMode
	---@return fun(error: number, proportional: number, derivative: number): number
	local function _makeIntegralCalculationFunc(mode)
		if mode == "clamp" then
			return _calculateIntegralClamp
		elseif mode == "backcalculation" then
			return _calculateIntegralBackcalculation
		elseif mode == "freeze" then
			return _calculateIntegralFreeze
		else
			error("Unknown anti-windup mode: " .. tostring(mode))
		end
	end

	local _calculateIntegral = _makeIntegralCalculationFunc(antiWindupMode)

	---@param sp number Setpoint
	---@param pv number Process variable
	---@return number output Clamped controller output
	function instance:run(sp, pv)
		local proportional = _calculateProportional(sp, pv)
		local derivative = _calculateDerivative(sp, pv)

		local error = sp - pv
		integral = _calculateIntegral(error, proportional, derivative)

		local output = proportional + integral + derivative

		-- Numerical safety clamp
		return _max(min, _min(max, output))
	end

	return instance
end

return AdvancedPID
