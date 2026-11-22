'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

var callGetStatus = rpc.declare({
    object: 'luci.iptvscan',
    method: 'get_status',
    expect: {}
});

var callStartScan = rpc.declare({
    object: 'luci.iptvscan',
    method: 'start_scan',
    expect: {}
});

return view.extend({
    load: function() {
        return callGetStatus().catch(function() {
            return { running: false, log: '' };
        });
    },

    render: function(status) {
        var self = this;
        status = status || {};

        var statusBadge = E('span', {
            'id': 'scan-status',
            'class': 'label',
            'style': this.badgeStyle(status.running)
        }, status.running ? _('运行中') : _('空闲'));

        var startBtn = E('button', {
            'id': 'scan-start-btn',
            'class': 'btn cbi-button cbi-button-apply',
            'click': function(ev) {
                ev.preventDefault();
                startBtn.disabled = true;
                startBtn.textContent = _('启动中...');
                callStartScan().then(function() {
                    ui.addNotification(null, E('p', {}, _('扫描任务已启动')), 'info');
                }).catch(function(e) {
                    ui.addNotification(null,
                        E('p', {}, _('启动失败：') + (e.message || e)), 'error');
                }).then(function() {
                    return self.refreshStatus();
                });
            }
        }, _('开始扫描'));
        startBtn.disabled = !!status.running;
        startBtn.textContent = status.running ? _('扫描中...') : _('开始扫描');

        var logBtn = E('button', {
            'class': 'btn cbi-button',
            'click': function(ev) {
                ev.preventDefault();
                self.handleViewLog();
            }
        }, _('查看日志'));

        var refreshBtn = E('button', {
            'class': 'btn cbi-button',
            'click': function(ev) {
                ev.preventDefault();
                self.refreshStatus();
            }
        }, _('刷新'));

        if (this.pollHandle) {
            poll.remove(this.pollHandle);
            this.pollHandle = null;
        }
        this.pollHandle = poll.add(L.bind(this.refreshStatus, this), 3);

        return E('div', { 'class': 'cbi-map' }, [
            E('h2', {}, _('IPTV 扫描状态')),
            E('div', { 'class': 'cbi-section', 'style': 'margin-bottom:16px;' }, [
                E('div', { 'style': 'display:flex;align-items:center;gap:12px;flex-wrap:wrap;' }, [
                    E('strong', {}, _('当前状态：')),
                    statusBadge,
                    startBtn,
                    logBtn,
                    refreshBtn
                ])
            ])
        ]);
    },

    applyStatus: function(res) {
        var badge = document.getElementById('scan-status');
        var btn   = document.getElementById('scan-start-btn');
        if (badge) {
            badge.textContent = res.running ? _('运行中') : _('空闲');
            badge.style.background = res.running ? '#28a745' : '#6c757d';
        }
        if (btn) {
            btn.disabled = !!res.running;
            btn.textContent = res.running ? _('扫描中...') : _('开始扫描');
        }
    },

    /* 点击才拉最新日志，无条件 showModal */
    handleViewLog: function() {
        var self = this;
        return callGetStatus().then(function(res) {
            res = res || {};
            self.applyStatus(res);
            var text = res.log || _('暂无日志');

            // 先把任何已打开的弹窗关掉，保证本次一定重新弹出
            try { ui.hideModal(); } catch (e) { /* ignore */ }

            // setTimeout(0) 让 hideModal 的 DOM 变更落盘后再 showModal
            window.setTimeout(function() {
                ui.showModal(_('扫描日志'), [
                    E('pre', {
                        'id': 'scan-log-modal',
                        'style': 'max-height:60vh; overflow:auto; white-space:pre-wrap;' +
                                 'font-size:12px; background:#ffffff; color:#000000;' +
		'border:1px solid #cccccc; padding:12px; border-radius:4px;' +
                                 'margin:0; font-family:monospace; line-height:1.5;'
                    }, text),
                    E('div', { 'class': 'right' }, [
                        E('button', {
                            'class': 'btn cbi-button cbi-button-neutral',
                            'click': ui.hideModal
                        }, _('关闭'))
                    ])
                ]);

                // 等一帧后再滚到底，避免内容高度未算完
                window.requestAnimationFrame(function() {
                    var el = document.getElementById('scan-log-modal');
                    if (el) el.scrollTop = el.scrollHeight;
                    window.setTimeout(function() {
                        var el2 = document.getElementById('scan-log-modal');
                        if (el2) el2.scrollTop = el2.scrollHeight;
                    }, 100);
                });
            }, 0);
        }).catch(function(e) {
            ui.addNotification(null,
                E('p', {}, _('获取日志失败：') + (e.message || e)), 'error');
        });
    },

    badgeStyle: function(running) {
        return (running ? 'background:#28a745;' : 'background:#6c757d;') +
            'color:#fff;padding:2px 8px;border-radius:3px;';
    },

    /* 轮询：只更新状态和按钮，绝不碰弹窗 */
    refreshStatus: function() {
        var self = this;
        return callGetStatus().then(function(res) {
            self.applyStatus(res || {});
        }).catch(function() {});
    }
});
