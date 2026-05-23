#!/bin/bash
#
# Gentoo Linux 自动安装脚本
# 目标配置: x86_64 + KDE Plasma + UEFI/GPT
#

set -e

# ============ 配置区域 ============
# 请根据你的实际情况修改以下变量

# 时区
TIMEZONE="Asia/Shanghai"

# 主机名
HOSTNAME="gentoo-laptop"

# 域名
DOMAIN="local"

# root 密码（安装后请立即更改！）
ROOT_PASSWORD="gentoo"

# 用户名
USERNAME="user"

# 用户密码
USER_PASSWORD="user"

# 分区配置 (UEFI + GPT)
# 如果你的硬盘不是 /dev/sda，请修改此处
DISK="/dev/sda"

# EFI 分区大小 (MB)
EFI_SIZE=512

# SWAP 分区大小 (MB)，建议为内存大小的1-2倍
SWAP_SIZE=4096

# KDEPlasma USE flags
KDE_PLASMA_USE_FLAGS="kde plasma udev systemd X wayland ipv6"

# ============ 中国镜像源配置 ============
# 中科大镜像源 (USTC) - 主要源
MIRROR_USTC="https://mirrors.ustc.edu.cn/gentoo"
# 清华大学镜像源 (TUNA) - 备用源
MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn/gentoo"
# 腾讯云镜像源 - 备用源
MIRROR_TENCENT="https://mirrors.cloud.tencent.com/gentoo"
# 华为云镜像源 - 备用源
MIRROR_HUAWEI="https://mirrors.huaweicloud.com/gentoo"

# ============ 二进制包配置 ============
# 是否使用预编译二进制包 (yes/no)
# 使用 binary packages 可以大大加快安装速度
USE_BINARY_PACKAGES="yes"

# 二进制包源 (使用中科大镜像的预编译包)
BINHOST_USTC="https://mirrors.ustc.edu.cn/gentoo"
# 清华大学也提供部分 binhost
BINHOST_TUNA="https://mirrors.tuna.tsinghua.edu.cn/gentoo"

# ============ 脚本正文 ============

# 配置文件路径
CONFIG_FILE="/root/.gentoo-install.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_CONFIG="${SCRIPT_DIR}/.gentoo-install.conf"

# 显示帮助
show_help() {
    cat << EOF
Gentoo 自动安装脚本

用法: $0 [选项]

选项:
  -h, --help           显示帮助信息
  -c, --config FILE    指定配置文件路径 (默认: ~/.gentoo-install.conf)
  -s, --show           显示当前保存的配置
  -r, --reconfigure    重新进入交互配置模式
  -d, --dry-run        仅显示配置，不执行安装
  -i, --interactive    强制进入交互模式 (即使有保存的配置)

示例:
  $0                  # 使用保存的配置开始安装
  $0 -r               # 重新配置
  $0 -s               # 查看当前配置
  $0 -c /path/to/config  # 使用指定配置文件

配置文件格式:
  DISK=/dev/sda
  HOSTNAME=gentoo
  TIMEZONE=Asia/Shanghai
  ROOT_PASSWORD=xxx
  USERNAME=xxx
  USER_PASSWORD=xxx
  USE_BINARY_PACKAGES=yes
  EFI_SIZE=512
  SWAP_SIZE=4096
  ADD_SUDO=yes

EOF
}

# 保存配置到文件
save_config() {
    local config_file="$1"
    log_info "保存配置到: $config_file"

    cat > "$config_file" << EOF
# Gentoo 安装配置 - 由 gentoo-install.sh 自动生成
# 创建时间: $(date '+%Y-%m-%d %H:%M:%S')

# 磁盘配置
DISK="${DISK}"
EFI_SIZE=${EFI_SIZE}
SWAP_SIZE=${SWAP_SIZE}

# 系统配置
HOSTNAME="${HOSTNAME}"
TIMEZONE="${TIMEZONE}"
DOMAIN="${DOMAIN}"

# 用户配置
ROOT_PASSWORD="${ROOT_PASSWORD}"
USERNAME="${USERNAME}"
USER_PASSWORD="${USER_PASSWORD}"
ADD_SUDO="${add_sudo}"

# 安装选项
USE_BINARY_PACKAGES="${USE_BINARY_PACKAGES}"

# 镜像源配置 (仅供参考)
MIRROR_USTC="${MIRROR_USTC}"
EOF

    chmod 600 "$config_file"
    log_success "配置已保存"
}

