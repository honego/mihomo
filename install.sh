#!/usr/bin/env bash

set -eE

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

die() {
    _err_msg "$(_red "$*")" >&2
    exit 1
}

curl() {
    local rc

    # 添加 -f --fail 不然 404 退出码也为 0
    # 32位 cygwin 已停止更新 证书可能有问题 添加 --insecure
    # centos7 curl 不支持 --retry-connrefused --retry-all-errors 因此手动 retry
    for ((i = 1; i <= 5; i++)); do
        if command curl --connect-timeout 10 --fail --insecure "$@"; then
            return
        else
            rc="$?"
            # 403 404 错误 或达到重试次数
            if [ "$rc" -eq 22 ] || [ "$i" -eq 5 ]; then
                return "$rc"
            fi
            sleep 1
        fi
    done
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

## mihomo 安装脚本入口

# 检查 root
if ((EUID != 0)); then
    die "请使用 root 用户运行此脚本."
fi
