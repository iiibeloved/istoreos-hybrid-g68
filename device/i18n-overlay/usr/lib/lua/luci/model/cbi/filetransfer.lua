--[[
 Copyright 2024 DustReliant
 Licensed to the public under the MIT License.
]]--

local m, s, o

m = Map("filetransfer", translate("文件传输设置"), translate("配置文件传输的系统参数"))

s = m:section(NamedSection, "config", "filetransfer", translate("基本设置"))

o = s:option(Value, "upload_dir", translate("上传目录"))
o.default = "/tmp/upload/"
o.description = translate("文件上传的默认目录")

o = s:option(Value, "max_file_size", translate("最大文件大小"))
o.default = "100"
o.datatype = "uinteger"
o.description = translate("单个文件最大大小（MB）")

o = s:option(Value, "allowed_extensions", translate("允许的文件类型"))
o.default = "ipk,tar,gz,zip,txt,conf,json,bin,img,sig,deb,rpm"
o.description = translate("允许上传的文件类型，用逗号分隔")

o = s:option(Value, "max_upload_sessions", translate("最大上传会话数"))
o.default = "5"
o.datatype = "uinteger"
o.description = translate("同时进行的上传会话数上限")

o = s:option(Value, "session_timeout", translate("会话超时"))
o.default = "3600"
o.datatype = "uinteger"
o.description = translate("上传会话超时时间（秒）")

s = m:section(NamedSection, "config", "filetransfer", translate("日志设置"))

o = s:option(ListValue, "log_level", translate("日志级别"))
o:value("debug", translate("调试"))
o:value("info", translate("信息"))
o:value("warning", translate("警告"))
o:value("error", translate("错误"))
o.default = "info"
o.description = translate("设置日志记录的详细程度")

o = s:option(Value, "log_retention", translate("日志保留"))
o.default = "30"
o.datatype = "uinteger"
o.description = translate("日志保留天数")

o = s:option(Flag, "auto_clean", translate("自动清理"))
o.default = "1"
o.description = translate("自动清理过期日志文件")

s = m:section(NamedSection, "config", "filetransfer", translate("安全设置"))

o = s:option(Flag, "enable_csrf", translate("启用 CSRF 防护"))
o.default = "1"
o.description = translate("启用跨站请求伪造防护")

o = s:option(Flag, "enable_ssl", translate("启用 SSL"))
o.default = "0"
o.description = translate("启用 SSL 加密")

o = s:option(Flag, "enable_file_validation", translate("启用文件内容校验"))
o.default = "1"
o.description = translate("使用魔数校验文件内容")

o = s:option(Value, "allowed_ips", translate("允许的 IP 地址"))
o.description = translate("允许访问的 IP 地址，逗号分隔（留空表示允许全部）")

return m 