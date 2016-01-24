local inspect   = require("inspect")
local turbo     = require("turbo")
local config    = require("config")
local aports    = require("aports")

aports:setRepositories(config.branches, config.repos, config.archs)
aports:setFields(config.db.fields)
aports:openDB()
aports:setMirror(config.mirror)
aports:setUri(config.uri)
aports:logging(config.logging)

aports:update()
