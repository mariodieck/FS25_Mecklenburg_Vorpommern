PlaceableSpeedDisplay = {
    modName = g_currentModName,
    baseXMLPath = "speedDisplay",
    specName = "placeableSpeedDisplay",
    prerequisitesPresent = function (specializations)
        return true
    end
}

PlaceableSpeedDisplay.specPath = "spec_" .. PlaceableSpeedDisplay.modName .. "." .. PlaceableSpeedDisplay.specName

function PlaceableSpeedDisplay.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "onSpeedDisplayTriggerCallback", PlaceableSpeedDisplay.onSpeedDisplayTriggerCallback)
    SpecializationUtil.registerFunction(placeableType, "setDisplayNumbers", PlaceableSpeedDisplay.setDisplayNumbers)
end

function PlaceableSpeedDisplay.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", PlaceableSpeedDisplay)
    SpecializationUtil.registerEventListener(placeableType, "onDelete", PlaceableSpeedDisplay)
    SpecializationUtil.registerEventListener(placeableType, "onUpdate", PlaceableSpeedDisplay)
    SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", PlaceableSpeedDisplay)
end

function PlaceableSpeedDisplay.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("SpeedDisplay")
    local baseXMLPath = basePath .. "." .. PlaceableSpeedDisplay.baseXMLPath
    local baseSavegamePath = basePath .. ".SpeedDisplay." .. PlaceableSpeedDisplay.specName

    schema:register(XMLValueType.NODE_INDEX,    baseXMLPath .. "#triggerNode", "Trigger of speed display. When driving thogh the speed is measured.")
    --schema:register(XMLValueType.NODE_INDEX,    baseXMLPath .. "#triggerMarkers", "Show trigger marker during placement to show where the trigger is. When placing hide trigger markers")
    schema:register(XMLValueType.INT,           baseXMLPath .. "#speedLimit", "The allowed speed limit of the vehicle. When Speed is higher than this the text will be in another color", 30)
    schema:register(XMLValueType.INT,           baseXMLPath .. "#duration", "How long the last speed is shown after the trigger is empty", 1)
    schema:register(XMLValueType.NODE_INDEX,    baseXMLPath .. ".display(?)#node", "Display start node")
	schema:register(XMLValueType.STRING,        baseXMLPath .. ".display(?)#font", "Display font name")
	schema:register(XMLValueType.STRING,        baseXMLPath .. ".display(?)#alignment", "Display text alignment")
	schema:register(XMLValueType.FLOAT,         baseXMLPath .. ".display(?)#size", "Display text size")
	schema:register(XMLValueType.FLOAT,         baseXMLPath .. ".display(?)#scaleX", "Display text x scale")
	schema:register(XMLValueType.FLOAT,         baseXMLPath .. ".display(?)#scaleY", "Display text y scale")
	schema:register(XMLValueType.STRING,        baseXMLPath .. ".display(?)#mask", "Display text mask")
	schema:register(XMLValueType.FLOAT,         baseXMLPath .. ".display(?)#emissiveScale", "Display emissive scale")
	schema:register(XMLValueType.COLOR,         baseXMLPath .. ".display(?)#colorFine", "Display text color when driving below the speed limit")
    schema:register(XMLValueType.COLOR,         baseXMLPath .. ".display(?)#colorTooFast", "Display text color when driving above the speed limit")
	schema:register(XMLValueType.COLOR,         baseXMLPath .. ".display(?)#hiddenColor", "Display text hidden color")

    schema:register(XMLValueType.INT,           baseSavegamePath .. "#speedLimit", "The allowed speed limit of the vehicle. When Speed is higher than this the text will be in another color. Value in placeables.xml", 30)

	schema:setXMLSpecializationType()
