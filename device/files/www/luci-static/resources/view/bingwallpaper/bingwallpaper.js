"use strict";
"require view";
"require uci";
"require fs";
"require ui";
"require rpc";

var callGetUrl = rpc.declare({ object: 'luci.argon_wallpaper', method: 'get_url' });

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('argon'),
			callGetUrl().catch(function(){ return { url: '' }; })
		]);
	},

	render: function(data) {
		var self = this;
		var cur = uci.get('argon', '@global[0]', 'online_wallpaper') || 'none';
		var url = (data[1] && data[1].url) || '';

		return E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('必应每日壁纸')),
			E('div', { class: 'cbi-map-descr' }, [
				_('启用后，Argon 主题的登录页（未登录时的背景）会显示必应每日壁纸，每天自动更换。'),
				E('br'),
				_('说明：该选项作用于登录页；管理员界面背景不受影响。')
			]),
			E('div', { class: 'cbi-section' }, [
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, _('启用必应每日壁纸')),
					E('div', { class: 'cbi-value-field' }, [
						E('input', {
							type: 'checkbox',
							id: 'bing_enabled',
							checked: (cur === 'bing') ? '' : undefined,
							change: ui.createHandlerFn(self, function(ev) {
								var on = ev.target.checked;
								return fs.exec('/usr/bin/bing-wallpaper', [ on ? 'enable' : 'disable' ])
									.then(function() { return uci.load('argon'); })
									.then(function() { ui.addNotification(null, E('p', {}, _('已保存')), 'info'); });
							})
						}),
						E('span', {}, ' ' + _('当前状态：') + (cur === 'bing' ? _('已启用') : _('未启用')))
					])
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, _('今日壁纸')),
					E('div', { class: 'cbi-value-field' }, [
						url ? E('a', { href: 'https:' + url, target: '_blank' }, url.split('?')[0].replace('//www.bing.com/th?id=OHR.', '')) : E('em', {}, _('（暂无缓存，点击下方刷新）')),
						E('br'),
						url ? E('img', { src: 'https:' + url, style: 'max-width:100%;max-height:220px;margin-top:8px;border-radius:6px' }) : ''
					])
				]),
				E('button', {
					class: 'btn cbi-button cbi-button-apply',
					click: ui.createHandlerFn(self, function() {
						ui.showModal(_('刷新'), [E('p', { class: 'spinning' }, _('正在获取…'))]);
						return fs.exec('/usr/bin/bing-wallpaper', [ 'refresh' ]).then(function() {
							ui.hideModal();
							window.location.reload();
						});
					})
				}, _('立即刷新'))
			])
		]);
	}
});
