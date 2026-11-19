#!/usr/bin/env bash
# 出安卓包（默认 release，arm64-v8a）。
#
# 工具链全在 .workbuddy/toolchain/，不碰系统环境：
#   jdk17/                 Gradle 7.4.2 只认 JDK 17，系统那个 26 用不了
#   android-sdk/           platform-tools + platforms;android-33 + build-tools;33.0.2
#   android-sdk/ndk/25.2.9519653
#
# ANDROID_SETUP 是 lime 的全局配置项（~/.lime/config.xml），不设的话
# AndroidPlatform 在构造阶段就报 "run lime setup android"。
# ANDROID_HOST 必须手传：hxcpp 4.3.2 按老 NDK 布局（toolchains/<arch>-<ver>/prebuilt）
# 探测 host 目录，NDK 25 只有 llvm/prebuilt/windows-x86_64，探测失败会退回 "windows"。

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TC="$ROOT/.workbuddy/toolchain"

export JAVA_HOME="$TC/jdk17"
export ANDROID_SDK="$TC/android-sdk"
export ANDROID_NDK_ROOT="$ANDROID_SDK/ndk/25.2.9519653"
export ANDROID_SETUP=true
export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/windows-x86_64/bin:$JAVA_HOME/bin:$ANDROID_SDK/platform-tools:$PATH"

# gradle 下载依赖要走本机代理。JDK 自带的 cacerts 不认代理的证书链（PKIX path
# building failed），WINDOWS-ROOT 让它直接读 Windows 证书库。
if [ -n "${HTTPS_PROXY:-}" ]; then
	proxy_host="$(printf '%s' "$HTTPS_PROXY" | sed -E 's#^[a-z]+://([^:/]+).*#\1#')"
	proxy_port="$(printf '%s' "$HTTPS_PROXY" | sed -E 's#.*:([0-9]+)/?$#\1#')"
	export GRADLE_OPTS="${GRADLE_OPTS:-} -Dhttps.proxyHost=$proxy_host -Dhttps.proxyPort=$proxy_port -Dhttp.proxyHost=$proxy_host -Dhttp.proxyPort=$proxy_port"
fi
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djavax.net.ssl.trustStoreType=WINDOWS-ROOT"

[ -d "$JAVA_HOME" ] || { echo "缺 JDK 17: $JAVA_HOME" >&2; exit 1; }
[ -d "$ANDROID_NDK_ROOT" ] || { echo "缺 NDK: $ANDROID_NDK_ROOT" >&2; exit 1; }

QJS_LIB="$ROOT/third_party/quickjs-ng/build/android-arm64/libquickjs-ng.a"
if [ ! -f "$QJS_LIB" ]; then
	echo "QuickJS arm64 静态库不存在，先编它"
	bash "$ROOT/.workbuddy/build_qjs_android.sh"
fi

cd "$ROOT"
echo "构建 android（arm64-v8a）…"
# -Dnostrip：NDK 25 的 bin 里只有 llvm-strip.exe，hxcpp 却按 ${TOOLCHAIN_PREFIX}strip
# 去找 aarch64-linux-android-strip，链接最后一步会报"不是内部或外部命令"。
# 先不 strip，包大一点；要 strip 就在 NDK bin 里复制一份 llvm-strip.exe 改名。
haxelib run lime build android -DANDROID_HOST=windows-x86_64 -Dnostrip "$@"
