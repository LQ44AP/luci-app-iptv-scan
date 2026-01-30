local m, s, iface, timeout, ranges, dict, city, m3u, txt, epg, run, stop

m = Map("iptv_scan", "IPTV 组播频道扫描", 
    "修改配置后请点击‘保存并应用’再开始扫描。")

s = m:section(TypedSection, "settings")
s.anonymous = true
s:tab("basic", "基础配置")
s:tab("log", "运行日志")

-- ================= 基础配置标签页 =================

iface = s:taboption("basic", ListValue, "interface", "扫描接口")
for _, n in ipairs(luci.sys.net.devices()) do
    if n ~= "lo" and not n:find("veth") then
        iface:value(n)
    end
end

timeout = s:taboption("basic", Value, "timeout", "超时(秒)")
timeout.default = "1.0"
timeout.datatype = "string" 

ranges = s:taboption("basic", DynamicList, "ranges", "网段范围", "格式 - 前缀:端口 (例: 239.1.0:8000)")

dict = s:taboption("basic", Value, "dict_file", "字典路径", "频道名称匹配库 (.txt), 内容格式:  频道名,rtp://ip:端口")
dict.datatype = "string"
dict.placeholder = "/root/iptv_dict.txt"

city = s:taboption("basic", Value, "city_file", "城市列表", "用于地方频道分类 (.txt)")
city.datatype = "string"
city.default = "/root/city_list.txt"

epg = s:taboption("basic", Value, "epg_url", "EPG 源地址", "用于 M3U 文件头的 x-tvg-url")
epg.default = "https://gitee.com/taksssss/tv/raw/main/epg/51zmt.xml.gz"

logo = s:taboption("basic", Value, "logo_base", "图标基础路径", "用于拼接 tvg-logo。格式 URL (如 http://addr/ ) 。")
logo.default = "https://gcore.jsdelivr.net/gh/taksssss/tv/icon/"
logo.placeholder = "https://gcore.jsdelivr.net/gh/taksssss/tv/icon/"

m3u = s:taboption("basic", Value, "m3u_file", "M3U 路径")
m3u.datatype = "string"
m3u.default = "/www/iptv.m3u"

txt = s:taboption("basic", Value, "txt_file", "TXT 路径")
txt.datatype = "string"
txt.default = "/www/iptv.txt"

prefix = s:taboption("basic", Value, "play_prefix", "播放前缀")
prefix.default = "rtp://"

-- ================= 任务操作按钮 =================

run = s:taboption("basic", Button, "_run", "任务操作")
run.inputtitle = "开始扫描"
run.inputstyle = "apply"
function run.write(self, section)
    if luci.http.formvalue(self:cbid(section)) then
        local is_running = luci.sys.call("pgrep -f iptv_scan.lua > /dev/null") == 0
        if is_running then
            luci.sys.call("echo \"[警告] 扫描任务已经在运行中...\" >> /tmp/iptv_scan.log")
        else
            luci.sys.call("echo \"[系统] 正在启动任务...\" > /tmp/iptv_scan.log")
            luci.sys.call("/usr/bin/lua /usr/bin/iptv_scan.lua >> /tmp/iptv_scan.log 2>&1 &")
        end
        luci.http.header("Referer", luci.http.getenv("HTTP_REFERER"))
    end
end

stop = s:taboption("basic", Button, "_stop", "终止扫描")
stop.inputtitle = "停止扫描"
stop.inputstyle = "reset"
function stop.write(self, section)
    if luci.http.formvalue(self:cbid(section)) then
        luci.sys.call("pkill -9 -f iptv_scan.lua >/dev/null 2>&1")
        luci.sys.call("rm -f /tmp/iptv_scan.lock")
        luci.sys.call("echo \"[系统] 已强制停止所有扫描进程。\" >> /tmp/iptv_scan.log")
        luci.http.header("Referer", luci.http.getenv("HTTP_REFERER"))
    end
end

-- ================= 日志标签页 =================

log_view = s:taboption("log", DummyValue, "_log")
log_view.template = "cbi/log_view"

return m
