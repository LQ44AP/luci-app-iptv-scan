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

# ============ conffiles：升级时保留用户修改 ============
define Package/luci-app-iptv-scan/conffiles
/etc/config/iptv_scan
/root/city_list.txt
/root/iptv_dict.txt
endef





