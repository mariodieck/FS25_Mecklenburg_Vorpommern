SC_PayFineEvent = {}
SC_PayFineEvent_mt = Class(SC_PayFineEvent, Event)

InitEventClass(SC_PayFineEvent, "SC_PayFineEvent")

function SC_PayFineEvent.emptyNew()
	local self = Event.new(SC_PayFineEvent_mt)
	return self
end

function SC_PayFineEvent.new(fineHeight, farmId)
	local self = SC_PayFineEvent.emptyNew()
	self.fine = fineHeight
    self.farmId = farmId

	return self
end

function SC_PayFineEvent:readStream(streamId, connection)
	assert(g_currentMission:getIsServer())
	self.fine = streamReadFloat32(streamId)
	self.farmId = streamReadInt32(streamId)
    self:run(connection)
end

function SC_PayFineEvent:writeStream(streamId, connection)
	streamWriteFloat32(streamId, self.fine)
	streamWriteInt32(streamId, self.farmId)
end

function SC_PayFineEvent:run(connection)
    if not connection:getIsServer() then
        g_currentMission:addMoney(self.fine, self.farmId, MoneyType.OTHER)
    else
        print("Error: run-method of SpeedCamera executed on client");
    end
end
