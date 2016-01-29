local inspect   = require("inspect")
local turbo     = require("turbo")
local conf      = require("config")
local aports    = require("aports")
local cjson     = require("cjson")
local model     = require("model")


---
-- Turbo Request handlers
---

local ApiPackageRenderer = class("ApiPackageRenderer", turbo.web.RequestHandler)

function ApiPackageRenderer:get(pid)
    local pkg = self.options.aports:getPackage(pid)
    if pkg then
        self:add_header("Content-Type", "application/vnd.api+json")
        local json = self.options.model:package(pkg, pid)
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiPackagesRenderer = class("ApiPackagesRenderer", turbo.web.RequestHandler)

function ApiPackagesRenderer:get()
    local pkgs = self.options.aports:getPackages()
    if next(pkgs) then
        local json = self.options.model:packages(pkgs)
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiDependsRenderer = class("ApiDependsRenderer", turbo.web.RequestHandler)

function ApiDependsRenderer:get(pid)
    local pkgs = self.options.aports:getDepends(pid)
    if next(pkgs) then
        local json = self.options.model:depends(pkgs)
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiRequredByRenderer = class("ApiRequredByRenderer", turbo.web.RequestHandler)

function ApiRequredByRenderer:get(pid)
    local pkgs = self.options.aports:getProvides(pid)
    if next(pkgs) then
        local json = self.options.model:requiredBy(pkgs, pid)
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiFilesRenderer = class("ApiFilesRenderer", turbo.web.RequestHandler)

function ApiFilesRenderer:get(pid)
    local files = self.options.aports:getFiles(pid)
    if next(files) then
        local json = self.options.model:files(files)
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    end
end

function main()
    local aports = aports(conf)
    local format = aports:indexFormat()
    local model = model(conf, format)
    local update = function() aports:update() end
    turbo.web.Application({
        {"^/$", turbo.web.RedirectHandler, "/packages"},
        {"^/packages/(.*)/files$", ApiFilesRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)/relationships/required_by$", ApiRequredByRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)/relationships/depends$", ApiDependsRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)$", ApiPackageRenderer, {aports=aports,model=model}},
        {"^/packages", ApiPackagesRenderer, {aports=aports,model=model}},
        {"favicon.ico", turbo.web.StaticFileHandler, "assets/favicon.ico"},
    }):listen(conf.port)
    local loop = turbo.ioloop.instance()
    loop:add_callback(update)
    loop:start()
end

main()
