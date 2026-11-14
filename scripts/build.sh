#!/usr/bin/env bash
#
# RTLPlayground 固件编译脚本（GitHub Actions / 本地 Docker 通用）
#
# 用法：
#   MACHINES="KEEPLINK_KP_9000_6XHML_X2_2M_PCB43_V1_1" bash scripts/build.sh
#   MACHINES="A B" CONFIG_FILE=configs/my.txt bash scripts/build.sh
#
# 环境变量：
#   MACHINES       必填，机型名（machine/<MACHINE>.h 的文件名），空格或逗号分隔
#   SRC_DIR        固件源码目录，默认 src
#   DIST_DIR       产物目录，默认 dist
#   CONFIG_DIR     按机型自动匹配配置的目录，默认 configs
#   CONFIG_FILE    显式指定配置文件（优先级最高），默认空
#   OEM            1=构建 OEM 网页升级包，0=不构建，auto=仅单机型时构建（默认）
#   CI             1=make CI=1（把警告当错误），默认 1
#   FAIL_FAST      1=某个机型失败就停止，0=继续编译其余机型（默认 1）
#   EXPECTED_SIZE  期望镜像大小（字节），0=不检查，默认 524288
#   SOURCE_REPO    仅用于 build-info.txt
#   SOURCE_REF     仅用于 build-info.txt
#
set -euo pipefail

SRC_DIR="${SRC_DIR:-src}"
DIST_DIR="${DIST_DIR:-dist}"
CONFIG_DIR="${CONFIG_DIR:-configs}"
CONFIG_FILE="${CONFIG_FILE:-}"
OEM="${OEM:-auto}"
CI="${CI:-1}"
FAIL_FAST="${FAIL_FAST:-1}"
EXPECTED_SIZE="${EXPECTED_SIZE:-524288}"
MACHINES="${MACHINES:-}"
SOURCE_REPO="${SOURCE_REPO:-unknown}"
SOURCE_REF="${SOURCE_REF:-unknown}"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "${MACHINES// /}" ] || die "请设置 MACHINES，例如 MACHINES='KEEPLINK_KP_9000_6XHML_X2_2M_PCB43_V1_1'"
[ -d "$SRC_DIR/machine" ] || die "找不到固件源码目录 '$SRC_DIR'（其中应包含 machine/）"
command -v make >/dev/null 2>&1 || die "缺少 make"
command -v gcc  >/dev/null 2>&1 || die "缺少 gcc"

MACHINES="${MACHINES//,/ }"
TS_CONFIG="$SRC_DIR/.rtlplayground-build-config.txt"
cleanup() { rm -f "$TS_CONFIG"; }
trap cleanup EXIT

mkdir -p "$DIST_DIR"
find "$DIST_DIR" -maxdepth 1 -type f \
  \( -name '*.bin' -o -name '*.map' -o -name '*.mem' \
     -o -name 'SHA256SUMS' -o -name 'build-info.txt' \) -delete

machines=()
# shellcheck disable=SC2086
for m in $MACHINES; do
  [[ "$m" =~ ^[A-Za-z0-9_]+$ ]] || die "非法机型名：'$m'（只允许字母、数字、下划线）"
  [ -f "$SRC_DIR/machine/$m.c" ] || die "源码中没有 machine/$m.c（机型名区分大小写）"
  [ -f "$SRC_DIR/machine/$m.h" ] || die "源码中没有 machine/$m.h"
  machines+=("$m")
done
[ "${#machines[@]}" -gt 0 ] || die "机型列表为空"

printf '待编译机型（%d）：%s\n' "${#machines[@]}" "${machines[*]}"

failed=()
built=()