end
--load from xml file of the storeItem
function PlaceableSpeedDisplay:onLoad(savegame)
    local spec = self[PlaceableSpeedDisplay.specPath]
    local key = "placeable." .. PlaceableSpeedDisplay.baseXMLPath

    spec.trigger = self.xmlFile:getValue(key .. "#triggerNode", nil, self.components, self.i3dMappings)

    if spec.trigger == nil then
        Logging.xmlError(self.xmlFile, "missing vehicle trigger for speed display")

        return
    end

    addTrigger(spec.trigger, "onSpeedDisplayTriggerCallback", self)

    --spec.triggerMarkers = self.xmlFile:getValue(key .. "#triggerMarkers", nil, self.components, self.i3dMappings)

    --if spec.triggerMarkers == nil then
        --Logging.xmlWarning(self.xmlFile, "Missing trigger markers. User can't see trigger position during placement.")
    --else
        --setVisibility(spec.triggerMarkers, true)
    --end

    spec.speedLimit = self.xmlFile:getValue(key .. "#speedLimit", 30)
    spec.duration = self.xmlFile:getValue(key .. "#duration", 1)
    spec.duration = spec.duration * 1000
    spec.timer = 0
    spec.timerActivated = false

    spec.vehicle = nil -- No need to create an empty table here just use nil
    spec.displays = {}

    --load displays
    self.xmlFile:iterate(key .. ".display", function (_, displayKey)
        local displayNode = self.xmlFile:getValue(displayKey .. "#node", nil, self.components, self.i3dMappings)

		if displayNode ~= nil then
			local fontName = self.xmlFile:getValue(displayKey .. "#font", "DIGIT"):upper()
			local fontMaterial = g_materialManager:getFontMaterial(fontName, self.customEnvironment)

			if fontMaterial ~= nil then
				local display = {}
				local alignmentStr = self.xmlFile:getValue(displayKey .. "#alignment", "RIGHT")
				local alignment = RenderText["ALIGN_" .. alignmentStr:upper()] or RenderText.ALIGN_RIGHT
				local size = self.xmlFile:getValue(displayKey .. "#size", 1)
				local scaleX = self.xmlFile:getValue(displayKey .. "#scaleX", 1)
				local scaleY = self.xmlFile:getValue(displayKey .. "#scaleY", 1)
				local mask = self.xmlFile:getValue(displayKey .. "#mask", "00")
				local emissiveScale = self.xmlFile:getValue(displayKey .. "#emissiveScale", 0.2)
				local colorFine = self.xmlFile:getValue(displayKey .. "#colorFine", {
					0,
					1,
					0,
					1
				}, true)
                local colorTooFast = self.xmlFile:getValue(displayKey .. "#colorTooFast", colorFine, true)
				local hiddenColor = self.xmlFile:getValue(displayKey .. "#hiddenColor", nil, true)

				-- Using the same node will mean that the displays will flicker as changing visibility will affect both character lines.
				-- Solution is to clone the displayLine node and update separately
				-- NOTE: The parameters for 'clone' are 'objectId, groupUnderParent, callOnCreate, addPhysics' so by using 'groupUnderParent' the node is auto linked to the same location as displayNode
				display.displayNodeFine = displayNode
				display.displayNodeToFast = clone(displayNode, true, false, false)

				display.formatStr, display.formatPrecision = string.maskToFormat(mask)
				display.fontMaterial = fontMaterial

				-- Apply the new node ids so each characterLine is separate
				display.characterLineFine = fontMaterial:createCharacterLine(display.displayNodeFine, mask:len(), size, colorFine, hiddenColor, emissiveScale, scaleX, scaleY, alignment)
				display.characterLineTooFast = fontMaterial:createCharacterLine(display.displayNodeToFast, mask:len(), size, colorTooFast, hiddenColor, emissiveScale, scaleX, scaleY, alignment)

				table.insert(spec.displays, display)
			end
		end
    end)

    self:setDisplayNumbers(0)
end

--save to placeable xml of savegame
function PlaceableSpeedDisplay:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self[PlaceableSpeedDisplay.specPath]

    xmlFile:setInt(key .. "#speedLimit", spec.speedLimit or 30)
