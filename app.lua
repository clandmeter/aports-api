local inspect   = require("inspect")
local turbo     = require("turbo")
local config    = require("config")
local aports    = require("aports")


function main()
    local aports = aports(config)
    aports:update()
end

main()
