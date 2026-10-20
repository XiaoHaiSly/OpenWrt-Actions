#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

FEEDS_PATH="./feeds"
PACKAGE_PATH="./package"

#修补命令统一入口：FIX <名称> <守卫目录> <命令...>
#守卫目录不存在时直接跳过，保证在 bash -e 下不中断
FIX() {
	local NAME=$1
	local GUARD=$2
	shift 2

	[ -d "$GUARD" ] || return 0

	echo " "
	if "$@"; then
		echo "$NAME has been fixed!"
	else
		echo "$NAME fix failed; continuing!"
	fi
}

#修改argon主题颜色
FIX "theme-argon" "$PACKAGE_PATH/luci-theme-argon" sed -i \
	"s/ primary '.*'/ primary '#5e72e4'/g; s/ blur '.*'/ blur '1'/g; s/ transparency '.*'/ transparency '0.3'/g; s/ online_wallpaper '.*'/ online_wallpaper 'none'/g" \
	"$PACKAGE_PATH/luci-theme-argon/root/etc/config/argon"

#修改aurora菜单式样
FIX "theme-aurora" "$PACKAGE_PATH/luci-app-aurora-config" find \
	"$PACKAGE_PATH/luci-app-aurora-config/root/usr/share/aurora/" -type f -name '*.template' -exec sed -i \
	"s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +

#修改mini-diskmanager菜单位置
FIX "mini-diskmanager" "$PACKAGE_PATH/luci-app-mini-diskmanager" sed -i "s/services/system/g" \
	"$PACKAGE_PATH/luci-app-mini-diskmanager/luci-app-mini-diskmanager/root/usr/share/luci/menu.d/luci-app-mini-diskmanager.json"

#修改openlist菜单位置
FIX "openlist" "$FEEDS_PATH/luci/applications/luci-app-openlist" sed -i "s/services/nas/g" \
	"$FEEDS_PATH/luci/applications/luci-app-openlist/root/usr/share/luci/menu.d/luci-app-openlist.json"

#修复Rust编译失败
FIX "rust" "$FEEDS_PATH/packages/lang/rust" sed -i 's/ci-llvm=true/ci-llvm=false/g' \
	"$FEEDS_PATH/packages/lang/rust/Makefile"

#替换docker相关包并检查一致性
for DOCKER_PKG in docker dockerd containerd runc docker-compose; do
	DOCKER_SRC="./package/luci-app-dockerman/$DOCKER_PKG"
	DOCKER_DST="./feeds/packages/utils/$DOCKER_PKG"

	if [ -d "$DOCKER_SRC" ] && [ -d "./feeds/packages/utils" ]; then
		rm -rf "$DOCKER_DST"
		mv -f "$DOCKER_SRC" "$DOCKER_DST"
		echo "Replace official $DOCKER_PKG with repo version: $DOCKER_DST"
	else
		echo "Not found $DOCKER_PKG in luci-app-dockerman repo, keep official version!"
	fi
done

[ -f "./feeds/packages/utils/dockerd/git-short-commit.sh" ] && chmod +x "./feeds/packages/utils/dockerd/git-short-commit.sh"

DOCKER_CLI_VER=$(grep -Po "^PKG_VERSION:=\K.*" ./feeds/packages/utils/docker/Makefile 2>/dev/null)
DOCKERD_VER=$(grep -Po "^PKG_VERSION:=\K.*" ./feeds/packages/utils/dockerd/Makefile 2>/dev/null)
if [ -n "$DOCKER_CLI_VER" ] && [ "$DOCKER_CLI_VER" != "$DOCKERD_VER" ]; then
	echo "WARNING: docker ($DOCKER_CLI_VER) and dockerd ($DOCKERD_VER) versions differ, dockerd build will fail!"
fi