# 加载配置
load_config() {
    local config_file="$1"

    if [[ -f "$config_file" ]]; then
        log_info "加载配置文件: $config_file"
        source "$config_file"
        log_success "配置已加载"
        return 0
    else
        log_warn "配置文件不存在: $config_file"
        return 1
    fi
}

# 显示当前配置
show_config() {
    echo ""
    echo "========================================"
    echo "       当前保存的配置"
    echo "========================================"
    echo ""

    if [[ -f "$CONFIG_FILE" ]]; then
        cat "$CONFIG_FILE"
        echo ""
        echo "配置文件: $CONFIG_FILE"
    elif [[ -f "$LOCAL_CONFIG" ]]; then
        cat "$LOCAL_CONFIG"
        echo ""
        echo "配置文件: $LOCAL_CONFIG"
    else
        echo "没有找到保存的配置文件"
        echo ""
        echo "当前脚本默认配置:"
        echo "  DISK=$DISK"
        echo "  HOSTNAME=$HOSTNAME"
        echo "  TIMEZONE=$TIMEZONE"
        echo "  EFI_SIZE=$EFI_SIZE"
        echo "  SWAP_SIZE=$SWAP_SIZE"
        echo "  USE_BINARY_PACKAGES=$USE_BINARY_PACKAGES"
    fi
    echo ""
}

# 解析命令行参数
parse_args() {
    # 默认值
    FORCE_INTERACTIVE=false
    DRY_RUN=false
    CONFIG_TO_LOAD=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--config)
                CONFIG_TO_LOAD="$2"
                shift 2
                ;;
            -s|--show)
                show_config
                exit 0
                ;;
            -r|--reconfigure)
                FORCE_INTERACTIVE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -i|--interactive)
                FORCE_INTERACTIVE=true
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 如果指定了配置文件
    if [[ -n "$CONFIG_TO_LOAD" ]]; then
        if load_config "$CONFIG_TO_LOAD"; then
            echo ""
            show_config
            if ! $DRY_RUN; then
                echo ""
                read -p "是否使用此配置开始安装? (y/n) [y]: " confirm
                [[ "$confirm" =~ ^[Nn]$ ]] && exit 0
            fi
        else
            log_error "无法加载配置文件"
            exit 1
        fi
    fi
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查是否以 root 身份运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请以 root 身份运行此脚本"
    fi
}

# 获取网络接口信息
detect_network() {
    log_info "检测网络接口..."
    ETHERNET=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | head -1)
    WIFI=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^wl|^wlan' | head -1)

    log_info "有线网卡: ${ETHERNET:-未检测到}"
    log_info "无线网卡: ${WIFI:-未检测到}"
}

