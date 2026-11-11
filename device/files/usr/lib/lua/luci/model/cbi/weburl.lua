local o = require "luci.sys"

a = Map("luci-app-control-weburl", translate("URL 过滤"), translate(
	"在此设置关键字过滤，可以是 URL 中任意字符，如视频站、QQ、迅雷、淘宝等。"))
a.template = "weburl/index"

t = a:section(TypedSection, "basic", translate("运行状态"))
t.anonymous = true

e = t:option(DummyValue, "weburl_status", translate("运行状态"))
e.template = "weburl/weburl"
e.value = translate("正在收集数据…")

t = a:section(TypedSection, "basic", translate("基本设置"), translate(
	"通常普通过滤即可；强制过滤使用更复杂算法，CPU 占用更高。"))
t.anonymous = true

e = t:option(Flag, "enable", translate("启用"))
e.rmempty = false

e = t:option(Flag, "algos", translate("强制过滤"))
e.rmempty = false

t = a:section(TypedSection, "macbind", translate("关键字设置"), translate(
	"MAC 地址用于只对指定客户端过滤；过滤时间段可选。"))
t.template = "cbi/tblsection"
t.anonymous = true
t.addremove = true

e = t:option(Flag, "enable", translate("启用"))
e.rmempty = false

e = t:option(Value, "macaddr", translate("MAC 地址"))
e.rmempty = true

o.net.mac_hints(function(t, a)
	e:value(t, "%s (%s)" % {t, a})
end)

e = t:option(Value, "timeon", translate("开始时间"))
e.placeholder = "00:00"
e.rmempty = true

e = t:option(Value, "timeoff", translate("结束时间"))
e.placeholder = "23:59"
e.rmempty = true

e = t:option(Value, "keyword", translate("关键字"))
e.rmempty = false

return a
