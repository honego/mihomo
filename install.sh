#!/usr/bin/env bash

set -eE

## 颜色函数
_red() {
    printf "\033[31m%b\033[0m\n" "$*"
}

_green() {
    printf "\033[32m%b\033[0m\n" "$*"
}

_yellow() {
    printf "\033[33m%b\033[0m\n" "$*"
}

_blue() {
    printf "\033[34m%b\033[0m\n" "$*"
}

# 红底白字
_red_bg() {
    printf "\033[41;37m%b\033[0m\n" "$*"
}

# 蓝底白字
_blue_bg() {
    printf "\033[44;37m%b\033[0m\n" "$*"
}

# 通用错误提示, 既包含错误也包含警告
_alert_msg() {
    printf "\033[41m\033[1m%b\033[0m %b\n" "$1" "$2"
}

_err_msg() {
    _alert_msg "错误" "$*"
}

_warn_msg() {
    _alert_msg "警告" "$*"
}

## 全局参数
GITHUB_REPO="MetaCubeX/mihomo"
# shellcheck disable=SC2034
GITHUB_REPO_URL="https://github.com/$GITHUB_REPO"
PROJECT="${GITHUB_REPO##*/}"
PROJECT_DIR="/etc/$PROJECT"
# shellcheck disable=SC2034
PROJECT_BIN="$PROJECT_DIR/bin"
# shellcheck disable=SC2034
SCRIPT_DIR="$PROJECT_DIR/sh"
# shellcheck disable=SC2034

# 缓存已识别的包管理器
PKG_MGR=""

# 避免重复更新软件包索引
APT_UPDATED=""

die() {
    _err_msg "$(_red "$*")" >&2
    exit 1
}

get_cmd_path() {
    # arch 云镜像不带 which
    # command -v 包括脚本里面的方法
    # ash 无效
    type -f -p "$1"
}

is_have_cmd() {
    get_cmd_path "$1" > /dev/null 2>&1
}

install_pkg() {
    local cmd

    find_pkg_mgr() {
        local id mgr

        [ -n "$PKG_MGR" ] && return

        # 查找方法 1: 通过 ID / ID_LIKE
        # 因为可能装了多种包管理器
        if [ -f /etc/os-release ]; then
            # https://github.com/chef/os_release
            for id in $(
                # shellcheck disable=SC1091
                . /etc/os-release
                echo "$ID $ID_LIKE"
            ); do
                case "$id" in
                alpine) PKG_MGR=apk ;;
                centos | fedora | rhel) is_have_cmd dnf && PKG_MGR=dnf || PKG_MGR=yum ;;
                debian | ubuntu) PKG_MGR=apt-get ;;
                esac
                [ -n "$PKG_MGR" ] && return
            done
        fi

        # 查找方法 2
        for mgr in apk apt-get dnf yum; do
            is_have_cmd "$mgr" && PKG_MGR="$mgr" && return
        done

        return 1
    }

    add_pkg() {
        local pkg

        pkg="$1"

        case "$PKG_MGR" in
        apk)
            apk add --no-cache "$pkg"
            ;;
        apt-get)
            [ -z "$APT_UPDATED" ] && apt-get update && APT_UPDATED="1"
            DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$pkg"
            ;;
        dnf | yum)
            "$PKG_MGR" install -y "$pkg"
            ;;
        esac
    }

    for cmd in "$@"; do
        if ! is_have_cmd "$cmd"; then
            if ! find_pkg_mgr; then
                die "找不到兼容的包管理器 请手动安装 $cmd."
            fi
            add_pkg "$cmd"
        fi
    done >&2
}

curl() {
    local rc

    is_have_cmd curl || install_pkg curl

    # 添加 -f --fail 不然 404 退出码也为0
    # 32位 cygwin 已停止更新, 证书可能有问题先添加 --insecure
    # centos 7 curl 不支持 --retry-connrefused --retry-all-errors 因此手动 retry
    for i in $(seq 5); do
        if command curl --insecure --connect-timeout 10 -f "$@"; then
            return
        else
            rc="$?"
            # 403 404 错误, 或者达到重试次数
            if [ "$rc" -eq 22 ] || [ "$i" -eq 5 ]; then
                return "$rc"
            fi
            sleep 1
        fi
    done
}

check_service_mgr() {
    local svc_mgr

    for svc_mgr in "rc-service" "systemctl"; do
        is_have_cmd "$svc_mgr" && return
    done

    return 1
}

## 脚本入口

# 检查 root
if [ "$EUID" -ne 0 ]; then
    die "请使用 root 用户运行此脚本."
fi

if ! check_service_mgr; then
    die "此系统缺少 rc-service 或 systemctl"
fi
