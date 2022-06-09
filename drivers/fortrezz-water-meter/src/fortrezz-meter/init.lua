-- Copyright 2022 J.Constantelos
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
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=1 })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version=3 })
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"

local do_configure = function (self, device)
  device:send(Configuration:Set({parameter_number = 4, size = 1, configuration_value = 1})) -- Reporting Rate Threshhold
  device:send(Configuration:Set({parameter_number = 5, size = 1, configuration_value = 12})) -- High Flow Rate Threshhold
end

local fortrezz_meter = {
  lifecycle_handlers = {
    doConfigure = do_configure
  }
}

return fortrezz_meter
