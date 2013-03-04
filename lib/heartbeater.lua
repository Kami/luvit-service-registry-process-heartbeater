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
local timer = require('timer')
local fmt = require('string').format

local async = require('async')

local ProcessHeartbeater = Object:extend()

function ProcessHeartbeater:initialize(pf, srClient, config, options)
  options = options and options or {}

  self._interval = options.interval and options.interval or 5000
  self._started = false
  self._timeoutId = nil
  self._activeProcesses = {} -- list of active pids
  self._heartbeaters = {} -- pid -> Heartbeater object

  self._pf = pf
  self._srClient = srClient
end

function ProcessHeartbeater:start()
  self._started = true
  self:schedule()
end

function ProcessHeartbeater:stop()
  self._started = false
  timer.clearTimer(self._timeoutId)
end

function ProcessHeartbeater:schedule()
  if not self._started then
    return
  end

  self._timeoutId = timer.setTimeout(self._interval, function()
    self:findNewAndDeadProcesses()
    self:schedule()
  end)
end

function ProcessHeartbeater:findNewAndDeadProcesses()
  local processes, process, configObject, pid
  processes = self._pf:findMatchingProcesses()

  for pid, pair in pairs(processes) do
    process = pair[1]
    configObject = pair[2]

    if self._activeProcesses[pid] == nil then
      -- New process, register it
      print('Found new process: ' .. tostring(pid))
      self:_registerProcess(process, configObject)
    end
  end

  for pid, _ in pairs(self._activeProcesses) do
    if processes[pid] == nil then
      -- This process is not active anymore, de-register it
      print('Found dead: ' .. tostring(pid))
      self:_deregisterProcess(pid)
    end
  end
end

function ProcessHeartbeater:_registerProcess(process, configObject)
  local pid = process:getPid()

  self._activeProcesses[pid] = process
  async.waterfall({
    function(callback)
      local heartbeatTimeout = configObject.heartbeat_timeout
      self._srClient.sessions:createSession(heartbeatTimeout, {}, callback)
    end,

    function(sessionId, _, hb, callback)
      local serviceId, metadata, payload

      serviceId = fmt('%s-%s', configObject['name'], pid)
      metadata = {
        ['pid'] = tostring(pid),
        ['ppid'] = tostring(process:getPpid()),
        ['name'] = configObject['name'],
        --['exe'] = process:getExe(),
        --['cwd'] = process:getCwd()
      }
      payload = {['metadata'] = metadata}

      self._srClient.services:createService(sessionId, serviceId, payload, function(err, res)
        callback(err, hb)
      end)
    end,

    function(hb, callback)
      self._heartbeaters[pid] = hb
      hb:start()
      callback()
    end
  },

  function(err)
    if err then
      print(err)
    end
  end)
end

function ProcessHeartbeater:_deregisterProcess(pid)
  local process, hb

  process = self._activeProcesses[pid]
  hb = self._heartbeaters[pid]

  hb:stop()

  self._activeProcesses[pid] = nil
  self._heartbeaters[pid] = nil
end

local exports = {}
exports.ProcessHeartbeater = ProcessHeartbeater
return exports
