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
                error(turbo.web.HTTPError(400, "400 Bad request."))
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

function getPagerArguments(obj)
    local r,s = {},{}
    for k,v in ipairs(conf.pager.options) do
        local arg = obj:get_argument(string.format("page[%s]",v), false, true)
        if arg then s[v] = arg end
    end
    r.number = (tonumber(s.number) or 1) > 0 and s.number or 1
    r.limit = (s.size and tonumber(s.size) <= conf.pager.limit) and s.size or conf.pager.limit
    r.offset = r.number and (r.number-1)*r.limit or 0
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
    local sort = getSortArguments(self)
    local filter = getFilterArguments(self)
    local pager = getPagerArguments(self)
    local pkgs = self.options.aports:getPackages(filter, sort, pager)
    local args = self.request.arguments or {}
    if next(pkgs) then
        pager.qty = self.options.aports:getRowCount("packages")
        local json = self.options.model:packages(pkgs, pager, args)
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiRelationshipsDependsRenderer = class("ApiRelationshipsDependsRenderer", turbo.web.RequestHandler)

function ApiRelationshipsDependsRenderer:get(pid)
    local pkgs = self.options.aports:getDepends(pid)
    if next(pkgs) then
        local json = self.options.model:relationshipsPackages(pkgs, pid, "depends")
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiRelationshipsInstallIfRenderer = class("ApiRelationshipsInstallIfRenderer", turbo.web.RequestHandler)

function ApiRelationshipsInstallIfRenderer:get(pid)
    local pkgs = self.options.aports:getInstallIf(pid)
    if next(pkgs) then
        local json = self.options.model:relationshipsPackages(pkgs, pid, "install_if")
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiRelationshipsProvidesRenderer = class("ApiRelationshipsProvidesRenderer", turbo.web.RequestHandler)

function ApiRelationshipsProvidesRenderer:get(pid)
    local pkgs = self.options.aports:getProvides(pid)
    if next(pkgs) then
        local json = self.options.model:relationshipsPackages(pkgs, pid, "provides")
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiRelationshipsOriginsRenderer = class("ApiRelationshipsOriginsRenderer", turbo.web.RequestHandler)

function ApiRelationshipsOriginsRenderer:get(pid)
    local pkgs = self.options.aports:getOrigins(pid)
    if next(pkgs) then
        local json = self.options.model:relationshipsPackages(pkgs, pid, "origins")
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiRelationshipsPackagesRenderer = class("ApiRelationshipsPackagesRenderer", turbo.web.RequestHandler)

function ApiRelationshipsPackagesRenderer:get(pid)
    local pkg = self.options.aports:getPackage(pid)
    if pkg then
        local json = self.options.model:relationshipsContents(pkg, pid, "packages")
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiRelationshipsContentRenderer = class("ApiRelationshipsContentRenderer", turbo.web.RequestHandler)

function ApiRelationshipsContentRenderer:get(pid)
    local files = self.options.aports:getFiles(pid)
    if next(files) then
        local json = self.options.model:relationshipsContents(files, pid, "contents")
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiContentRenderer = class("ApiContentRenderer", turbo.web.RequestHandler)

function ApiContentRenderer:get(pid)
    local files = self.options.aports:getFiles(pid)
    if next(files) then
        local json = self.options.model:contents(pid, files)
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end

local ApiContentRenderer = class("ApiContentRenderer", turbo.web.RequestHandler)

function ApiContentRenderer:get(id)
    local cnt = self.options.aports:getContents(id)
    if cnt then
        local json = self.options.model:contents(cnt)
        self:add_header("Content-Type", "application/vnd.api+json")
        self:write(cjson.encode(json))
    else
        error(turbo.web.HTTPError(404, "404 Page not found."))
    end
end


function main()
    local aports = aports(conf)
    local format = aports:indexFormat()
    local model = model(conf, format)
    local update = function() aports:update() end
    turbo.web.Application({
        {"^/$", turbo.web.RedirectHandler, "/packages"},
        {"^/packages/(.*)/relationships/contents$", ApiRelationshipsContentRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)/relationships/origins$", ApiRelationshipsOriginsRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)/relationships/provides$", ApiRelationshipsProvidesRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)/relationships/depends$", ApiRelationshipsDependsRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)/relationships/install_if$", ApiRelationshipsInstallIfRenderer, {aports=aports,model=model}},
        {"^/packages/(.*)$", ApiPackageRenderer, {aports=aports,model=model}},
        {"^/contents/(.*)/relationships/packages$", ApiRelationshipsPackagesRenderer, {aports=aports,model=model}},
        {"^/contents/(.*)$", ApiContentRenderer, {aports=aports,model=model}},
        {"^/contents", ApiContentsRenderer, {aports=aports,model=model}},
        {"^/packages", ApiPackagesRenderer, {aports=aports,model=model}},
        {"favicon.ico", turbo.web.StaticFileHandler, "assets/favicon.ico"},
    }):listen(conf.port)
    local loop = turbo.ioloop.instance()
    --loop:add_callback(update)
    loop:set_interval(60000*conf.update, update)
    loop:start()
end

main()
