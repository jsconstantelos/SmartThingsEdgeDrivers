-- Copyright 2022 JSConstantelos (original DTH), Mariano_Colmenarejo (DTH to Edge driver conversion!)
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=1 })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version=3 })
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 2 })

local preferencesMap = require "preferences"
local utils = require "st.utils"

---   Custom Capabilities definition Attributes for reference  only----
  --- laughbook63613.waterFlowRate, Attribute: waterFlowRate, Type: number, Units: gpm
  --- laughbook63613.gallonsLastUsed, Attribute: waterUsedLast, Type: number, Units: gals
  --- laughbook63613.totalGallonsUsed, Attribute: waterUsedTotal, Type: number, Units: gals 
  --- laughbook63613.highestWaterFlowRate, Attribute: waterFlowHighestRate, Type: number, Units: gpm
  --- laughbook63613.highestGallonsUsed, Attribute: waterUsedHighest, Type: number, Units: gals

---   Custom Capabilities declaration----
local cap_waterFlowRate = capabilities["laughbook63613.waterFlowRate"]
local cap_gallonsLastUsed = capabilities["laughbook63613.gallonsLastUsed"]
local cap_totalGallonsUsed = capabilities["laughbook63613.totalGallonsUsed"]
local cap_highestWaterFlowRate = capabilities["laughbook63613.highestWaterFlowRate"]
local cap_highestGallonsUsed = capabilities["laughbook63613.highestGallonsUsed"]

-- variables initialization
local delta = 0
local last_delta = 1  -- for only emit delta=0 one time
local last_waterFlowRate = 0   -- store the las state cpability
local last_waterUsedLast = 0   -- store the las state cpability
local last_waterUsedTotal = 0   -- store the las state cpability
local last_waterFlowHighestRate = 0   -- store the las state cpability
local last_waterUsedHighest = 0   -- store the las state cpability
local meter_reset = "No" --- allow emit attribute values after Meter reset


-- Alarm CC Report for power source and alarm HeatState
local function alarm_report_handler(driver, device, cmd)
  
  local alarm_type = cmd.args.z_wave_alarm_type
  print("alarm_type >>>>>",alarm_type)
  local alarm_event = cmd.args.z_wave_alarm_event
  print("alarm_event >>>>>",alarm_event)

  if alarm_type == 8 then --Power Alarm
    if alarm_event == 2 then  --AC Mains Disconnected
      print("alarmState: <<<< AC Mains Disconnected >>>>")
      device:emit_event(capabilities.powerSource.powerSource("battery"))
      
    elseif alarm_event == 3 then  -- AC Mains Reconnected
      print("alarmState: <<<< AC Mains Reconnected >>>>")
      device:emit_event(capabilities.powerSource.powerSource("mains"))

    elseif alarm_event == 0x0B then  -- Replace Battery Now
      print("alarmState: <<<< Replace Battery Now >>>>")

    elseif alarm_event == 0 then   -- Battery Replaced
      print("alarmState: <<<< Battery Replaced >>>>")

    end
  elseif alarm_type == 4 then
    if alarm_event == 0 then  -- Normal operation
      print("alarmState: <<<< Normal operation >>>>")

    elseif alarm_event == 01 then  -- overheated
      print("alarmState: <<<< overheated >>>>")

    elseif alarm_event == 05 then   -- Freezing Detected!
      print("alarmState: <<<< Freezing Detected! >>>>")

    end
  end
end

