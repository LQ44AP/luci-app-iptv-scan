include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-iptv-scan
PKG_VERSION:=1.0.3
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Your Name <you@example.com>

LUCI_TITLE:=LuCI app for IPTV multicast scanner
LUCI_DEPENDS:=+luasocket +libuci-lua
LUCI_PKGARCH:=all

# ============ conffiles：升级时保留用户修改 ============
# 注意：必须在 include luci.mk 之前定义，否则 BuildPackage 不会注册它
define Package/$(PKG_NAME)/conffiles
/etc/config/iptv_scan
/etc/iptv_scan/city_list.txt
/etc/iptv_scan/iptv_dict.txt
endef

include $(TOPDIR)/feeds/luci/luci.mk





