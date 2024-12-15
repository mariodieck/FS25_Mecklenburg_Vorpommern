--[[
ModDesc!!!
<l10n>
    <text name="VehicleRadar_Default">
        <en>You got flashed too much with %1d.</en>
        <de>Du wurdest mit %1dkm/h zuviel geblitzt und musst %s bezahlen.</de>
     </text>
    <text name="VehicleRadar_info">
        <en>%s$ for to fast driving</en>
        <de>%s€ für zu schnelles Fahren</de>
    </text>
</ll0n>
]]
--©	[TWD]Rick Black Labele
--	tn47
SpeedCamera = {};

SpeedCamera.speedLimitTable = {}
SpeedCamera.costPerKMHTable = {}

SpeedCamera.dir = g_currentModDirectory;
local SpeedCamera_mt = Class(SpeedCamera);

function SpeedCamera.onCreate(id)
    --  g_currentMission:addNonUpdateable(SpeedCamera:new(id));
      g_currentMission:addUpdateable(SpeedCamera:new(id));
end

function SpeedCamera:new(id, customMt)
    local instance = {};
    if customMt ~= nil then
        setmetatable(instance, customMt);
    else
        setmetatable(instance, SpeedCamera_mt);
    end;
    instance.rootId = id;
    
    instance.triggerId = getChildAt(id, 0)
    local speedLimit = Utils.getNoNil(getUserAttribute(instance.triggerId, "speedLimit"), 50);
    local costPerKMH = Utils.getNoNil(getUserAttribute(instance.triggerId, "costPerKMH"), 50)*1.1;
    self.speedText = Utils.getNoNil(getUserAttribute(instance.triggerId, "speedText"), "VehicleRadar_Default");
    self.infoText = Utils.getNoNil(getUserAttribute(instance.triggerId, "infoText"), "VehicleRadar_info");

    addTrigger(instance.triggerId, "SpeedCameraCallback", instance);
	local flashLight = getUserAttribute(instance.rootId, "flashLight")
	if flashLight ~= nil then
		instance.flashLight = I3DUtil.indexToObject(instance.rootId, flashLight)
	end
	local realLight = getUserAttribute(instance.rootId, "realLight")
	if realLight ~= nil then
		instance.realLight = I3DUtil.indexToObject(instance.rootId, realLight)
	end
	instance.flashActive = false;

    self.count=0;
	
    table.insert(SpeedCamera.speedLimitTable, instance.triggerId, speedLimit)
    table.insert(SpeedCamera.costPerKMHTable, instance.triggerId, costPerKMH)

    return instance;
end

function SpeedCamera:update(dt)
	if self.flashActive then
		local intensity = 200;
		local _,y,z,w = getShaderParameter(self.flashLight, "lightControl")
		setShaderParameter(self.flashLight, "lightControl", intensity, y, z, w, false)
		setVisibility(self.realLight, true)
		self.flashActive = false;
	else
		local intensity = 0;
		local _,y,z,w = getShaderParameter(self.flashLight, "lightControl")
		setShaderParameter(self.flashLight, "lightControl", intensity, y, z, w, false)
		setVisibility(self.realLight, false)
	end;
end;

function SpeedCamera:delete()
    removeTrigger(self.triggerId);
end

function SpeedCamera:calculateCost(speed, triggerId)
    local cost;
    if(speed > 15) then
        cost=(speed*4-40)*SpeedCamera.costPerKMHTable[triggerId];
    else
        cost=(((-37625*math.pow(10,-10))*math.pow(speed,6))+((1609262*math.pow(10,-10))*math.pow(speed,5))+((-23444736*math.pow(10,-10))*math.pow(speed,4))+((144011223*math.pow(10,-10))*math.pow(speed,3))+((135190505*math.pow(10,-10))*math.pow(speed,2))+((4792206974*math.pow(10,-10))*speed)+(-5611455*math.pow(10,-10)))*SpeedCamera.costPerKMHTable[triggerId]+1;
    end
    return math.ceil(cost);
end

function SpeedCamera:checkSpeed(speedToCheck, triggerId)
    return SpeedCamera:calculateCost(speedToCheck-(SpeedCamera.speedLimitTable[triggerId]), triggerId);
end

function SpeedCamera:SpeedCameraCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    local vehicle = g_currentMission.nodeToObject[otherShapeId];
    if vehicle ~= nil and vehicle.spec_drivable ~= nil and vehicle.spec_enterable ~= nil and vehicle.spec_enterable.isEntered then
        local speed = vehicle:getLastSpeed();

        if onEnter then
			self.count=self.count+1;
            if speed > SpeedCamera.speedLimitTable[triggerId] and self.count == 1 then
				self.flashActive = true;
                local money = SpeedCamera:checkSpeed(speed, triggerId);
                g_currentMission:showBlinkingWarning((g_i18n:getText(self.speedText)):format((speed-SpeedCamera.speedLimitTable[triggerId]),g_i18n:formatNumber(money)));
                g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, (g_i18n:getText(self.infoText)):format(money))
                if g_currentMission:getIsServer() then
                    g_currentMission:addMoney(-money, vehicle:getActiveFarm(), MoneyType.OTHER, true);
                else
                    g_client:getServerConnection():sendEvent(SC_PayFineEvent:new(-money,vehicle))
                end
            end
        end
		
		if onLeave then
			self.count=self.count-1;
		end
    end
end

g_onCreateUtil.addOnCreateFunction("SpeedCamera", SpeedCamera.onCreate);
