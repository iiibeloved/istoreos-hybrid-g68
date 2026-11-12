local o = require "luci.sys"

a = Map("luci-app-control-webrestriction", translate("访问控制"), translate(
	"用黑名单或白名单模式控制列表中的客户端能否上网。"))
a.template = "webrestriction/index"

e = a:section(TypedSection, "basic", translate("运行状态"))
e.anonymous = true

t = e:option(DummyValue, "webrestriction_status", translate("运行状态"))
t.template = "webrestriction/webrestriction"
t.value = translate("正在收集数据…")

e = a:section(TypedSection, "basic", translate("全局设置"))
e.anonymous = true

t = e:option(Flag, "enable", translate("启用"))
t.rmempty = false

t = e:option(ListValue, "limit_type", translate("限制模式"))
t.default = "blacklist"
t:value("whitelist", translate("白名单"))
t:value("blacklist", translate("黑名单"))

e = a:section(TypedSection, "macbind", translate("列表设置"), translate(
	"黑名单模式：列表中的客户端禁止上网；白名单模式：仅列表中的客户端可以上网。"))
e.template = "cbi/tblsection"
e.anonymous = true
e.addremove = true

t = e:option(Flag, "enable", translate("启用"))
t.rmempty = false

t = e:option(Value, "macaddr", translate("MAC 地址"))
t.rmempty = true

o.net.mac_hints(function(e, a)
	t:value(e, "%s (%s)" % {e, a})
end)
return a
