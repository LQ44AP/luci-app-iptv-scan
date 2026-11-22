include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-iptv-scan
PKG_VERSION:=1.0.4
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0
PKG_MAINTAINER:=Your Name <you@example.com>

LUCI_TITLE:=LuCI app for IPTV multicast scan
LUCI_DEPENDS:=+luasocket +libuci-lua
LUCI_PKGARCH:=all

define Package/luci-app-auto-subnet/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
    chmod 0755 /usr/share/rpcd/ucode/luci.iptvscan
    chmod 0755 /usr/bin/iptv_scan.lua
fi
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature







