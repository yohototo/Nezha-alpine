#!/usr/bin/env bash

#========================================================
#   宿主机直接安装哪吒面板（不含Agent）脚本，适用开不了docker的小鸡
#   基于 https://github.com/naiba/nezha/blob/master/script/install.sh 修改
#   哪吒作者 Github: https://github.com/naiba/nezha
#========================================================

NZ_BASE_PATH="/opt/nezha"
NZ_DASHBOARD_PATH="${NZ_BASE_PATH}/dashboard"
NZ_DASHBOARD_SERVICE="/etc/systemd/system/nezha-dashboard.service"
NZ_DASHBOARD_SERVICERC="/etc/init.d/nezha-dashboard"
NZ_VERSION="v0.15.0"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH=$PATH:/usr/local/bin

os_arch=""
[ -e /etc/os-release ] && cat /etc/os-release | grep -i "PRETTY_NAME" | grep -qi "alpine" && os_alpine='1'

pre_check() {
    [ "$os_alpine" != 1 ] && ! command -v systemctl >/dev/null 2>&1 && echo "不支持此系统：未找到 systemctl 命令" && exit 1
    
    # check root
    [[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1
    
    ## os_arch
    if [[ $(uname -m | grep 'x86_64') != "" ]]; then
        os_arch="amd64"
        elif [[ $(uname -m | grep 'i386\|i686') != "" ]]; then
        os_arch="386"
        elif [[ $(uname -m | grep 'aarch64\|armv8b\|armv8l') != "" ]]; then
        os_arch="arm64"
        elif [[ $(uname -m | grep 'arm') != "" ]]; then
        os_arch="arm-7"
        elif [[ $(uname -m | grep 's390x') != "" ]]; then
        os_arch="s390x"
        elif [[ $(uname -m | grep 'riscv64') != "" ]]; then
        os_arch="riscv64"
    fi
    ## China_IP
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 10 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            echo "根据ipapi.co提供的信息，当前IP可能在中国"
            read -e -r -p "是否选用中国镜像完成安装? [Y/n] " input
            case $input in
                [yY][eE][sS] | [yY])
                    echo "使用中国镜像"
                    CN=true
                ;;
                
                [nN][oO] | [nN])
                    echo "不使用中国镜像"
                ;;
                *)
                    echo "使用中国镜像"
                    CN=true
                ;;
            esac
        fi
    fi
    
    ## China_IP
    if [[ -z "${CN}" ]]; then
        GITHUB_RAW_URL="raw.githubusercontent.com/applexad/nezhascript/main"
        GITHUB_URL="github.com"
        GITHUB_RELEASE_URL="github.com/applexad/nezha-binary-build/releases/latest/download"
    else
        GITHUB_RAW_URL="external.githubfast.com/https/raw.githubusercontent.com/applexad/nezhascript/main"
        GITHUB_URL="githubfast.com"
        GITHUB_RELEASE_URL="githubfast.com/applexad/nezha-binary-build/releases/latest/download"
    fi
}


