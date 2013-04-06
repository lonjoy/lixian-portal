
path = require 'path'
fs = require 'fs'
lazy = require 'lazy'
cli = path.join __dirname, 'xunlei-lixian', 'lixian_cli.py'


{
  exec
  execFile
  spawn
} = require 'child_process'

statusMap = 
  completed: 'success'
  failed: 'error'
  waiting: 'warn'
  downloading: 'info'
statusMapLabel = 
  completed: '完成'
  failed: '失败'
  waiting: '等待'
  downloading: '下载中'

regexMG = /^([^ ]+) +(.+) +(completed|downloading|waiting|failed) *(http\:\/\/.+)?$/mg
regexQ = /^([^ ]+) +(.+) +(completed|downloading|waiting|failed) *(http\:\/\/.+)?$/m

exports.stats = stats = 
  retrieving: null
  error: {}
  speed: 'NaN'
  tasks: []
  requireLogin: false

exports.queue = queue = []
exports.log = log = []

exports.startCron = ->
  while true
    if queue.length
      item = queue[0]
      log.unshift  "#{item.name} 启动"
      await item.func defer e
      log.unshift "#{item.name} 完成"
      queue.shift()
      if e
        log.unshift e.message
        console.error e.message

    await setTimeout defer(), 100

queue.tasks = 
  retrieve: (task)->
    queue.push 
      name: "取回 #{task.id}"
      func: (cb)->
        stats.retrieving = spawn cli, ['download', '--continue', '--no-hash', '--delete', task.id], stdio: 'pipe'
        errBuffer = []
        stats.retrieving.task = task
        new lazy(stats.retrieving.stderr).lines.forEach (line)->
          line ?= []
          line = line.toString 'utf8'
          errBuffer.push line
          line = line.match /\s+(\d?\d%)\s+([^ ]{1,10})\s+([^ ]{1,10})\r?\n?$/
          [dummy, stats.progress, stats.speed, stats.time] = line if line

        await stats.retrieving.on 'exit', defer e
        if e
          stats.error[task.id] = errBuffer.join ''
        stats.retrieving = null
        queue.tasks.updateTasklist()
        cb()
          
  updateTasklist: ->
    queue.push
      name: '刷新任务列表'
      func: (cb)->
        await exec "#{cli} list --no-colors", defer e, out, err
        if e && err.match /user is not logged in/
          stats.requireLogin = true
          return cb e
        return cb e if e
        _tasks = []
        if out.match regexMG 
          for task in out.match regexMG
            task = task.match regexQ
            _tasks.push
              id: task[1]
              filename: task[2]
              status: statusMap[task[3]]
              statusLabel: statusMapLabel[task[3]]

        stats.tasks = _tasks
        
        for task in _tasks
          if task.status=='success' && !stats.error[task.id]?
            queue.tasks.retrieve task
        cb()
  deleteTask: (id)->
    queue.push
      name: "删除任务 #{id}"
      func: (cb)->
        await exec "#{cli} delete #{id}", defer e, out, err
        return cb e if e
        queue.tasks.updateTasklist()
        cb null

  login: (username, password)->
    queue.push
      name: "登录"
      func: (cb)->
        await exec "#{cli} config username #{username}", defer e, out, err
        return cb e if e
        await exec "#{cli} config password #{password}", defer e, out, err
        return cb e if e
        await exec "#{cli} login", defer e, out, err
        return cb e if e
        queue.tasks.updateTasklist()
        cb null
  addBtTask: (filename, torrent)->
    queue.push
      name: "添加bt任务 #{filename}"
      func: (cb)->
        await exec "#{cli} add #{torrent}", defer e, out, err
        return cb e if e
        queue.tasks.updateTasklist()
        cb null
  addTask: (url)->
    queue.push
      name: "添加任务 #{url}"
      func: (cb)->
        await exec "#{cli} add #{url}", defer e, out, err
        return cb e if e
        queue.tasks.updateTasklist()
        cb null

