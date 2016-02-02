local inspect = require("inspect")

local model = class("model")


function model:initialize(conf, format)
    self.conf = conf
    self.format = format
end

function model:jsonFormat(k)
    local f = self.format
    f.f = "files"
    f.r = "repo"
    f.b = "branch"
    return k and f[k] or f
end

function model:attributesModel(pkg)
    local r = {}
    for _,v in pairs(self:jsonFormat()) do
        r[v] = pkg[v]
    end
    return r
end

function model:packageModel(pkg)
    local m = {}
    m.type = "packages"
    m.id = pkg.id
    pkg.maintainer = pkg.maintainer and string.format("%s <%s>", pkg.mname, pkg.memail) or nil
    m.attributes = self:attributesModel(pkg)
    local relationships = {"depends", "provides", "install_if", "origins"}
    m.relationships = {}
    for _,r in ipairs(relationships) do
        m.relationships[r] = {}
        m.relationships[r].links = {}
        m.relationships[r].links.self = string.format("%s/packages/%s/relationships/%s", self.conf.uri, pkg.id, r)
    end
    m.links = {}
    m.links.self = string.format("%s/packages/%s", self.conf.uri, pkg.id)
    return m
end

function model:package(pkg, pid)
    local r = {}
    r.links = {}
    r.links.self = string.format("%s/packages/%s", self.conf.uri, pid) 
    r.data = self:packageModel(pkg)
    return r
end

function model:links(qty, pager)
    local last = math.floor(qty/pager.limit)
    local next = pager.number+1 > last and last or pager.number+1
    local prev = pager.number-1 < 1 and 1 or pager.number-1
    local r = {}
    r.self = string.format("%s%s", self.conf.uri, pager.uri)
    r.first = string.format("%s/packages?page[number]=1",self.conf.uri)
    r.prev = string.format("%s/packages?page[number]=%s",self.conf.uri,prev)
    r.next = string.format("%s/packages?page[number]=%s",self.conf.uri,next)
    r.last = string.format("%s/packages?page[number]=%s",self.conf.uri,last)
    return r
end

function model:packages(pkgs, qty, pager)
    local r = {}
    r.links = self:links(qty, pager)
    r.data = {}
    for _,pkg in pairs(pkgs) do
        table.insert(r.data, self:packageModel(pkg))
    end
    return r
end

function model:fields(pkgs, pid, type)
    local r = {}
    r.links = {}
    r.links.self = string.format("%s/packages/%s/relationships/%s", self.conf.uri, pid, type)
    r.data = {}
    for _,pkg in pairs(pkgs) do
        table.insert(r.data, self:packageModel(pkg))
    end
    return r
end

function model:files(files)
    local r = {}
    for _,file in ipairs(files) do
        table.insert(r, string.format("%s/%s", file.path, file.file))
    end
    return r
end

return model