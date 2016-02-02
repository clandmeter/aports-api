local inspect   = require("inspect")
local turbo     = require("turbo")
local conf      = require("config")
local aports    = require("aports")
local cjson     = require("cjson")
local model     = require("model")

function is_in(needle,haystack)
    if type(needle) == "string" and type(haystack) == "table" then
        for k,v in pairs(haystack) do
            if v == needle then return true end
        end
    end
end

function getFilterArguments(obj)
    local r = {}
    local format = obj.options.model:jsonFormat()
    for k,v in pairs(format) do
        local filter = string.format("filter[%s]",v)
        local arg = obj:get_argument(filter, false, true)
        if arg then r[v] = arg end
    end
    return r
end

function getSortArguments(obj)
    local r = {}
    local format = obj.options.model:jsonFormat()
    local sort = obj:get_argument("sort", false, true)
    if sort then
        -- check if we want to invert the sort order
        if sort:match("^-") then
            sort = sort:sub(2)
            r.order = "DESC"
        end
        -- check if column exists
        for i in sort:gmatch('[^,]+') do
            if not is_in(i,format) then
                return false
            end
        end
        r.sort = sort
        r.order = r.order or "ASC"
    else
        r.sort = conf.sort.default
        r.order = "ASC"
    end
    return r
end

function getPagerArguments(obj, max)
    local r,s = {},{}
    for k,v in ipairs(conf.pager.options) do
        local arg = obj:get_argument(string.format("page[%s]",v), false, true)
        if arg then s[v] = arg end
    end
    r.number = s.number or 1
    r.limit = (s.size and tonumber(s.size) <= conf.pager.limit) and s.size or conf.pager.limit
    r.offset = r.number+1 and r.number*r.limit or 0
    r.uri = obj.request.uri
    return r
end

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
    local filter = getFilterArguments(self)
    local sort = getSortArguments(self)
    if not sort then
        error(turbo.web.HTTPError(400, "400 Bad request."))
    end
    local pager = getPagerArguments(self)
    local pkgs = self.options.aports:getPackages(filter, sort, pager)
    local qty = self.options.aports:getRowCount("packages")
    if next(pkgs) then
        local json = self.options.model:packages(pkgs, qty, pager)
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
        local json = self.options.model:fields(pkgs, pid, "depends")
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiInstallIfRenderer = class("ApiInstallIfRenderer", turbo.web.RequestHandler)

function ApiInstallIfRenderer:get(pid)
    local pkgs = self.options.aports:getInstallIf(pid)
    if next(pkgs) then
        local json = self.options.model:fields(pkgs, pid, "install_if")
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiProvidesRenderer = class("ApiProvidesRenderer", turbo.web.RequestHandler)

function ApiProvidesRenderer:get(pid)
    local pkgs = self.options.aports:getProvides(pid)
    if next(pkgs) then
        local json = self.options.model:fields(pkgs, pid, "provides")
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiOriginsRenderer = class("ApiOriginsRenderer", turbo.web.RequestHandler)

function ApiOriginsRenderer:get(pid)
    local pkgs = self.options.aports:getOrigins(pid)
    if next(pkgs) then
        local json = self.options.model:fields(pkgs, pid, "origins")
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
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
        {"^/packages/(.*)/relationships/origins$", ApiOriginsRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)/relationships/provides$", ApiProvidesRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)/relationships/depends$", ApiDependsRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)/relationships/install_if$", ApiInstallIfRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)$", ApiPackageRenderer, {aports=aports,model=model}},
        {"^/packages", ApiPackagesRenderer, {aports=aports,model=model}},
        {"favicon.ico", turbo.web.StaticFileHandler, "assets/favicon.ico"},
    }):listen(conf.port)
    local loop = turbo.ioloop.instance()
    --loop:add_callback(update)
    loop:set_interval(60000*conf.update, update)
    loop:start()
end

main()
