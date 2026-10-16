--!strict
--[[
	DeviceClass: which of the three first-class targets the client is laid
	out for (docs/design/feel.md section 1), as plain functions. The client
	binder asks again whenever the viewport's size or the last input kind
	changes (a rotation, a window resize, a keyboard on a tablet).

	  PC      the last input was a pointer, a keyboard or a mouse (or a gamepad,
	          which uses the PC layout until it has its own)
	  Phone   touch, and the viewport's shorter side is under 600 units
	  Tablet  touch, and the shorter side is 600 units or more

	  inputKind(name)              the Input kind of a UserInputType's or
	                               PreferredInput's name; nil for inputs
	                               that say nothing about the device
	  starting(preferred, touch, keyboard)
	                               the Input kind before any input
	  pick(input, width, height)   the Device class
	  portrait(width, height)      whether the viewport is taller than wide
]]

export type DeviceClass = "PC" | "Phone" | "Tablet"
-- A keyboard or a mouse is a pointer; gamepad is kept apart for its layout to come.
export type InputKind = "pointer" | "touch" | "gamepad"

local DeviceClass = {}

-- The phone/tablet boundary: a touch viewport whose shorter side is under
-- this many units is a Phone.
DeviceClass.PHONE_SHORTER_SIDE = 600

-- The UserInputType and PreferredInput names each Input kind is reported
-- by. Mouse movement is left out on purpose: some touch screens report it
-- for a tap, and a stray one must not flip a tablet to the PC layout.
local KINDS: { [string]: InputKind } = {
	Keyboard = "pointer",
	KeyboardAndMouse = "pointer",
	TextInput = "pointer",
	MouseButton1 = "pointer",
	MouseButton2 = "pointer",
	MouseButton3 = "pointer",
	MouseWheel = "pointer",
	Touch = "touch",
}

function DeviceClass.inputKind(name: string): InputKind?
	return KINDS[name] or if string.match(name, "^Gamepad%d*$") then "gamepad" else nil
end

-- The Input kind before any input: the device's preferred input's, or
-- touch for a touch screen with no keyboard.
function DeviceClass.starting(preferred: string?, touchEnabled: boolean, keyboardEnabled: boolean): InputKind
	local kind: InputKind? = if preferred then DeviceClass.inputKind(preferred) else nil
	if kind then
		return kind
	elseif touchEnabled and not keyboardEnabled then
		return "touch"
	end
	return "pointer"
end

function DeviceClass.pick(input: InputKind, width: number, height: number): DeviceClass
	if input ~= "touch" then
		return "PC"
	end
	return if math.min(width, height) < DeviceClass.PHONE_SHORTER_SIDE then "Phone" else "Tablet"
end

function DeviceClass.portrait(width: number, height: number): boolean
	return height > width
end

return DeviceClass
