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
    m.relationships = {}
    m.relationships.depends = {}
    m.relationships.depends.links = {}
    m.relationships.depends.links.self = string.format("%s/packages/%s/relationships/depends", self.conf.uri, pkg.id)
    m.relationships.provides = {}
    m.relationships.provides.links = {}
    m.relationships.provides.links.self = string.format("%s/packages/%s/relationships/provides", self.conf.uri, pkg.id)
    m.relationships.origins = {}
    m.relationships.origins.links = {}
    m.relationships.origins.links.self = string.format("%s/packages/%s/relationships/origins", self.conf.uri, pkg.id)
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

function model:packages(pkgs)
    local r = {}
    r.links = {}
    r.links.self = string.format("%s/packages", self.conf.uri) 
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