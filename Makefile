include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-iptv-scan
PKG_VERSION:=1.0.1
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for IPTV Multicast Scan
  DEPENDS:=+luasocket +luci-base +luci-compat +libuci-lua
  PKGARCH:=all
endef

# 下面三个定义留空即可
define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	# 1. 安装控制器 (Controller)
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/

	# 2. 安装 CBI 模型 (Model)
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./luasrc/model/cbi/*.lua $(1)/usr/lib/lua/luci/model/cbi/

	# 3. 安装 视图模板 (View)
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/cbi
	$(INSTALL_DATA) ./luasrc/view/cbi/*.htm $(1)/usr/lib/lua/luci/view/cbi/

	# 4. 安装 配置文件
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/iptv_scan $(1)/etc/config/

	# 5. 安装 扫描引擎脚本
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/iptv_scan.lua $(1)/usr/bin/

	# 6. 安装 ACL 权限控制
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/*.json $(1)/usr/share/rpcd/acl.d/

	# 7. 安装 城市名列表
	$(INSTALL_DIR) $(1)/root
	$(INSTALL_DATA) ./root/*.txt $(1)/root
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	rm -rf /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	killall -HUP rpcd 2>/dev/null
fi
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
