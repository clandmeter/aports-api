local inspect   = require("inspect")
local turbo     = require("turbo")
local conf      = require("config")
local aports    = require("aports")
local cjson     = require("cjson")



function formatPackageAttributes(pkg)
    local r = {}
    for _,v in pairs(aports:jsonFormat()) do
        r[v] = pkg[v]
    end
    return r
end

function getPackageJson(pkg)
    local r = {}
    r.type = "packages"
    r.id = pkg.id
    pkg.maintainer = pkg.maintainer and string.format("%s <%s>", pkg.mname, pkg.memail) or nil
    r.attributes = formatPackageAttributes(pkg)
    r.links = {
        self = string.format("%s/packages/%s", conf.uri, pkg.id)
    }
    r.relationships = {}
    r.relationships.depends = {
        links = {
            self = {
                string.format("%s/packages/%s/relationships/depends", conf.uri, pkg.id)
            }
        }
    }
    r.relationships.required_by = {
        links={
            self={
                string.format("%s/packages/%s/relationships/required_by", conf.uri, pkg.id)
            }
        }
    }
    return r
end

function formatPackages(pkgs)
    local r = {}
    for _,pkg in pairs(pkgs) do
        table.insert(r, getPackageJson(pkg))
    end
    return r
end

---
-- Turbo Request handlers
---

local ApiPackageRenderer = class("ApiPackageRenderer", turbo.web.RequestHandler)

function ApiPackageRenderer:get(pid)
    local aports = self.options.aports
    local pkg = aports:getPackage(pid)
    if pkg then
        self:add_header("Content-Type", "application/vnd.api+json")
        local json = getPackageJson(pkg)
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiPackagesRenderer = class("ApiPackagesRenderer", turbo.web.RequestHandler)

function ApiPackagesRenderer:get()
    local aports = self.options.aports
    local pkgs = aports:getPackages()
    if next(pkgs) then
        local json = formatPackages(pkgs)
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiDependsRenderer = class("ApiDependsRenderer", turbo.web.RequestHandler)

function ApiDependsRenderer:get(pid)
    local aports = self.options.aports
    local pkgs = aports:getDepends(pid)
    if next(pkgs) then
        local json = formatPackages(pkgs)
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiRequredByRenderer = class("ApiRequredByRenderer", turbo.web.RequestHandler)

function ApiRequredByRenderer:get(pid)
    local aports = self.options.aports
    local pkgs = aports:getProvides(pid)
    if next(pkgs) then
        local json = formatPackages(pkgs)
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

function main()
    local aports = aports(conf)
    local update = function() aports:update() end
    turbo.web.Application({
        {"^/packages/(.*)/relationships/required_by$", ApiRequredByRenderer, {aports=aports}},
        {"^/packages/(.*)/relationships/depends$", ApiDependsRenderer, {aports=aports}},
        {"^/packages/(.*)$", ApiPackageRenderer, {aports=aports}},
        {"^/packages", ApiPackagesRenderer, {aports=aports}},
    }):listen(conf.port)
    local loop = turbo.ioloop.instance()
    loop:add_callback(update)
    loop:start()
end

main()