end

-- load from placeable xml of savegame
function PlaceableSpeedDisplay:loadFromXMLFile(xmlFile, key)
    local spec = self[PlaceableSpeedDisplay.specPath]

    spec.speedLimit = xmlFile:getInt(key .. "#speedLimit", 30)
end

function PlaceableSpeedDisplay:onDelete()
    local spec = self[PlaceableSpeedDisplay.specPath]

    if spec.trigger ~= nil then
        removeTrigger(spec.trigger)

        spec.trigger = nil
    end
end

function PlaceableSpeedDisplay:onUpdate(dt)
    local spec = self[PlaceableSpeedDisplay.specPath]

    if spec.timerActivated then
        spec.timer = spec.timer + dt

        if spec.timer > spec.duration then
            self:setDisplayNumbers(0)
            spec.timerActivated = false
            spec.timer = 0
            self:setDisplayNumbers(0)
        else
            self:raiseActive()
        end
    end
end

function PlaceableSpeedDisplay:onFinalizePlacement()
    local spec = self[PlaceableSpeedDisplay.specPath]

    --if spec.triggerMarkers ~= nil then
       --setVisibility(spec.triggerMarkers, false)
    --end
end

function PlaceableSpeedDisplay:setDisplayNumbers(speed)
    local spec = self[PlaceableSpeedDisplay.specPath]

    if speed <= 0 then
        for _, display in pairs(spec.displays) do
            setVisibility(display.displayNodeFine, false)
            setVisibility(display.displayNodeToFast, false)
        end
    else
        for _, display in pairs(spec.displays) do
            local int, floatPart = math.modf(speed)
            local value = string.format(display.formatStr, int, math.abs(math.floor(floatPart * 10^display.formatPrecision)))

			-- This will guarantee only one node is visible at a time
			local isSpeeding = speed > spec.speedLimit

			setVisibility(display.displayNodeFine, not isSpeeding)
			setVisibility(display.displayNodeToFast, isSpeeding)

			if isSpeeding then
				display.fontMaterial:updateCharacterLine(display.characterLineTooFast, value)
            else
				display.fontMaterial:updateCharacterLine(display.characterLineFine, value)
            end
        end
    end
end

function PlaceableSpeedDisplay:onSpeedDisplayTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    local spec = self[PlaceableSpeedDisplay.specPath]
	if onEnter or onLeave then
		local vehicle = g_currentMission:getNodeObject(otherId)

		-- Best to make sure its is a drivable vehicle  for enter and leave or anything leaving will clear the display.
		-- Also if the collision of the trigger uses BIT 20 then players would be detected and they do not have function 'getLastSpeed' so would cause error
		if vehicle ~= nil and vehicle.spec_drivable ~= nil then
			if onEnter then
				-- By using 'vehicle ~= spec.vehicle' also it will mean that the vehicle speed is only checked when it first enters the trigger, otherwise as each vehicle component (otherId) enters the speed will change.
				if vehicle ~= spec.vehicle then
                    spec.timerActivated = false
                    spec.timer = 0
					spec.vehicle = vehicle

					self:setDisplayNumbers(math.min(MathUtil.round(vehicle:getLastSpeed()), 99))
				end
			-- Only clear the speed if it is the same vehicle leaving that triggered the speed to start with
			elseif onLeave or vehicle == spec.vehicle then
				-- You should reset `spec.vehicle` to nil instead of using table constructors. when you use `{}` you are creating a new table each time and this is not a good practice in this situation.
				-- Using this in onEnter 'if spec.vehicle ~= {} then' will also be false every time as you are creating a new table using the constructors each time ;-)

				spec.vehicle = nil -- Set to nil
                spec.timerActivated = true
                self:raiseActive()
			    -- Only clear the speed if it is the same vehicle leaving that triggered the speed to start with
			end
		end
	end
end