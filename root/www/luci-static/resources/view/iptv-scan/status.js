'use strict';
'require view';
'require rpc';
'require uci';
'require ui';
'require poll';

var callGetStatus = rpc.declare({
    object: 'luci.iptvscan',
    method: 'get_status',
    expect: { }
});

var callStartScan = rpc.declare({
    object: 'luci.iptvscan',
    method: 'start_scan',
    expect: { }
});

return view.extend({
    load: function() {
        return callGetStatus();
    },

    render: function(status) {
        var self = this;
        var logArea = E('pre', {
            'id': 'scan-log',
            'style': 'max-height: 500px; overflow-y: auto; background: #1e1e1e; color: #d4d4d4; padding: 12px; border-radius: 4px; font-size: 12px; line-height: 1.5; white-space: pre-wrap;'
        }, status.log || _('暂无日志'));

        var statusBadge = E('span', {
            'id': 'scan-status',
            'class': 'label',
            'style': status.running
                ? 'background: #28a745; color: #fff; padding: 2px 8px; border-radius: 3px;'
                : 'background: #6c757d; color: #fff; padding: 2px 8px; border-radius: 3px;'
        }, status.running ? _('运行中') : _('空闲'));

        var startBtn = E('button', {
            'class': 'btn cbi-button cbi-button-apply',
            'click': ui.createHandlerFn(self, function() {
                startBtn.disabled = true;
                startBtn.textContent = _('启动中...');
                return callStartScan().then(function(res) {
                    if (res.error) {
                        ui.addNotification(null, E('p', {}, res.error), 'error');
                    } else {
                        ui.addNotification(null,
                            E('p', {}, _('扫描任务已启动')), 'info');
                    }
                    startBtn.disabled = false;
                    startBtn.textContent = _('开始扫描');
                    self.refreshStatus();
                }).catch(function(e) {
                    ui.addNotification(null,
                        E('p', {}, _('启动失败：') + e.message), 'error');
                    startBtn.disabled = false;
                    startBtn.textContent = _('开始扫描');
                });
            })
        }, _('开始扫描'));

        var refreshBtn = E('button', {
            'class': 'btn cbi-button',
            'click': ui.createHandlerFn(self, function() {
                self.refreshStatus();
            })
        }, _('刷新'));

        // 自动轮询状态（每 3 秒）
        poll.add(function() {
            return self.refreshStatus();
        }, 3);

        return E('div', { 'class': 'cbi-map' }, [
            E('h2', {}, _('IPTV 扫描状态')),
            E('div', {
                'class': 'cbi-section',
                'style': 'margin-bottom: 16px;'
            }, [
                E('div', {
                    'style': 'display: flex; align-items: center; gap: 12px; margin-bottom: 12px;'
                }, [
                    E('strong', {}, _('当前状态：')),
                    statusBadge,
                    startBtn,
                    refreshBtn
                ])
            ]),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', {}, _('扫描日志')),
                logArea
            ])
        ]);
    },

    refreshStatus: function() {
        var self = this;
        return callGetStatus().then(function(res) {
            var badge = document.getElementById('scan-status');
            var log = document.getElementById('scan-log');
            if (badge) {
                badge.textContent = res.running ? _('运行中') : _('空闲');
                badge.style.background = res.running ? '#28a745' : '#6c757d';
            }
            if (log) {
                log.textContent = res.log || _('暂无日志');
                log.scrollTop = log.scrollHeight;
            }
        });
    }
});