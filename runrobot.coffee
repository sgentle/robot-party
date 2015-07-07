#!/usr/bin/env coffee
fs = require 'fs'
path = require 'path'

Robot = require './Robot.coffee.md'

safeReaddir = (dir) ->
  try
    fs.readdirSync dir
  catch
    null

getbot = (file) ->
  code = fs.readFileSync file, 'utf8'
  dir = file.replace(new RegExp("#{path.extname file}$"), '')
  if files = safeReaddir dir
    {
      code: code
      children: getbot path.join(dir, f) for f in files when path.extname(f) is '.bot'
    }
  else
    code

code = getbot process.argv[2]
console.log "code", code
new Robot code
