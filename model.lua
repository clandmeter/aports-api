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

---
-- package model
---

function model:package(pkg, pid)
    local r = {}
    r.links = {}
    r.links.self = string.format("%s/packages/%s", self.conf.uri, pid)
    r.data = self:packageData(pkg)
    return r
end

function model:packageData(pkg)
    local m = {}
    m.type = "packages"
    m.id = tostring(pkg.id)
    pkg.maintainer = pkg.maintainer and string.format("%s <%s>", pkg.mname, pkg.memail) or nil
    m.attributes = self:packageAttributes(pkg)
    m.relationships = self:packagesRelationships(pkg.id)
    m.links = {}
    m.links.self = string.format("%s/packages/%s", self.conf.uri, pkg.id)
    return m
end

function model:packageAttributes(pkg)
    local r = {}
    for _,v in pairs(self:jsonFormat()) do
        r[v] = pkg[v]
    end
    return r
end

function model:packagesRelationships(pid)
    local m = {}
    local relationships = {"depends", "provides", "install_if", "origins", "contents"}
    for _,r in ipairs(relationships) do
        m[r] = {}
        m[r].links = {}
        m[r].links.self = string.format("%s/packages/%s/relationships/%s", self.conf.uri, pid, r)
    end
    return m
end

---
-- contents model
---

function model:contents(pid, files)
    local r = {}
    r.links = {}
    r.links.self = string.format("%s/contents/%s", self.conf.uri, pid)
    r.data = self:contentsData(pid, files)
    return r
end

function model:contentsData(pid, files)
    local m = {}
    m.type = "contents"
    m.id = tostring(pid)
    m.attributes = self:contentsAttributes(files)
    m.relationships = self:contentsRelationships(pid)
    return m
end

function model:contentsAttributes(files)
    local r = {}
    r.files = {}
    for _,v in ipairs(files) do
        table.insert(r.files, {path=v.path,file=v.file})
    end
    return r
end

function model:contentsRelationships(pid)
    local m = {}
    m.packages = {}
    m.packages.links = {}
    m.packages.links.self = string.format("%s/contents/%s/relationships/packages", self.conf.uri, pid)
    return m
end

---
-- links model
---

function model:arguments(args, nr)
    local r = {}
    for k,v in pairs(args) do
        if k == "page[number]" then v = tostring(nr) end
        table.insert(r, string.format("%s=%s",k,v:match("^%s*(.-)%s*$")))
    end
    return r
end

function model:links(pager, args)
    local l,r = {},{}
    l.first = 1
    l.last = math.floor(pager.qty/pager.limit)
    l.next = pager.number+1 > l.last and l.last or pager.number+1
    if l.next == l.last then l.next = nil end
    if pager.number-1 < 1 then l.prev = nil else l.prev = pager.number-1  end
    r.self = string.format("%s%s", self.conf.uri, pager.uri)
    if not args["page[number]"] then args["page[number]"] = 1 end
    for k,v in pairs(l) do
        local args = table.concat(self:arguments(args,v),"&")
        r[k] = string.format("%s/packages?%s",self.conf.uri, args)
    end
    return r
end

---
-- packages model
---

function model:packages(pkgs, pager, args)
    local r = {}
    r.links = self:links(pager, args)
    r.data = {}
    for _,pkg in pairs(pkgs) do
        table.insert(r.data, self:packageData(pkg))
    end
    return r
end

---
--  relationships model
---

function model:relationshipsPackages(pkgs, pid, type)
    local m = {}
    m.links = {}
    m.links.self = string.format("%s/packages/%s/relationships/%s", self.conf.uri, pid, type)
    m.data = {}
    for _,pkg in pairs(pkgs) do
        table.insert(m.data, self:packageData(pkg))
    end
    return m
end

function model:relationshipsContents(data, pid, type)
    local m = {}
    m.links = {}
    m.links.self = string.format("%s/contents/%s/relationships/%s", self.conf.uri, pid, type)
    if type == "packages" then
        m.data = self:packageData(data)
    elseif type == "contents" then
        m.data = {}
        for k,v in pairs(data) do
            table.insert(m.data, self:contentsData(v))
        end
    end
    return m
end

---
-- contents model
---


function model:contents(data)
    local r = {}
    r.links = {}
    r.links.self = string.format("%s/contents/%s", self.conf.uri, data.id)
    r.data = self:contentsData(data)
    return r
end

function model:contentsData(data)
    local m = {}
    m.type = "contents"
    m.id = tostring(data.id)
    m.attributes = self:contentsAttributes(data)
    m.relationships = self:contentsRelationships(data)
    m.links = self:contentsLinks(data)
    return m
end

function model:contentsAttributes(data)
    local r = {}
    r.file = data.file
    r.path = data.path
    return r
end

function model:contentsRelationships(data)
    local r = {}
    r.packages = {}
    r.packages.links = {}
    r.packages.links.self = string.format("%s/contents/%s/relationships/packages", self.conf.uri, data.id)
    return r
end

function model:contentsLinks(data)
    local r = {}
    r.self = string.format("%s/contents/%s", self.conf.uri, data.id)
    return r
end


return model
