local m, s

m = Map("dockermanager", translate("Docker 管理器"), translate("Docker 管理器提供 LinkEase 桌面网页模块与 HTTP API，用于管理 Docker。"))
m:section(SimpleSection).template = "dockermanager_status"

s = m:section(TypedSection, "dockermanager", translate("全局设置"))
s.addremove = false
s.anonymous = true

s:option(Flag, "enabled", translate("启用")).rmempty = false

local data_dir = s:option(Value, "data_dir", translate("数据目录"))
data_dir.rmempty = false

local listen_mode = s:option(ListValue, "listen_mode", translate("监听模式"))
listen_mode:value("auto", translate("自动"))
listen_mode:value("unix", translate("Unix 套接字"))
listen_mode:value("tcp", translate("TCP 端口"))
listen_mode.default = "auto"
listen_mode.rmempty = false

local external_port_enabled = s:option(Flag, "external_port_enabled", translate("允许外部端口访问"))
external_port_enabled.default = "0"
external_port_enabled.rmempty = false

local socket_path = s:option(Value, "socket_path", translate("Unix 套接字路径"))
socket_path.default = "/var/run/dockermanager.sock"
socket_path.rmempty = false
socket_path.readonly = true

local port = s:option(Value, "port", translate("监听端口"))
port.default = "8192"
port.rmempty = false
port.datatype = "port"

local bind_addr = s:option(Value, "bind_addr", translate("绑定地址"))
bind_addr.default = "0.0.0.0"
bind_addr.rmempty = false

local base_path = s:option(Value, "base_path", translate("基础路径"))
base_path.default = "/apps/dockermanager/"
base_path.rmempty = false
base_path.readonly = true

return m
