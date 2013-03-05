--[[
Copyright Tomaz Muraus

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]

local Object = require('core').Object
local string = require('string')
local bind = require('utils').bind

local ProcessScanner = require('process_info').ProcessScanner

local ProcessFinder = Object:extend()

function ProcessFinder:initialize(config)
  self._config = config
  self._scanner = ProcessScanner:new()
end

-- Find processes which match a pattern defined in the config
function ProcessFinder:findMatchingProcesses()
  local processes, process, pid, configObject, result

  result = {}
  processes = self._scanner:getProcesses()

  for _, process in ipairs(processes) do
    configObject = self:_matchesPattern(process)

    if configObject then
      pid = process:getPid()
      result[pid] = {process, configObject}
    end
  end

  return result
end


-- Return true if process cmdline matches one of the defined patterns
function ProcessFinder:_matchesPattern(process)
  local cmdline, values, match, result

  for key, values in pairs(self._config) do
    status, cmdline = pcall(bind(process.getCmdline, process))

    if status then
      match = string.find(cmdline, values['pattern'])

      if match ~= nil then
        return values
      end
    end
  end

  return false
end

local exports = {}
exports.ProcessFinder = ProcessFinder
return exports
