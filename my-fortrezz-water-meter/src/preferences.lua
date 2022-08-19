local devices = {
  FORTREZZ = {
    MATCHING_MATRIX = {
      mfrs = 0x0084,
      product_types = 0x0473,
      product_ids = 0x0110
    },
    PARAMETERS = {
      reportRate = {parameter_number = 4, size = 1},
      highFlowRate = {parameter_number = 5, size = 1},
    }
  },
}

local preferences = {}

preferences.get_device_parameters = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.PARAMETERS
    end
  end
  return nil
end

preferences.to_numeric_value = function(new_value)
  local numeric = tonumber(new_value)
  if numeric == nil then -- in case the value is boolean
    numeric = new_value and 1 or 0
  end
  return numeric
end

return preferences