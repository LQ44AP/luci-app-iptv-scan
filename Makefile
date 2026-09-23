include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-iptv-scan
PKG_VERSION:=1.0.3
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0
PKG_MAINTAINER:=Your Name <you@example.com>

LUCI_TITLE:=LuCI app for IPTV multicast scanner
LUCI_DEPENDS:=+luasocket +libuci-lua
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

define Build/Compile
endef

# ============ conffiles：升级时保留用户修改 ============
define Package/luci-app-iptv-scan/conffiles
/etc/config/iptv_scan
/root/city_list.txt
/root/iptv_dict.txt
endef

# ============ 安装规则：显式声明每个文件的落点 ============
define Package/luci-app-iptv-scan/install
	# ---------- LuCI 菜单 ----------
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-iptv-scan.json \
		$(1)/usr/share/luci/menu.d/luci-app-iptv-scan.json

	# ---------- rpcd ACL ----------
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-iptv-scan.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-iptv-scan.json

	# ---------- rpcd ucode 后端 ----------
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_BIN) ./root/usr/share/rpcd/ucode/luci.iptvscan \
		$(1)/usr/share/rpcd/ucode/luci.iptvscan

	# ---------- UCI 配置文件 ----------
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/iptv_scan \
		$(1)/etc/config/iptv_scan

	# ---------- UCI 默认值 ----------
	# $(INSTALL_DIR) $(1)/etc/uci-defaults
	# $(INSTALL_BIN) ./root/etc/uci-defaults/85_iptv_scan \
	# 	$(1)/etc/uci-defaults/85_iptv_scan

	# ---------- 扫描主程序 ----------
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/iptv_scan.lua \
		$(1)/usr/bin/iptv_scan.lua

	# ---------- 数据文件：city_list.txt / iptv_dict.txt ----------
	$(INSTALL_DIR) $(1)/root
	$(INSTALL_CONF) ./root/root/city_list.txt \
		$(1)/root/city_list.txt
	# $(INSTALL_CONF) ./root/root/iptv_dict.txt \
	# 	$(1)/root/iptv_dict.txt

	# ---------- LuCI 前端视图 ----------
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/iptv-scan
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/iptv-scan/settings.js \
		$(1)/www/luci-static/resources/view/iptv-scan/settings.js
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/iptv-scan/status.js \
		$(1)/www/luci-static/resources/view/iptv-scan/status.js
endef

# ============ 安装后置脚本：确保 rpcd 重载 ============
define Package/luci-app-iptv-scan/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/rpcd reload >/dev/null 2>&1
	rm -f /tmp/luci-indexcache*
	rm -rf /tmp/luci-modulecache*
	exit 0
}
endef

$(eval $(call BuildPackage,luci-app-iptv-scan))





