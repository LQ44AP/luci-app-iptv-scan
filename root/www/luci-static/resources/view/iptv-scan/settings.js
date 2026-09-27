'use strict';
'require view';
'require form';
'require uci';
'require network';

return view.extend({
    load: function() {
        return Promise.all([
            uci.load('iptv_scan'),
            network.getDevices()
        ]);
    },

    render: function(data) {
        var devices = data[1] || [];
        var m, s, o;

        m = new form.Map('iptv_scan',
            _('IPTV 扫描设置'),
            _('配置组播扫描参数。修改后需点击“保存并应用”生效。'));

        // ===================== 基本设置 =====================
        s = m.section(form.NamedSection, '@settings[0]', 'settings',
            _('基本设置'));
        s.anonymous = true;

        // ===== 扫描接口（物理接口下拉）=====
        o = s.option(form.ListValue, 'interface',
            _('扫描接口'),
            _('选择用于发送组播加入请求的物理接口，如 eth0、lan1、eth0.2 等。'));
        o.rmempty = false;

        var seen = {};

        devices.forEach(function(dev) {
            if (!dev || typeof dev.getName !== 'function') return;
            var name = dev.getName();
            if (!name || name === 'lo' || seen[name]) return;
            seen[name] = true;

            var type = (typeof dev.getType === 'function') ? dev.getType() : '';
            var up   = (typeof dev.isUp === 'function') ? dev.isUp() : true;

            var label = name;
            if (type) label += ' [' + type + ']';
            if (!up)  label += ' (' + _('未连接') + ')';

            o.value(name, label);
        });

        // 兜底：若 UCI 中已有值不在设备列表中（如设备临时未插），仍保留为选项，避免保存时丢失
        var cur = uci.get('iptv_scan', '@settings[0]', 'interface');
        if (cur && !seen[cur]) {
            o.value(cur, cur + ' (' + _('当前值') + ')');
        }

        // ===== 其它基本设置 =====
        o = s.option(form.Value, 'timeout',
            _('接收超时（秒）'),
            _('等待组播响应的超时时间，默认 1 秒。'));
        o.datatype = 'ufloat';
        o.default = '1';

        o = s.option(form.Value, 'play_prefix',
            _('播放地址前缀'),
            _('生成 M3U 时使用的地址前缀，默认 rtp://。'));
        o.default = 'rtp://';

        // ===== EPG 地址（建议下拉 + 可自由输入）=====
        o = s.option(form.Value, 'epg_url',
            _('EPG 地址'),
            _('EPG 节目单地址。可从下拉建议中选择，或直接输入自定义 URL；留空则不写入 EPG 信息。'));
        o.value('https://gitee.com/taksssss/tv/raw/main/epg/51zmt.xml.gz',
                _('51zmt（Gitee）'));
        o.value('https://gcore.jsdelivr.net/gh/taksssss/tv/epg/51zmt.xml.gz',
                _('51zmt（jsDelivr）'));
        o.value('', _('不使用 EPG'));
        o.default = 'https://gitee.com/taksssss/tv/raw/main/epg/51zmt.xml.gz';
        o.rmempty = true;

        // ===== 台标基础路径 =====
        o = s.option(form.Value, 'logo_base',
            _('台标基础路径'),
            _('频道台标图片的基础 URL。可从下拉建议中选择，或直接输入自定义路径；留空则不生成 logo 属性。'));
        o.value('https://gcore.jsdelivr.net/gh/taksssss/tv/icon',
                _('taksssss/tv（jsDelivr）'));
        o.value('https://raw.githubusercontent.com/taksssss/tv/main/icon',
                _('taksssss/tv（GitHub Raw）'));
        o.value('https://gitee.com/taksssss/tv/raw/main/icon',
                _('taksssss/tv（Gitee）'));
        o.value('', _('不使用台标'));
        o.default = 'https://gcore.jsdelivr.net/gh/taksssss/tv/icon';
        o.rmempty = true;

        // ===================== 文件路径 =====================
        s = m.section(form.NamedSection, '@settings[0]', 'settings',
            _('文件路径'));
        s.anonymous = true;

        o = s.option(form.Value, 'dict_file',
            _('字典文件'),
            _('频道名称与组播地址的映射文件。'));
        o.default = '/root/iptv_dict.txt';
        o.rmempty = false;

        o = s.option(form.Value, 'city_file',
            _('城市列表文件'),
            _('用于地方频道归类城市关键词列表。'));
        o.default = '/root/city_list.txt';
        o.rmempty = false;

        o = s.option(form.Value, 'm3u_file',
            _('M3U 输出文件'),
            _('全量 M3U 播放列表输出路径。'));
        o.default = '/www/iptv.m3u';
        o.rmempty = false;

        o = s.option(form.Value, 'txt_file',
            _('TXT 输出文件'),
            _('TXT 格式播放列表输出路径。'));
        o.default = '/www/iptv.txt';
        o.rmempty = false;

        // ===================== 扫描网段 =====================
        s = m.section(form.NamedSection, '@settings[0]', 'settings',
            _('扫描网段'));
        s.anonymous = true;

        o = s.option(form.DynamicList, 'ranges',
            _('组播网段'),
            _('格式：前缀:端口，如 239.81.0.:8000。可添加多个网段。'));
        o.rmempty = false;

        return m.render();
    }
});