--- Meter handler for waterflow
local function meter_report_handler(self, device, cmd)
  print("cmd.args.meter_value >>>>",cmd.args.meter_value)
  print("cmd.args.previous_meter_value >>>>",cmd.args.previous_meter_value)

  -- Detect a Meter reset performed 
  if cmd.args.meter_value == 0 and cmd.args.previous_meter_value == 0 then -- this is a reset performed
    if meter_reset == "No" then
      print("<<<< Excute Reset All values to 0 >>>>")
      meter_reset = "Yes"
      device:emit_event_for_endpoint("main", cap_waterFlowRate.waterFlowRate(0))
      device:emit_event_for_endpoint("main", cap_totalGallonsUsed.waterUsedTotal(0))
      device:emit_event_for_endpoint("main", cap_highestWaterFlowRate.waterFlowHighestRate(0))
      device:emit_event_for_endpoint("main", cap_gallonsLastUsed.waterUsedLast(0))
      device:emit_event_for_endpoint("main", cap_highestGallonsUsed.waterUsedHighest(0))
    end
    return
  end

  delta = utils.round((((cmd.args.meter_value - cmd.args.previous_meter_value) / (device.preferences.reportRate * 10)) * 60)*100)/100

  if delta < 0 then --There should never be any negative values 
    print("<<< We just detected a negative delta value that won't be processed: ".. delta .." gpm >>>")
    return

  elseif delta > 60 then --There should never be any crazy high gallons as a delta, even at 1 minute reporting intervals.  It's not possible unless you're a firetruck.
    print("<<< We just detected a crazy high delta value that won't be processed: ".. delta .." gpm >>>")

    return
  end

  if delta == 0 then
    print("<<< Flow has stopped, so process what the meter collected >>>")

    last_waterUsedTotal = device:get_latest_state("main", cap_totalGallonsUsed.ID, cap_totalGallonsUsed.waterUsedTotal.NAME)
    if last_waterUsedTotal == nil then last_waterUsedTotal = 0 end
    if cmd.args.meter_value == last_waterUsedTotal then
      print("<<< Current and previous gallon values were the same, so skip processing >>>")
      if last_delta == 0 then
        return
      else
        last_delta = 0
      end
    elseif cmd.args.meter_value < last_waterUsedTotal then
      print("<<< Current gallon value is less than the previous gallon value and that should never happen, so skip processing >>>")
      return
    end

    local prevCumulative = cmd.args.meter_value - last_waterUsedTotal

    last_waterUsedHighest = device:get_latest_state("main", cap_highestGallonsUsed.ID, cap_highestGallonsUsed.waterUsedHighest.NAME)
    if last_waterUsedHighest == nil then last_waterUsedHighest = 0 end
    if prevCumulative > last_waterUsedHighest then
      local prevCumulative_format = tonumber(string.format("%.1f", prevCumulative))
      device:emit_event_for_endpoint("main", cap_highestGallonsUsed.waterUsedHighest(prevCumulative_format))

    end

    device:emit_event_for_endpoint("main", capabilities.waterSensor.water.dry())
    device:emit_event_for_endpoint("main", cap_waterFlowRate.waterFlowRate(delta))
    device:emit_event_for_endpoint("main", cap_totalGallonsUsed.waterUsedTotal(tonumber(string.format("%.1f",cmd.args.meter_value))))
    device:emit_event_for_endpoint("main", cap_gallonsLastUsed.waterUsedLast(tonumber(string.format("%.1f", prevCumulative))))

    return

  elseif delta > 0 and delta <= 60 then

    last_delta = delta -- for allow emit event if next delta = 0
    meter_reset = "No" -- Allow a emit values after new Meter Rest command

    device:emit_event_for_endpoint("main", cap_waterFlowRate.waterFlowRate(delta))
    print("<<< flowing at: ".. delta .." gpm >>>")
    device:emit_event_for_endpoint("main", capabilities.waterSensor.water.wet())

    last_waterFlowHighestRate = device:get_latest_state("main", cap_highestWaterFlowRate.ID, cap_highestWaterFlowRate.waterFlowHighestRate.NAME)
    if last_waterFlowHighestRate == nil then last_waterFlowHighestRate = 0 end
    if delta > last_waterFlowHighestRate then
      device:emit_event_for_endpoint("main", cap_highestWaterFlowRate.waterFlowHighestRate(delta))

      if delta > device.preferences.highFlowRate then
        print("alarmState: <<<< High Flow Detected! >>>>")
      else
        print("alarmState: <<<< Water is currently flowing >>>>")
      end
    end
  end

end