for m in "${machines[@]}"; do
  cfg=""
  if [ -n "$CONFIG_FILE" ]; then
    [ -f "$CONFIG_FILE" ] || die "配置文件不存在：$CONFIG_FILE"
    cfg="$CONFIG_FILE"
  elif [ -f "$CONFIG_DIR/$m.txt" ]; then
    cfg="$CONFIG_DIR/$m.txt"
  fi

  log "编译 $m"
  if [ -n "$cfg" ]; then
    printf '    启动配置：%s\n' "$cfg"
    cp -f "$cfg" "$TS_CONFIG"
    make_args=(CI="$CI" MACHINE="$m" CONFIG=".rtlplayground-build-config.txt")
  else
    printf '    启动配置：源码自带 config.txt\n'
    make_args=(CI="$CI" MACHINE="$m")
  fi

  if ! make -C "$SRC_DIR" "${make_args[@]}"; then
    if [ "$FAIL_FAST" = "1" ]; then
      die "$m 编译失败"
    fi
    warn "$m 编译失败，继续编译其余机型"
    failed+=("$m")
    continue
  fi

  bin=""
  for candidate in "$SRC_DIR/output/$m"/rtlplayground-*.bin; do
    [ -f "$candidate" ] || continue
    if [ -z "$bin" ] || [ "$candidate" -nt "$bin" ]; then
      bin="$candidate"
    fi
  done
  [ -n "$bin" ] || die "编译结束但找不到产物：$SRC_DIR/output/$m/rtlplayground-*.bin"

  size="$(stat -c %s "$bin")"
  if [ "$EXPECTED_SIZE" -gt 0 ] && [ "$size" -ne "$EXPECTED_SIZE" ]; then
    die "$m 的镜像大小是 $size 字节，预期 $EXPECTED_SIZE 字节；如果项目修改了 IMAGESIZE，请调整 EXPECTED_SIZE（0 表示不检查）"
  fi

  cp -f "$bin" "$DIST_DIR/rtlplayground-$m.bin"
  for ext in map mem; do
    if [ -f "$SRC_DIR/output/$m/rtlplayground.$ext" ]; then
      cp -f "$SRC_DIR/output/$m/rtlplayground.$ext" "$DIST_DIR/rtlplayground-$m.$ext"
    fi
  done
  built+=("$m")
  printf '    产物：%s（%s 字节）\n' "$(basename "$bin")" "$size"
done

# ---------------------------------------------------------------- OEM 升级包
build_oem=0
case "$OEM" in
  1|true|yes|on)  build_oem=1 ;;
  0|false|no|off) build_oem=0 ;;
  auto)
    if [ "${#machines[@]}" -eq 1 ]; then build_oem=1; else build_oem=0; fi
    ;;
  *) die "OEM 只能是 1、0 或 auto" ;;
esac

if [ "$build_oem" -eq 1 ]; then
  if [ "${#machines[@]}" -ne 1 ]; then
    warn "OEM 网页升级包只对单机型有意义，多机型构建已跳过"
  elif [ "${#failed[@]}" -gt 0 ]; then
    warn "固件编译失败，跳过 OEM 升级包"
  else
    log "编译 OEM 网页升级包"
    if ! make -C "$SRC_DIR/installer"; then
      if [ "$FAIL_FAST" = "1" ]; then
        die "OEM 升级包编译失败"
      fi
      warn "OEM 升级包编译失败"
      failed+=("OEM")
    else
      oem_bin="$SRC_DIR/installer/output/rtlplayground_oem_upgrade.bin"
      [ -f "$oem_bin" ] || die "找不到 OEM 升级包：$oem_bin"
      cp -f "$oem_bin" "$DIST_DIR/rtlplayground_oem_upgrade-${machines[0]}.bin"
      printf '    产物：%s\n' "$(basename "$oem_bin")"
    fi
  fi
fi

# ---------------------------------------------------------------- 构建信息
commit="$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || true)"
commit_date="$(git -C "$SRC_DIR" show -s --format=%cI HEAD 2>/dev/null || true)"
{
  printf 'RTLPlayground cloud build\n'
  printf 'source repo : %s\n' "$SOURCE_REPO"
  printf 'source ref  : %s\n' "$SOURCE_REF"
  printf 'commit      : %s\n' "${commit:-unknown}"
  printf 'commit date : %s\n' "${commit_date:-unknown}"
  printf 'built at    : %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'builder     : %s\n' "${RUNNER_OS:-$(uname -s)}"
  printf 'CI flags    : CI=%s\n' "$CI"
  printf 'machines    : %s\n' "${built[*]:-（无）}"
  printf '\nfiles:\n'
} > "$DIST_DIR/build-info.txt"

for f in "$DIST_DIR"/*.bin; do
  [ -f "$f" ] || continue
  printf '  %-70s %10s bytes\n' "$(basename "$f")" "$(stat -c %s "$f")" >> "$DIST_DIR/build-info.txt"
done

sums=()
for f in "$DIST_DIR"/*.bin "$DIST_DIR"/*.map "$DIST_DIR"/*.mem; do
  [ -f "$f" ] && sums+=("$(basename "$f")")
done
sums+=("build-info.txt")
( cd "$DIST_DIR" && sha256sum "${sums[@]}" > SHA256SUMS )

log "构建完成"
for f in "$DIST_DIR"/*.bin; do
  [ -f "$f" ] || continue
  printf '  %-70s %10s bytes\n' "$(basename "$f")" "$(stat -c %s "$f")"
done

if [ "${#failed[@]}" -gt 0 ]; then
  warn "以下机型/步骤失败：${failed[*]}"
  exit 1
fi