confirm() {
    if [[ $# > 1 ]]; then
        echo && read -e -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -e -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

update_script() {
    echo -e "> 更新脚本"
    
    curl -sL https://${GITHUB_RAW_URL}/install.sh -o /tmp/nezha.sh
    new_version=$(cat /tmp/nezha.sh | grep "NZ_VERSION" | head -n 1 | awk -F "=" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$new_version" ]; then
        echo -e "脚本获取失败，请检查本机能否链接 https://${GITHUB_RAW_URL}/install.sh"
        return 1
    fi
    echo -e "当前最新版本为: ${new_version}"
    mv -f /tmp/nezha.sh ./nezha.sh && chmod a+x ./nezha.sh
    
    echo -e "3s后执行新脚本"
    sleep 3s
    clear
    exec ./nezha.sh
    exit 0
}

before_show_menu() {
    echo && echo -n -e "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    show_menu
}

install_base() {
    (command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 && command -v getenforce >/dev/null 2>&1) ||
    (install_soft curl wget unzip subversion)
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && yum makecache && yum install $* -y) ||
    (command -v apt >/dev/null 2>&1 && apt update && apt install $* -y) ||
    (command -v apt-get >/dev/null 2>&1 && apt-get update && apt-get install $* -y) ||
    (command -v apk >/dev/null 2>&1 && apk update && apk add $* -f)
}

install_dashboard() {
    install_base
    
    echo -e "> 安装面板"
    
    # 哪吒监控文件夹
    if [ ! -d "${NZ_DASHBOARD_PATH}" ]; then
        mkdir -p $NZ_DASHBOARD_PATH
    else
        echo "您可能已经安装过面板端，重复安装会覆盖数据，请注意备份。"
        read -e -r -p "是否退出安装? [Y/n] " input
        case $input in
            [yY][eE][sS] | [yY])
                echo "退出安装"
                exit 0
            ;;
            [nN][oO] | [nN])
                echo "继续安装"
            ;;
            *)
                echo "退出安装"
                exit 0
            ;;
        esac
    fi
    
    chmod 777 -R $NZ_DASHBOARD_PATH
    
    modify_dashboard_config 0
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

modify_dashboard_config() {
    echo -e "> 修改面板配置"
    
    echo -e "正在下载配置模板"
    
    wget -t 2 -T 10 -O /tmp/nezha-config.yaml https://${GITHUB_RAW_URL}/config.yaml >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}下载脚本失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
        return 0
    fi
    
    echo "关于 GitHub Oauth2 应用：在 https://github.com/settings/developers 创建，无需审核，Callback 填 http(s)://域名或IP/oauth2/callback" &&
    echo "关于 Gitee Oauth2 应用：在 https://gitee.com/oauth/applications 创建，无需审核，Callback 填 http(s)://域名或IP/oauth2/callback" &&
    read -ep "请输入 OAuth2 提供商(github/gitlab/jihulab/gitee，默认 github): " nz_oauth2_type &&
    read -ep "请输入 Oauth2 应用的 Client ID: " nz_github_oauth_client_id &&
    read -ep "请输入 Oauth2 应用的 Client Secret: " nz_github_oauth_client_secret &&
    read -ep "请输入 GitHub/Gitee 登录名作为管理员，多个以逗号隔开: " nz_admin_logins &&
    read -ep "请输入站点标题: " nz_site_title &&
    read -ep "请输入站点访问端口: (默认 8008)" nz_site_port &&
    read -ep "请输入用于 Agent 接入的 RPC 端口: (默认 5555)" nz_grpc_port
    
    if [[ -z "${nz_admin_logins}" || -z "${nz_github_oauth_client_id}" || -z "${nz_github_oauth_client_secret}" || -z "${nz_site_title}" ]]; then
        echo -e "${red}所有选项都不能为空${plain}"
        before_show_menu
        return 1
    fi
    
    if [[ -z "${nz_site_port}" ]]; then
        nz_site_port=8008
    fi
    if [[ -z "${nz_grpc_port}" ]]; then
        nz_grpc_port=5555
    fi
    if [[ -z "${nz_oauth2_type}" ]]; then
        nz_oauth2_type=github
    fi
    
    sed -i "s/nz_oauth2_type/${nz_oauth2_type}/" /tmp/nezha-config.yaml
    sed -i "s/nz_admin_logins/${nz_admin_logins}/" /tmp/nezha-config.yaml
    sed -i "s/nz_grpc_port/${nz_grpc_port}/" /tmp/nezha-config.yaml
    sed -i "s/nz_github_oauth_client_id/${nz_github_oauth_client_id}/" /tmp/nezha-config.yaml
    sed -i "s/nz_github_oauth_client_secret/${nz_github_oauth_client_secret}/" /tmp/nezha-config.yaml
    sed -i "s/nz_language/zh-CN/" /tmp/nezha-config.yaml
    sed -i "s/nz_site_title/${nz_site_title}/" /tmp/nezha-config.yaml
    sed -i "s/80/${nz_site_port}/" /tmp/nezha-config.yaml
    
    mkdir -p $NZ_DASHBOARD_PATH/data
    mv -f /tmp/nezha-config.yaml ${NZ_DASHBOARD_PATH}/data/config.yaml

    echo -e "正在下载服务文件"

    if [ "$os_alpine" != 1 ];then
        wget -t 2 -T 10 -O $NZ_DASHBOARD_SERVICE https://${GITHUB_RAW_URL}/nezha-dashboard.service >/dev/null 2>&1
        else
        wget -t 2 -T 10 -O $NZ_DASHBOARD_SERVICERC https://${GITHUB_RAW_URL}/nezha-dashboard >/dev/null 2>&1
        chmod +x $NZ_DASHBOARD_SERVICERC
        if [[ $? != 0 ]]; then
            echo -e "${red}文件下载失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
            return 0
        fi
    fi

    
    echo -e "面板配置 ${green}修改成功，请稍等重启生效${plain}"
    
    restart_and_update
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_and_update() {
    echo -e "> 重启并更新面板"
    
    cd $NZ_DASHBOARD_PATH

    if [ "$os_alpine" != 1 ];then
        wget -qO dashboard $GITHUB_RELEASE_URL/dashboard-linux-$os_arch >/dev/null 2>&1 && chmod +x dashboard >/dev/null 2>&1

    else
        wget -qO dashboard $GITHUB_RELEASE_URL/dashboard-musl-linux-$os_arch >/dev/null 2>&1 && chmod +x dashboard >/dev/null 2>&1

    fi

    if [ ! -d resource ];then
        svn checkout https://$GITHUB_URL/naiba/nezha/trunk/resource >/dev/null 2>&1
    else
        svn up resource >/dev/null 2>&1
    fi

    if [ "$os_alpine" != 1 ];then
        systemctl daemon-reload
        systemctl enable nezha-dashboard
        systemctl restart nezha-dashboard
    else
        rc-update add nezha-dashboard
        rc-service nezha-dashboard restart
    fi
    
    if [[ $? == 0 ]]; then
        echo -e "${green}哪吒监控 重启成功${plain}"
        echo -e "默认管理面板地址：${yellow}域名:站点访问端口${plain}"
    else
        echo -e "${red}重启失败，可能是因为启动时间超过了两秒，请稍后查看日志信息${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start_dashboard() {
    echo -e "> 启动面板"
    
    if [ "$os_alpine" != 1 ]; then
        systemctl start nezha-dashboard
    else
        rc-service nezha-dashboard start
    fi
    
    if [[ $? == 0 ]]; then
        echo -e "${green}哪吒监控 启动成功${plain}"
    else
        echo -e "${red}启动失败，请稍后查看日志信息${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}


stop_dashboard() {
    echo -e "> 停止面板"
    
    if [ "$os_alpine" != 1 ]; then
        systemctl stop nezha-dashboard
    else
        rc-service nezha-dashboard stop
    fi
    
    if [[ $? == 0 ]]; then
        echo -e "${green}哪吒监控 停止成功${plain}"
    else
        echo -e "${red}停止失败，请稍后查看日志信息${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_dashboard_log() {
    echo -e "> 获取面板日志"
    
    if [ "$os_alpine" != 1 ]; then
        journalctl -xf -u nezha-dashboard.service
    else
        echo "Alpine Linux 无此功能！"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall_dashboard() {
    echo -e "> 卸载管理面板"
    
    rm -rf $NZ_DASHBOARD_PATH

    if [ "$os_alpine" != 1 ]; then
        rm $NZ_DASHBOARD_SERVICE
    else
        rm $NZ_DASHBOARD_SERVICERC
    fi

    clean_all
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

clean_all() {
    if [ -z "$(ls -A ${NZ_BASE_PATH})" ]; then
        rm -rf ${NZ_BASE_PATH}
    fi
}

show_usage() {
    echo "哪吒监控 管理脚本使用方法: "
    echo "--------------------------------------------------------"
    echo "./nezha.sh                            - 显示管理菜单"
    echo "./nezha.sh install_dashboard          - 安装面板端"
    echo "./nezha.sh modify_dashboard_config    - 修改面板配置"
    echo "./nezha.sh start_dashboard            - 启动面板"
    echo "./nezha.sh stop_dashboard             - 停止面板"
    echo "./nezha.sh restart_and_update         - 重启并更新面板"
    echo "./nezha.sh show_dashboard_log         - 查看面板日志"
    echo "./nezha.sh uninstall_dashboard        - 卸载管理面板"
    echo "--------------------------------------------------------"
}

show_menu() {
    echo -e "
    ${green}哪吒监控管理脚本${plain} ${red}${NZ_VERSION}${plain}
    --- https://github.com/applexad/nezhascript ---
    ${green}1.${plain}  安装面板端
    ${green}2.${plain}  修改面板配置
    ${green}3.${plain}  启动面板
    ${green}4.${plain}  停止面板
    ${green}5.${plain}  重启并更新面板
    ${green}6.${plain}  查看面板日志
    ${green}7.${plain}  卸载管理面板
    ————————————————-
    ${green}8.${plain} 更新脚本
    ————————————————-
    ${green}0.${plain}  退出脚本
    "
    echo && read -ep "请输入选择 [0-8]: " num
    
    case "${num}" in
        0)
            exit 0
        ;;
        1)
            install_dashboard
        ;;
        2)
            modify_dashboard_config
        ;;
        3)
            start_dashboard
        ;;
        4)
            stop_dashboard
        ;;
        5)
            restart_and_update
        ;;
        6)
            show_dashboard_log
        ;;
        7)
            uninstall_dashboard
        ;;
        8)
            update_script
        ;;
        *)
            echo -e "${red}请输入正确的数字 [0-8]${plain}"
        ;;
    esac
}

pre_check

if [[ $# > 0 ]]; then
    case $1 in
        "install_dashboard")
            install_dashboard 0
        ;;
        "modify_dashboard_config")
            modify_dashboard_config 0
        ;;
        "start_dashboard")
            start_dashboard 0
        ;;
        "stop_dashboard")
            stop_dashboard 0
        ;;
        "restart_and_update")
            restart_and_update 0
        ;;
        "show_dashboard_log")
            show_dashboard_log 0
        ;;
        "uninstall_dashboard")
            uninstall_dashboard 0
        ;;
        "update_script")
            update_script 0
        ;;
        *) show_usage ;;
    esac
else
    show_menu
fi