--- init lifecycle Handler
local function do_init (self, device)

  -- initialize values of capabilities
  last_waterFlowRate = device:get_latest_state("main", cap_waterFlowRate.ID, cap_waterFlowRate.waterFlowRate.NAME)
  if last_waterFlowRate == nil then last_waterFlowRate = 0 end

  last_waterUsedTotal = device:get_latest_state("main", cap_totalGallonsUsed.ID, cap_totalGallonsUsed.waterUsedTotal.NAME)
  if last_waterUsedTotal == nil then last_waterUsedTotal = 0 end

  last_waterFlowHighestRate = device:get_latest_state("main", cap_highestWaterFlowRate.ID, cap_highestWaterFlowRate.waterFlowHighestRate.NAME)
  if last_waterFlowHighestRate == nil then last_waterFlowHighestRate = 0 end

  last_waterUsedLast = device:get_latest_state("main", cap_gallonsLastUsed.ID, cap_gallonsLastUsed.waterUsedLast.NAME)
  if last_waterUsedLast == nil then last_waterUsedLast = 0 end

  last_waterUsedHighest = device:get_latest_state("main", cap_highestGallonsUsed.ID, cap_highestGallonsUsed.waterUsedHighest.NAME)
  if last_waterUsedHighest == nil then last_waterUsedHighest = 0 end
  
  -- change to selected profile single or multi tile
  if device.preferences.changeProfile == "Single" then
    device:try_update_metadata({profile = "base-water-meter"})
  elseif device.preferences.changeProfile == "Multi" then
    device:try_update_metadata({profile = "base-water-meter-multi"})
  end

end

-- device added lifecycle
local device_added = function (self, device)

  device:refresh()

  -- emit initial values
  if last_waterFlowHighestRate > device.preferences.highFlowRate then
    device:emit_event_for_endpoint("main", capabilities.waterSensor.water.wet())
  else
    device:emit_event_for_endpoint("main", capabilities.waterSensor.water.dry())
  end
  device:emit_event_for_endpoint("main", cap_waterFlowRate.waterFlowRate(last_waterFlowRate))
  device:emit_event_for_endpoint("main", cap_totalGallonsUsed.waterUsedTotal(last_waterUsedTotal))
  device:emit_event_for_endpoint("main", cap_highestWaterFlowRate.waterFlowHighestRate(last_waterFlowHighestRate))
  device:emit_event_for_endpoint("main", cap_gallonsLastUsed.waterUsedLast(last_waterUsedLast))
  device:emit_event_for_endpoint("main", cap_highestGallonsUsed.waterUsedHighest(last_waterUsedHighest))

end

-- Handler for preferences change
local function info_changed(driver, device, event, args)

  local preferences = preferencesMap.get_device_parameters(device)
  for id, value in pairs(device.preferences) do
    if args.old_st_store.preferences[id] ~= value and preferences and preferences[id] then
      print("Preference Changed >>>", id,"Old Value >>>>>>>>>",args.old_st_store.preferences[id], "Value >>", value)
      local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
      print(">>>>> parameter_number:",preferences[id].parameter_number,"size:",preferences[id].size,"configuration_value:",new_parameter_value)

      device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
    end

    --change profile tile
    if id == "changeProfile" then
      local oldPreferenceValue = device:get_field(id)
      local newParameterValue = device.preferences[id]
      if oldPreferenceValue ~= newParameterValue then
      device:set_field(id, newParameterValue, {persist = true})
      if device.preferences.changeProfile == "Single" then
        device:try_update_metadata({profile = "base-water-meter"})
      elseif device.preferences.changeProfile == "Multi" then
        device:try_update_metadata({profile = "base-water-meter-multi"})
      end
      end
    end
  end
   -- This will print in the log the total memory in use by Lua in Kbytes
   print("Memory >>>>>>>",collectgarbage("count"), " Kbytes")
end

--- Device doConfigure lifecycle
local do_configure = function (self, device)
  device:send(Configuration:Set({parameter_number = 4, size = 1, configuration_value = device.preferences.reportRate})) -- Reporting Rate Threshhold
  device:send(Configuration:Set({parameter_number = 5, size = 1, configuration_value = device.preferences.highFlowRate})) -- High Flow Rate Threshhold

end

--- Template driver configuration
local driver_template = {
  supported_capabilities = {
    capabilities.temperatureMeasurement,
    capabilities.waterSensor,
    capabilities.powerSource,
    capabilities.battery,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.refresh
  },
  lifecycle_handlers = {
    init = do_init,
    doConfigure = do_configure,
    added = device_added,
    infoChanged = info_changed,
  },
  zwave_handlers = {
    [cc.ALARM] = {
      [Alarm.REPORT] = alarm_report_handler
    },
    [cc.METER] = {
      [Meter.REPORT] = meter_report_handler
    }
  },
  sub_drivers = {
    --require("fortrezz-meter")
  }
}

-- Run driver
defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local waterMeter = ZwaveDriver("my-fortrezz-water-meter", driver_template)
waterMeter:run()