# 交互式选择磁盘
select_disk() {
    echo ""
    echo "========================================"
    echo "        选择安装目标磁盘"
    echo "========================================"
    echo ""

    # 列出可用磁盘
    mapfile -t DISKS < <(lsblk -ndo NAME,SIZE,TYPE | grep -E 'disk$' | awk '{print "/dev/"$1, $2}')
    mapfile -t DISK_PATHS < <(lsblk -ndo NAME,SIZE,TYPE | grep -E 'disk$' | awk '{print "/dev/"$1}')

    if [[ ${#DISKS[@]} -eq 0 ]]; then
        log_error "未检测到可用磁盘"
    fi

    echo "可用磁盘:"
    echo ""
    for i in "${!DISKS[@]}"; do
        echo "  [$((i+1))] ${DISKS[$i]}"
    done
    echo "  [0] 其他（手动输入）"
    echo ""

    while true; do
        read -p "选择磁盘 [1]: " choice
        [[ -z "$choice" ]] && choice=1

        if [[ "$choice" == "0" ]]; then
            read -p "请输入磁盘设备路径: " DISK
            break
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#DISK_PATHS[@]} ]]; then
            DISK="${DISK_PATHS[$((choice-1))]}"
            break
        else
            log_warn "无效选择，请重试"
        fi
    done

    log_info "已选择磁盘: $DISK"

    # 显示磁盘当前分区情况
    echo ""
    echo "磁盘当前分区:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE $DISK 2>/dev/null || echo "  (无分区表或空磁盘)"
    echo ""
}

# 交互式配置用户
interactive_users() {
    echo ""
    echo "========================================"
    echo "          用户配置"
    echo "========================================"
    echo ""

    # 主机名
    read -p "主机名 [$HOSTNAME]: " input
    [[ -n "$input" ]] && HOSTNAME="$input"

    # 时区
    echo ""
    echo "常用时区:"
    echo "  [1] Asia/Shanghai (北京时间)"
    echo "  [2] Asia/Tokyo (东京时间)"
    echo "  [3] Asia/Hong_Kong (香港时间)"
    echo "  [4] 自定义"
    read -p "选择时区 [1]: " tz_choice
    [[ -z "$tz_choice" ]] && tz_choice=1

    case "$tz_choice" in
        1) TIMEZONE="Asia/Shanghai" ;;
        2) TIMEZONE="Asia/Tokyo" ;;
        3) TIMEZONE="Asia/Hong_Kong" ;;
        4) read -p "请输入时区: " TIMEZONE ;;
    esac

    # Root 密码
    echo ""
    while true; do
        read -sp "设置 Root 密码: " ROOT_PASSWORD
        echo ""
        [[ -n "$ROOT_PASSWORD" ]] && break
        log_warn "密码不能为空"
    done

    # 用户配置
    echo ""
    echo "是否创建普通用户? (y/n)"
    read -p "[y]: " create_user
    [[ -z "$create_user" ]] && create_user="y"

    if [[ "$create_user" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "用户名: " USERNAME
            [[ -n "$USERNAME" ]] && break
            log_warn "用户名不能为空"
        done

        while true; do
            read -sp "设置 $USERNAME 密码: " USER_PASSWORD
            echo ""
            [[ -n "$USER_PASSWORD" ]] && break
            log_warn "密码不能为空"
        done

        # 询问用户组
        echo ""
        echo "用户组 (默认: wheel,audio,video,usb,portage):"
        read -p "是否添加用户到 sudoers? (y/n) [y]: " add_sudo
        [[ -z "$add_sudo" ]] && add_sudo="y"
    else
        USERNAME=""
        USER_PASSWORD=""
    fi
}

# 交互式配置
interactive_config() {
    echo ""
    echo "========================================"
    echo "     Gentoo 自动安装配置"
    echo "========================================"
    echo ""

    select_disk
    interactive_users

    # 二进制包选项
    echo ""
    echo "========================================"
    echo "        安装选项"
    echo "========================================"
    echo ""
    echo "是否使用预编译二进制包?"
    echo "  [1] 是 (推荐，加快安装速度)"
    echo "  [2] 否 (纯源码编译)"
    read -p "选择 [1]: " bin_choice
    [[ -z "$bin_choice" ]] && bin_choice=1
    [[ "$bin_choice" == "2" ]] && USE_BINARY_PACKAGES="no"

    # 分区方案确认
    echo ""
    echo "========================================"
    echo "        分区方案"
    echo "========================================"
    echo ""
    echo "将使用以下分区方案:"
    echo "  EFI 分区:  ${EFI_SIZE}MB (/dev/sda1)"
    echo "  SWAP 分区: ${SWAP_SIZE}MB (/dev/sda2)"
    echo "  根分区:    剩余空间 (/dev/sda3)"
    echo ""
    read -p "是否继续? (y/n) [n]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0

    echo ""
    log_info "配置完成，开始安装..."
    sleep 3
}

# 分区和格式化
partition_disk() {
    log_info "开始分区 (UEFI + GPT)..."

    # 卸载已挂载的分区
    umount -R /mnt/gentoo 2>/dev/null || true
    swapoff -a 2>/dev/null || true

    # 清空分区表
    dd if=/dev/zero of=$DISK bs=512 count=1 2>/dev/null

    # 创建 GPT 分区表
    parted -s $DISK mklabel gpt

    # 创建 EFI 分区 (512MB)
    parted -s $DISK mkpart ESP fat32 1MiB ${EFI_SIZE}MiB
    parted -s $DISK set 1 esp on

    # 创建 SWAP 分区
    SWAP_START=$((EFI_SIZE + 1))
    SWAP_END=$((EFI_SIZE + SWAP_SIZE))
    parted -s $DISK mkpart primary linux-swap ${SWAP_START}MiB ${SWAP_END}MiB

    # 创建根分区 (剩余全部)
    ROOT_START=$((SWAP_END + 1))
    parted -s $DISK mkpart primary ext4 ${ROOT_START}MiB 100%

    # 格式化分区
    log_info "格式化分区..."

    mkfs.fat -F 32 ${DISK}1
    mkswap ${DISK}2
    mkfs.ext4 -F ${DISK}3

    # 挂载分区
    log_info "挂载分区..."
    mount ${DISK}3 /mnt/gentoo
    mkdir -p /mnt/gentoo/boot/efi
    mount ${DISK}1 /mnt/gentoo/boot/efi
    swapon ${DISK}2

    log_success "分区完成"
}

# 下载并安装 Stage3
install_stage3() {
    log_info "下载 Stage3 基础系统..."

    cd /mnt/gentoo

    # 使用中科大镜像源获取最新的 stage3
    STAGE3_LIST_URL="${MIRROR_USTC}/releases/amd64/autobuilds/latest-stage3-amd64-desktop-openrc.txt"

    log_info "从 USTC 镜像获取 Stage3 信息..."
    STAGE3_FILE=$(curl -s $STAGE3_LIST_URL | grep -v '^#' | awk '{print $1}')
    STAGE3_URL="${MIRROR_USTC}/releases/amd64/autobuilds/${STAGE3_FILE}"

    # 如果中科大源失败，尝试其他镜像
    if ! curl -sf --head "$STAGE3_URL" > /dev/null; then
        log_warn "USTC 镜像不可用，尝试 TUNA..."
        STAGE3_LIST_URL="${MIRROR_TUNA}/releases/amd64/autobuilds/latest-stage3-amd64-desktop-openrc.txt"
        STAGE3_FILE=$(curl -s $STAGE3_LIST_URL | grep -v '^#' | awk '{print $1}')
        STAGE3_URL="${MIRROR_TUNA}/releases/amd64/autobuilds/${STAGE3_FILE}"
    fi

    log_info "下载: $STAGE3_URL"
    wget -q --show-progress "$STAGE3_URL" -O stage3.tar.xz

    log_info "解压 Stage3..."
    tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner

    log_success "Stage3 安装完成"
}

# 配置 make.conf
configure_make_conf() {
    log_info "配置 make.conf..."

    # 根据是否使用二进制包设置配置
    if [[ "$USE_BINARY_PACKAGES" == "yes" ]]; then
        # 优先使用二进制包，本地编译作为备用
        cat > /mnt/gentoo/etc/portage/make.conf << EOF
# 编译配置
MAKEOPTS="-j$(nproc)"
EMERGE_DEFAULT_OPTS="--jobs=8 --load-average=8"

# 地区设置
L10N="en-US zh-CN"
LC_MESSAGES=C

# GCC 优化
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="\${CFLAGS}"

# USE flags
USE="${KDE_PLASMA_USE_FLAGS} -gnome -gtk -qt4"

# Portage 并行下载
PORTAGE_NICENESS=0
FETCHCOMMAND="wget -c \${URI} -P \${DISTDIR}"
RESUMECOMMAND="wget -c \${URI} -P \${DISTDIR}"

# 二进制包配置 - 优先使用预编译包
FEATURES="getbinpkg"
MAKEBINPKG_RDEPEND="yes"

# 中国镜像源 (优先使用)
GENTOO_MIRRORS="${MIRROR_USTC} ${MIRROR_TUNA} ${MIRROR_TENCENT}"

# 二进制包源
PORTAGE_BINHOST="${BINHOST_USTC}/binpkg"
EOF
        log_info "配置为优先使用二进制包模式"
    else
        # 纯源码编译模式
        cat > /mnt/gentoo/etc/portage/make.conf << EOF
# 编译配置
MAKEOPTS="-j$(nproc)"
EMERGE_DEFAULT_OPTS="--jobs=8 --load-average=8"

# 地区设置
L10N="en-US zh-CN"
LC_MESSAGES=C

# GCC 优化
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="\${CFLAGS}"

# USE flags
USE="${KDE_PLASMA_USE_FLAGS} -gnome -gtk -qt4"

# Portage 并行下载
PORTAGE_NICENESS=0
FETCHCOMMAND="wget -c \${URI} -P \${DISTDIR}"
RESUMECOMMAND="wget -c \${URI} -P \${DISTDIR}"

# 中国镜像源 (优先使用)
GENTOO_MIRRORS="${MIRROR_USTC} ${MIRROR_TUNA} ${MIRROR_TENCENT}"
EOF
    fi

    log_success "make.conf 配置完成"
}

# 配置 Portage
configure_portage() {
    log_info "配置 Portage..."

    # 创建 repos.conf，使用中科大镜像
    mkdir -p /mnt/gentoo/etc/portage/repos.conf
    cat > /mnt/gentoo/etc/portage/repos.conf/gentoo.conf << EOF
[DEFAULT]
main-repo = gentoo

[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.mirrors.ustc.edu.cn/gentoo-portage
auto-sync = yes
sync-rsync-verify-jobs = 1
sync-rsync-verify-metamanifest = yes
sync-rsync-verify-max-age = 3
sync-openpgp-key-path = /usr/share/openpgp-keys/gentoo-release.asc
sync-openpgp-keyserver = hkps://keys.gentoo.org
sync-openpgp-key-refresh-retry-count = 40
sync-openpgp-key-refresh-retry-overall-timeout = 1200
sync-openpgp-key-refresh-retry-delay-exp-base = 2
sync-openpgp-key-refresh-retry-delay-max = 60
sync-openpgp-key-refresh-retry-delay-mult = 4
sync-webrsync-verify-signature = yes
EOF

    # 复制DNS配置
    cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

    # 挂载必要文件系统
    log_info "挂载必要文件系统..."
    mount --types proc /proc /mnt/gentoo/proc
    mount --rbind /sys /mnt/gentoo/sys
    mount --make-rslave /mnt/gentoo/sys
    mount --rbind /dev /mnt/gentoo/dev
    mount --make-rslave /mnt/gentoo/dev
    mount --bind /run /mnt/gentoo/run
    mount --make-slave /mnt/gentoo/run

    log_success "Portage 配置完成"
}

# 配置时区和 locale
configure_locale() {
    log_info "配置时区和 locale..."

    # 时区
    ln -sf /usr/share/zoneinfo/$TIMEZONE /mnt/gentoo/etc/localtime

    # Locale
    cat > /mnt/gentoo/etc/locale.gen << 'EOF'
en_US.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
EOF

    log_info "生成 locale..."
    chroot /mnt/gentoo /bin/bash -c "locale-gen"

    # 设置默认 locale
    echo "LANG=en_US.UTF-8" > /mnt/gentoo/etc/env.d/02locale
    echo "LC_ALL=en_US.UTF-8" >> /mnt/gentoo/etc/env.d/02locale

    log_success "Locale 配置完成"
}

# 配置网络
configure_network() {
    log_info "配置网络..."

    ETHERNET=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | head -1)
    WIFI=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^wl|^wlan' | head -1)

    # hosts 文件
    cat > /mnt/gentoo/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.$DOMAIN $HOSTNAME
EOF

    # 配置有线网络 (DHCP)
    if [[ -n "$ETHERNET" ]]; then
        mkdir -p /mnt/gentoo/etc/init.d
        cat > /mnt/gentoo/etc/init.d/net.${ETHERNET} << 'EOF'
#!/sbin/openrc-run
name="net.$ iface"
description="Network interface $ iface"
kind="openrc"
EOF
        chmod +x /mnt/gentoo/etc/init.d/net.${ETHERNET}

        # 自动启动 DHCP
        ln -sf /etc/init.d/net.lo /mnt/gentoo/etc/init.d/net.${ETHERNET}
        chroot /mnt/gentoo /bin/bash -c "rc-update add net.${ETHERNET} default"
    fi

    # 安装 NetworkManager 用于 WiFi
    log_info "安装 NetworkManager..."

    # 配置文件系统表
    cat > /mnt/gentoo/etc/fstab << EOF
# /etc/fstab
# <设备>                                  <挂载点>  <类型>  <选项>                          <dump> <pass>
UUID=$(blkid -s UUID -o value ${DISK}1)  /boot/efi  vfat    defaults,noatime                0      2
UUID=$(blkid -s UUID -o value ${DISK}2)  none      swap    sw                              0      0
UUID=$(blkid -s UUID -o value ${DISK}3)  /         ext4    defaults,noatime                0      1

# tmpfs
tmpfs                                    /tmp      tmpfs   defaults,noatime,mode=1777      0      0
EOF

    log_success "网络配置完成"
}

# 安装固件
install_firmware() {
    log_info "安装固件..."

    # 创建 /lib/firmware 目录（如果 stage3 没有）
    mkdir -p /mnt/gentoo/lib/firmware

    # 链接 /lib 到 /usr/lib (现代 Gentoo 布局)
    if [[ ! -L /mnt/gentoo/lib ]]; then
        rm -rf /mnt/gentoo/lib
        ln -s usr/lib /mnt/gentoo/lib
    fi

    # 创建 firmware 目录软链接
    if [[ ! -L /mnt/gentoo/lib64 ]]; then
        ln -s usr/lib /mnt/gentoo/lib64
    fi

    log_success "固件目录配置完成"
}

# 编译安装内核
install_kernel() {
    log_info "安装 Linux 内核..."

    # 安装内核源码
    chroot /mnt/gentoo /bin/bash -c "emerge --quiet sys-kernel/gentoo-sources"

    # 安装固件
    chroot /mnt/gentoo /bin/bash -c "emerge --quiet sys-kernel/linux-firmware"

    # 安装 genkernel (自动编译内核工具)
    chroot /mnt/gentoo /bin/bash -c "emerge --quiet sys-kernel/genkernel"

    # 编译内核
    log_info "编译内核 (这可能需要一些时间)..."
    chroot /mnt/gentoo /bin/bash -c "genkernel --menuconfig all"

    log_success "内核编译完成"
}

# 配置引导程序
install_bootloader() {
    log_info "安装 GRUB 引导程序..."

    # 安装 GRUB for UEFI
    chroot /mnt/gentoo /bin/bash -c "emerge --quiet sys-boot/grub"

    # 安装到 EFI 分区
    log_info "配置 GRUB..."
    chroot /mnt/gentoo /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo"

    # 生成 GRUB 配置
    chroot /mnt/gentoo /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"

    log_success "引导程序安装完成"
}

# 创建用户
create_users() {
    log_info "创建用户账户..."

    # 设置 root 密码
    chroot /mnt/gentoo /bin/bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

    # 创建普通用户（如果设置了用户名）
    if [[ -n "$USERNAME" ]]; then
        log_info "创建用户: $USERNAME"
        chroot /mnt/gentoo /bin/bash -c "useradd -m -G wheel,audio,video,usb,input,portage -s /bin/bash ${USERNAME}"
        chroot /mnt/gentoo /bin/bash -c "echo '${USERNAME}:${USER_PASSWORD}' | chpasswd"

        # 配置 sudo
        if [[ "$add_sudo" =~ ^[Yy]$ ]]; then
            chroot /mnt/gentoo /bin/bash -c "echo '${USERNAME} ALL=(ALL) ALL' >> /etc/sudoers"
        fi
        log_success "用户 $USERNAME 创建完成"
    else
        log_info "跳过创建普通用户"
    fi

    log_success "用户账户配置完成"
}

# 安装 KDE Plasma 桌面环境
install_kde_plasma() {
    log_info "安装 KDE Plasma 桌面环境..."

    # 同步 portage
    chroot /mnt/gentoo /bin/bash -c "emerge --sync"

    # 设置 emerge 命令（根据是否使用二进制包）
    if [[ "$USE_BINARY_PACKAGES" == "yes" ]]; then
        EMERGE_CMD="emerge --getbinpkg --binpkg-respect-use=y"
        log_info "使用预编译二进制包模式 (加快安装速度)"
    else
        EMERGE_CMD="emerge"
        log_info "使用源码编译模式"
    fi

    # 更新 @world set
    log_info "更新系统..."
    chroot /mnt/gentoo /bin/bash -c "$EMERGE_CMD --quiet --update --deep --newuse @world"

    # 安装 X11
    log_info "安装 X11..."
    chroot /mnt/gentoo /bin/bash -c "$EMERGE_CMD --quiet x11-base/xorg-x11"

    # 安装 SDDM 登录管理器
    log_info "安装 SDDM..."
    chroot /mnt/gentoo /bin/bash -c "$EMERGE_CMD --quiet kde-plasma/sddm"

    # 安装 KDE Plasma
    if [[ "$USE_BINARY_PACKAGES" == "yes" ]]; then
        log_info "安装 KDE Plasma (使用预编译包，大幅加快速度)..."
        # 使用 -g 强制从 binhost 获取，没有则回退编译
        chroot /mnt/gentoo /bin/bash -c "emerge -g --getbinpkg --binpkg-respect-use=y kde-plasma/plasma-meta"
    else
        log_info "安装 KDE Plasma (源码编译，这可能需要很长时间)..."
        chroot /mnt/gentoo /bin/bash -c "emerge --quiet kde-plasma/plasma-meta"
    fi

    # 安装常用应用
    log_info "安装常用应用..."
    chroot /mnt/gentoo /bin/bash -c "$EMERGE_CMD --quiet kde-apps/konsole kde-apps/kate firefox-bin"

    # 配置 SDDM 自动启动
    chroot /mnt/gentoo /bin/bash -c "rc-update add xdm default"

    # 配置 SDDM
    cat > /mnt/gentoo/etc/conf.d/xdm << 'EOF'
DISPLAYMANAGER="sddm"
EOF

    log_success "KDE Plasma 安装完成"
}

# 安装 NetworkManager (WiFi 支持)
install_network_manager() {
    log_info "安装 NetworkManager..."

    chroot /mnt/gentoo /bin/bash -c "emerge --quiet net-misc/networkmanager"

    # 设置 NetworkManager 自动启动
    chroot /mnt/gentoo /bin/bash -c "rc-update add NetworkManager default"

    # 禁用默认的 OpenRC 网络服务（因为使用 NetworkManager）
    [[ -n "$ETHERNET" ]] && chroot /mnt/gentoo /bin/bash -c "rc-update del net.${ETHERNET} default" 2>/dev/null || true

    log_success "NetworkManager 安装完成"
}

# 清理安装
cleanup() {
    log_info "清理安装..."

    # 卸载文件系统
    umount -R /mnt/gentoo
    swapoff ${DISK}2

    log_success "清理完成"
}

# 显示完成信息
show_complete() {
    echo ""
    echo "========================================"
    echo -e "${GREEN}  Gentoo 安装完成！${NC}"
    echo "========================================"
    echo ""
    echo "重启前请确认:"
    echo "  1. 确保 EFI 分区正确挂载到 /boot/efi"
    echo "  2. 已正确设置启动顺序从 EFI 启动"
    echo ""
    echo "重启命令:"
    echo "  cd / ; umount -R /mnt/gentoo ; reboot"
    echo ""
    echo "首次登录后:"
    echo "  - 使用 KDE Plasma 桌面"
    echo "  - WiFi 配置: nmtui 或 Plasma 网络设置"
    echo "  - 记得更改 root 密码!"
    echo ""
}

# 主函数
main() {
    # 解析命令行参数
    parse_args "$@"

    check_root
    detect_network

    # 自动加载配置（如果没有强制交互模式）
    if ! $FORCE_INTERACTIVE; then
        # 优先使用用户指定的配置文件，其次检查 ~/.gentoo-install.conf
        if [[ -n "$CONFIG_TO_LOAD" ]]; then
            load_config "$CONFIG_TO_LOAD"
        elif [[ -f "$CONFIG_FILE" ]]; then
            load_config "$CONFIG_FILE"
        elif [[ -f "$LOCAL_CONFIG" ]]; then
            load_config "$LOCAL_CONFIG"
        fi
    fi

    # 如果没有加载到配置，或者强制交互模式，进入交互配置
    if $FORCE_INTERACTIVE || [[ -z "$HOSTNAME" ]] || [[ -z "$DISK" ]]; then
        interactive_config
        # 交互配置完成后自动保存
        save_config "$CONFIG_FILE"
    else
        # 显示即将使用的配置
        echo ""
        log_info "将使用保存的配置进行安装:"
        echo ""
        echo "  磁盘: $DISK"
        echo "  主机名: $HOSTNAME"
        echo "  时区: $TIMEZONE"
        echo "  二进制包: $USE_BINARY_PACKAGES"
        echo ""
        read -p "确认开始安装? (y/n) [y]: " confirm
        [[ "$confirm" =~ ^[Nn]$ ]] && exit 0
    fi

    log_info "开始 Gentoo 安装..."
    echo ""

    partition_disk
    install_stage3
    configure_make_conf
    configure_portage
    configure_locale
    configure_network
    install_firmware
    install_kernel
    install_bootloader
    create_users
    install_network_manager
    install_kde_plasma
    cleanup

    show_complete
}

# 运行
main "$@"
