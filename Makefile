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



