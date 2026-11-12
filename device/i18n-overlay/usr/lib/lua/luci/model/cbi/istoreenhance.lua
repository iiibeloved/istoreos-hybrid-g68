local m, s

local istoreenhance_model = require "luci.model.istoreenhance"

m = Map("istoreenhance", translate("KSpeeder"), translate("KSpeeder 可修复一些网络问题，让 iStore 更好用。"))

m:section(SimpleSection).template  = "istoreenhance_status"

s=m:section(TypedSection, "istoreenhance", translate("全局设置"))
s.addremove=false
s.anonymous=true

s:option(Flag, "enabled", translate("启用")).rmempty=false

s:option(Value, "adminport", translate("管理端口")).rmempty=false

s:option(Value, "port", translate("端口")).rmempty=false

o = s:option(Value, "cache", translate("缓存路径").."<b>*</b>")
o.rmempty = false
o.datatype = "string"

local blocks = istoreenhance_model.blocks()
local home = istoreenhance_model.home()

local paths, default_path = istoreenhance_model.find_paths(blocks, home, "Configs")
for _, val in pairs(paths) do
  o:value(val, val)
end
o.default = default_path

return m


