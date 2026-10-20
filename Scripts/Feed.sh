#!/bin/bash
set -eo pipefail

#修改软件源域名
FEED_HOST="${WRT_FEED_HOST:-}"

CONF_DIR="$GITHUB_WORKSPACE/Config"
TOP="$PWD"
APK="$TOP/staging_dir/host/bin/apk"

feed_ready() {
	[ -n "$FEED_HOST" ]
}

feed_host() {
	local H=${FEED_HOST#http://}; H=${H#https://}; echo "${H%%/*}"
}

feed_tag() {
	echo "${WRT_HASH:0:7}"
}

normalize_packages() {
	[ -f "$CONF_DIR/PACKAGES.txt" ] || return 0
	tr -d '\r' < "$CONF_DIR/PACKAGES.txt" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk '
		/^$/ || /^#/ { next }
		/^CONFIG_PACKAGE_.*=y$/ { sub(/=y$/, "=m"); print; next }
		/^CONFIG_/ { print; next }
		{ print "CONFIG_PACKAGE_" $0 "=m" }'
}

make_index() {
	find "$1" -maxdepth 1 -name '*.apk' -size +25M -print -delete | sed 's/^/too large, skipped on Pages: /'
	( cd "$1" && "$APK" mkndx --root "$TOP" --keys-dir "$TOP" --allow-untrusted --output packages.adb ./*.apk )
}

case "$1" in
config)
	echo "CONFIG_ALL_KMODS=y" >> .config
	#调整排除的内核模块
	for K in $(echo "$WRT_KMOD_EXCLUDE" | tr ',\r\n' '   '); do
		echo "# CONFIG_PACKAGE_$K is not set" >> .config
	done
	if [ "$WRT_FEED_USER" = "true" ]; then
		FWY=$(mktemp)
		{ grep -hoP '^CONFIG_PACKAGE_\K[^=]+(?==y$)' "$CONF_DIR/$WRT_CONFIG.txt" "$CONF_DIR/GENERAL.txt" || true; } | sort -u > "$FWY"
		normalize_packages | awk '
			FILENAME == ARGV[1] { y[$0]; next }
			{ n = $0; sub(/^CONFIG_PACKAGE_/, "", n); sub(/=.*/, "", n); if (!(n in y)) print }
		' "$FWY" - >> .config
		rm -f "$FWY"
	fi
	;;

collect)
	OUT="$GITHUB_WORKSPACE/feed-out"
	rm -rf "$OUT" && mkdir -p "$OUT"

	KDIR="$OUT/kmods/$WRT_SUBTARGET"
	mkdir -p "$KDIR"
	cp -f bin/targets/*/*/packages/*.apk "$KDIR"/
	VM=$(find build_dir -maxdepth 4 -name .vermagic -path '*linux-*' | head -n 1)
	[ -n "$VM" ] || { echo "ERROR: .vermagic not found"; exit 1; }
	cat "$VM" > "$KDIR/vermagic"
	make_index "$KDIR"
	echo "kmods: $(ls "$KDIR"/*.apk | wc -l) packages, vermagic $(cat "$KDIR/vermagic")"

	if [ "$WRT_FEED_USER" = "true" ]; then
		ARCH=$(grep -oP '^CONFIG_TARGET_ARCH_PACKAGES="\K[^"]+' .config)
		UDIR="$OUT/packages/$ARCH"
		mkdir -p "$UDIR" ./tmp
		{
			grep -oP '^CONFIG_PACKAGE_\K[^=]+(?==m$)' .config || true
			normalize_packages | grep -oP '^CONFIG_PACKAGE_\K[^=]+(?==m$)' || true
		} | sort -u > ./tmp/feed-m.txt
		python3 - ./tmp/feed-m.txt "$APK" "$UDIR" bin/packages/"$ARCH"/*/ <<'PY'
import json, os, shutil, subprocess, sys
mfile, apk, dst = sys.argv[1:4]
want = set(open(mfile).read().split())
n = 0
for src in sys.argv[4:]:
    adb = os.path.join(src, "packages.adb")
    if not os.path.exists(adb):
        continue
    data = json.loads(subprocess.check_output([apk, "adbdump", "--format", "json", adb]))
    pkgs = data["packages"] if isinstance(data, dict) else data
    for p in pkgs:
        name = p["name"]
        base = name
        for t in p.get("tags", []):
            if t.startswith("openwrt:abiversion="):
                abi = t.split("=")[-1]
                if base.endswith(abi):
                    base = base[: -len(abi)]
        if base in want or name in want:
            f = os.path.join(src, "%s-%s.apk" % (name, p["version"]))
            if os.path.exists(f):
                shutil.copy2(f, dst)
                n += 1
print("userspace: %d packages" % n)
PY
		if ls "$UDIR"/*.apk >/dev/null 2>&1; then
			make_index "$UDIR"
		else
			echo "WARNING: no userspace package collected, check Config/PACKAGES.txt"
			rmdir "$UDIR" || true
		fi
	fi
	;;

firmware)
	feed_ready || { echo "FEED_HOST not set, skip writing feed into firmware"; exit 0; }
	[ -n "$(feed_tag)" ] || { echo "ERROR: WRT_HASH not set"; exit 1; }
	ARCH=$(grep -oP '^CONFIG_TARGET_ARCH_PACKAGES="\K[^"]+' .config)
	URL="https://$(feed_tag).$(feed_host)"
	mkdir -p files/etc/apk/repositories.d
	cat > files/etc/apk/repositories.d/extra-feeds.list <<LIST
$URL/packages/$ARCH/packages.adb
$URL/kmods/$WRT_SUBTARGET/packages.adb
LIST
	cat files/etc/apk/repositories.d/extra-feeds.list
	;;

project)
	if feed_ready; then H=$(feed_host); echo "${H%%.*}"; fi
	;;

tag)
	feed_tag
	;;

*)
	echo "usage: Feed.sh config|collect|firmware|project|tag"; exit 1
	;;
esac

