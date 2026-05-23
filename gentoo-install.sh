#!/bin/bash
#
# Gentoo Linux 自动安装脚本
# 目标配置: x86_64 + KDE Plasma + UEFI/GPT
#

set -e

# ============ 配置区域 ============
# 请根据你的实际情况修改以下变量

# 初始化系统 (systemd / openrc)
# 注意: 必须与 Stage3 下载和 USE flags 保持一致
INIT_SYSTEM="systemd"

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

# 是否将用户添加到 sudoers (yes/no)
ADD_SUDO="yes"

# 分区配置 (UEFI + GPT)
# 如果你的硬盘不是 /dev/sda，请修改此处
DISK="/dev/sda"

# EFI 分区大小 (MB)
EFI_SIZE=512

# SWAP 分区大小 (MB)，建议为内存大小的1-2倍
SWAP_SIZE=4096

# 根分区文件系统 (ext4/btrfs/xfs)
ROOT_FS="ext4"

# KDE Plasma USE flags（根据初始化系统自动选择，一般无需修改）
KDE_USE_FLAGS_SYSTEMD="kde plasma udev systemd X wayland ipv6"
KDE_USE_FLAGS_OPENRC="kde plasma udev elogind X wayland ipv6"

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
BINHOST_TUNA="https://mirrors.tuna.tsinghua.edu.cn/gentoo"

# ============ 内部状态 ============
CHROOT_READY=false
MOUNTED=false

# ============ 脚本正文 ============

# 配置文件路径
CONFIG_FILE="/root/.gentoo-install.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_CONFIG="${SCRIPT_DIR}/.gentoo-install.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
die()         { log_error "$1"; exit 1; }

# ============ 工具函数 ============

# 获取分区设备路径（兼容 NVMe/mmcblk 设备）
# NVMe: /dev/nvme0n1 → /dev/nvme0n1p1
# SATA: /dev/sda     → /dev/sda1
get_part_dev() {
    local disk="$1" num="$2"
    if [[ $disk =~ nvme[0-9]+n[0-9]+$ || $disk =~ mmcblk[0-9]+$ ]]; then
        echo "${disk}p${num}"
    else
        echo "${disk}${num}"
    fi
}

# 根据初始化系统获取 USE flags
get_use_flags() {
    case "$INIT_SYSTEM" in
        systemd) echo "$KDE_USE_FLAGS_SYSTEMD" ;;
        openrc)  echo "$KDE_USE_FLAGS_OPENRC" ;;
        *)       die "未知的初始化系统: $INIT_SYSTEM (支持: systemd / openrc)" ;;
    esac
}

# 清理安装环境
cleanup() {
    if $MOUNTED; then
        log_info "清理安装环境..."
        umount -R /mnt/gentoo 2>/dev/null || true
        swapoff -a 2>/dev/null || true
        log_info "清理完成"
    fi
}
trap cleanup EXIT

# 检查是否以 root 身份运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "请以 root 身份运行此脚本"
    fi
}

# 获取网络接口信息
detect_network() {
    log_info "检测网络接口..."
    ETHERNET=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | head -1 || true)
    WIFI=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^wl|^wlan' | head -1 || true)

    log_info "有线网卡: ${ETHERNET:-未检测到}"
    log_info "无线网卡: ${WIFI:-未检测到}"
}

# 检查网络连通性
check_network() {
    log_info "检查网络连接..."
    if ! ping -c 1 -W 5 gentoo.org > /dev/null 2>&1; then
        die "网络不可用，请先配置网络连接"
    fi
    log_success "网络连接正常"
}

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
  INIT_SYSTEM=systemd
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

# 初始化系统
INIT_SYSTEM="${INIT_SYSTEM}"

# 磁盘配置
DISK="${DISK}"
EFI_SIZE=${EFI_SIZE}
SWAP_SIZE=${SWAP_SIZE}
ROOT_FS="${ROOT_FS}"

# 系统配置
HOSTNAME="${HOSTNAME}"
TIMEZONE="${TIMEZONE}"
DOMAIN="${DOMAIN}"

# 用户配置
ROOT_PASSWORD="${ROOT_PASSWORD}"
USERNAME="${USERNAME}"
USER_PASSWORD="${USER_PASSWORD}"
ADD_SUDO="${ADD_SUDO}"

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
        echo "  INIT_SYSTEM=$INIT_SYSTEM"
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
                [[ -z "${2:-}" ]] && die "-c 选项需要一个参数"
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
            die "无法加载配置文件: $CONFIG_TO_LOAD"
        fi
    fi
}

# ============ 交互式配置 ============

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
        die "未检测到可用磁盘"
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
    lsblk -o NAME,SIZE,TYPE,FSTYPE "$DISK" 2>/dev/null || echo "  (无分区表或空磁盘)"
    echo ""
}

# 交互式选择初始化系统
select_init_system() {
    echo ""
    echo "========================================"
    echo "        选择初始化系统"
    echo "========================================"
    echo ""
    echo "  [1] systemd  - 现代化，KDE Plasma 推荐使用"
    echo "  [2] OpenRC   - 轻量级，Gentoo 传统默认"
    echo ""

    while true; do
        read -p "选择初始化系统 [1]: " init_choice
        [[ -z "$init_choice" ]] && init_choice=1

        case "$init_choice" in
            1) INIT_SYSTEM="systemd"; break ;;
            2) INIT_SYSTEM="openrc"; break ;;
            *) log_warn "无效选择，请重试" ;;
        esac
    done

    log_info "已选择初始化系统: $INIT_SYSTEM"
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
            read -p "用户名 [$USERNAME]: " input
            if [[ -n "$input" ]]; then
                USERNAME="$input"
                break
            fi
            # 如果为空则使用默认值
            break
        done

        while true; do
            read -sp "设置 $USERNAME 密码: " USER_PASSWORD
            echo ""
            [[ -n "$USER_PASSWORD" ]] && break
            log_warn "密码不能为空"
        done

        # 询问 sudo
        echo ""
        read -p "是否添加用户到 sudoers? (y/n) [y]: " ADD_SUDO
        [[ -z "$ADD_SUDO" ]] && ADD_SUDO="y"
    else
        USERNAME=""
        USER_PASSWORD=""
        ADD_SUDO="no"
    fi
}

# 交互式选择文件系统
select_filesystem() {
    echo ""
    echo "========================================"
    echo "        选择根分区文件系统"
    echo "========================================"
    echo ""
    echo "请选择根分区使用的文件系统:"
    echo ""
    echo "  [1] ext4    - 稳定可靠，通用性强 (推荐新手)"
    echo "  [2] btrfs   - 支持快照、压缩，适合桌面用户"
    echo "  [3] xfs     - 高性能，适合大文件服务器"
    echo ""
    echo "注意: EFI 分区固定使用 FAT32，SWAP 分区使用 swap"
    echo ""

    while true; do
        read -p "选择文件系统 [1]: " fs_choice
        [[ -z "$fs_choice" ]] && fs_choice=1

        case "$fs_choice" in
            1) ROOT_FS="ext4"; break ;;
            2) ROOT_FS="btrfs"; break ;;
            3) ROOT_FS="xfs"; break ;;
            *) log_warn "无效选择，请重试" ;;
        esac
    done

    log_info "已选择文件系统: $ROOT_FS"

    # 显示文件系统说明
    case "$ROOT_FS" in
        ext4)
            echo "  - 经典稳定，广泛使用"
            echo "  - 最大支持 16TB 单文件"
            ;;
        btrfs)
            echo "  - 支持 COW、快照、压缩"
            echo "  - 需要更多内存 (建议 >= 4GB)"
            ;;
        xfs)
            echo "  - 高性能，大文件支持好"
            echo "  - 不支持缩小分区"
            ;;
    esac
    echo ""
}

# 交互式配置
interactive_config() {
    echo ""
    echo "========================================"
    echo "     Gentoo 自动安装配置"
    echo "========================================"
    echo ""

    select_disk
    select_init_system
    interactive_users
    select_filesystem

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
    echo "  EFI 分区:  ${EFI_SIZE}MB ($(get_part_dev "$DISK" 1)) - FAT32"
    echo "  SWAP 分区: ${SWAP_SIZE}MB ($(get_part_dev "$DISK" 2)) - swap"
    echo "  根分区:    剩余空间 ($(get_part_dev "$DISK" 3)) - $ROOT_FS"
    echo ""
    read -p "是否继续? (y/n) [n]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0

    echo ""
    log_info "配置完成，开始安装..."
    sleep 3
}

# ============ 安装步骤 ============

# 分区和格式化
partition_disk() {
    log_info "开始分区 (UEFI + GPT)..."

    # 分区设备路径（兼容 NVMe）
    local efi_part sw_part root_part
    efi_part=$(get_part_dev "$DISK" 1)
    sw_part=$(get_part_dev "$DISK" 2)
    root_part=$(get_part_dev "$DISK" 3)

    # 最终数据警告
    echo ""
    echo -e "${RED}⚠ 警告: 即将清除 ${DISK} 上的所有数据！${NC}"
    echo -e "${RED}  此操作不可逆！请确认你已备份重要数据。${NC}"
    echo ""
    read -p "确认清除磁盘 ${DISK} 上的所有数据? 输入 YES 确认: " confirm
    [[ "$confirm" != "YES" ]] && die "用户取消操作"

    # 卸载已挂载的分区
    umount -R /mnt/gentoo 2>/dev/null || true
    swapoff -a 2>/dev/null || true

    # 清除文件系统签名（比 dd 更安全、更彻底）
    wipefs -a "$DISK" 2>/dev/null || dd if=/dev/zero of="$DISK" bs=512 count=1 2>/dev/null

    # 创建 GPT 分区表
    parted -s "$DISK" mklabel gpt

    # 创建 EFI 分区
    parted -s "$DISK" mkpart ESP fat32 1MiB ${EFI_SIZE}MiB
    parted -s "$DISK" set 1 esp on

    # 创建 SWAP 分区
    local swap_start=$((EFI_SIZE + 1))
    local swap_end=$((EFI_SIZE + SWAP_SIZE))
    parted -s "$DISK" mkpart primary linux-swap ${swap_start}MiB ${swap_end}MiB

    # 创建根分区（使用用户选择的文件系统类型）
    local root_start=$((swap_end + 1))
    parted -s "$DISK" mkpart primary "$ROOT_FS" ${root_start}MiB 100%

    # 刷新分区表，等待 udev 识别
    partprobe "$DISK" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 1

    # 格式化分区
    log_info "格式化分区..."
    log_info "EFI: FAT32 | SWAP: swap | 根: $ROOT_FS"

    mkfs.fat -F 32 "$efi_part"
    mkswap "$sw_part"

    case "$ROOT_FS" in
        ext4)
            mkfs.ext4 -F "$root_part"
            ;;
        btrfs)
            mkfs.btrfs -f "$root_part"
            ;;
        xfs)
            mkfs.xfs -f "$root_part"
            ;;
        *)
            die "未知文件系统: $ROOT_FS"
            ;;
    esac

    # 挂载分区
    log_info "挂载分区..."
    mkdir -p /mnt/gentoo
    mount "$root_part" /mnt/gentoo
    mkdir -p /mnt/gentoo/boot/efi
    mount "$efi_part" /mnt/gentoo/boot/efi
    swapon "$sw_part"

    MOUNTED=true
    log_success "分区完成"
}

# 下载并安装 Stage3
install_stage3() {
    log_info "下载 Stage3 基础系统..."

    cd /mnt/gentoo

    # 根据 INIT_SYSTEM 选择 stage3 变体
    local stage3_variant
    case "$INIT_SYSTEM" in
        systemd) stage3_variant="desktop-systemd" ;;
        openrc)  stage3_variant="desktop-openrc" ;;
    esac

    # 依次尝试多个镜像源
    local mirrors=("$MIRROR_USTC" "$MIRROR_TUNA" "$MIRROR_TENCENT" "$MIRROR_HUAWEI")
    local stage3_file="" stage3_url=""

    for mirror in "${mirrors[@]}"; do
        local list_url="${mirror}/releases/amd64/autobuilds/latest-stage3-amd64-${stage3_variant}.txt"
        log_info "尝试镜像: ${mirror}..."

        stage3_file=$(curl -sf "$list_url" 2>/dev/null | grep -v '^#' | awk '{print $1}' | head -1) || continue

        if [[ -n "$stage3_file" ]]; then
            stage3_url="${mirror}/releases/amd64/autobuilds/${stage3_file}"
            if curl -sf --head "$stage3_url" > /dev/null 2>&1; then
                log_info "找到 Stage3: ${stage3_url}"
                break
            fi
        fi
        stage3_file=""
    done

    if [[ -z "$stage3_file" ]]; then
        # 尝试降级到非 desktop 变体
        log_warn "未找到 desktop-${stage3_variant} 变体，尝试标准 ${stage3_variant} 变体..."
        local fallback_variant
        case "$INIT_SYSTEM" in
            systemd) fallback_variant="systemd" ;;
            openrc)  fallback_variant="openrc" ;;
        esac

        for mirror in "${mirrors[@]}"; do
            local list_url="${mirror}/releases/amd64/autobuilds/latest-stage3-amd64-${fallback_variant}.txt"
            stage3_file=$(curl -sf "$list_url" 2>/dev/null | grep -v '^#' | awk '{print $1}' | head -1) || continue

            if [[ -n "$stage3_file" ]]; then
                stage3_url="${mirror}/releases/amd64/autobuilds/${stage3_file}"
                if curl -sf --head "$stage3_url" > /dev/null 2>&1; then
                    log_info "找到 Stage3: ${stage3_url}"
                    break
                fi
            fi
            stage3_file=""
        done
    fi

    [[ -z "$stage3_file" ]] && die "所有镜像源均无法获取 Stage3，请检查网络连接"

    # 下载 Stage3
    log_info "下载: $stage3_url"
    wget -q --show-progress "$stage3_url" -O stage3.tar.xz

    # 下载并验证校验和
    log_info "验证 Stage3 完整性..."
    if wget -q "${stage3_url}.DIGESTS" -O stage3.DIGESTS 2>/dev/null; then
        local tarball_name
        tarball_name=$(basename "$stage3_url")
        local expected_hash actual_hash
        expected_hash=$(awk "/SHA512.*${tarball_name}/ && !/CONTENTS/ {print \$NF}" stage3.DIGESTS | head -1)
        if [[ -n "$expected_hash" ]]; then
            actual_hash=$(sha512sum stage3.tar.xz | awk '{print $1}')
            if [[ "$expected_hash" == "$actual_hash" ]]; then
                log_success "Stage3 完整性验证通过 (SHA512)"
            else
                log_warn "Stage3 SHA512 校验不匹配！"
                read -p "文件可能已损坏，是否继续? (y/n) [n]: " cont
                [[ "$cont" != "y" && "$cont" != "Y" ]] && die "用户取消"
            fi
        else
            log_warn "无法解析校验文件，跳过完整性验证"
        fi
    else
        log_warn "无法下载校验文件，跳过完整性验证"
    fi

    # 解压
    log_info "解压 Stage3..."
    tar xpvf stage3.tar.xz --xattrs-include='*.*' --numeric-owner

    # 清理下载文件
    rm -f stage3.tar.xz stage3.DIGESTS

    log_success "Stage3 安装完成"
}

# 配置 make.conf
configure_make_conf() {
    log_info "配置 make.conf..."

    local use_flags
    use_flags=$(get_use_flags)

    # 构建 binpkg 配置（仅在启用时添加）
    local binpkg_config=""
    if [[ "$USE_BINARY_PACKAGES" == "yes" ]]; then
        binpkg_config="
# 二进制包配置 - 优先使用预编译包
FEATURES=\"getbinpkg\"
MAKEBINPKG_RDEPEND=\"yes\"
PORTAGE_BINHOST=\"${BINHOST_USTC}/binpkg\"
"
    fi

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
USE="${use_flags} -gnome -gtk -qt4"

# GRUB UEFI 支持
GRUB_PLATFORMS="efi-64"

# Portage 下载配置
PORTAGE_NICENESS=0
FETCHCOMMAND="wget -c \${URI} -P \${DISTDIR}"
RESUMECOMMAND="wget -c \${URI} -P \${DISTDIR}"

# 中国镜像源 (优先使用)
GENTOO_MIRRORS="${MIRROR_USTC} ${MIRROR_TUNA} ${MIRROR_TENCENT}"
${binpkg_config}
EOF

    if [[ "$USE_BINARY_PACKAGES" == "yes" ]]; then
        log_info "已启用二进制包模式 (FEATURES=getbinpkg)"
    else
        log_info "已启用纯源码编译模式"
    fi

    log_success "make.conf 配置完成"
}

# 配置 Portage 和 chroot 环境
configure_portage() {
    log_info "配置 Portage 和 chroot 环境..."

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
sync-rsync-extra-opts = --info=progress2
EOF

    # 复制 DNS 配置
    cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

    # 挂载必要文件系统
    log_info "挂载 chroot 文件系统..."
    mount --types proc /proc /mnt/gentoo/proc
    mount --rbind /sys /mnt/gentoo/sys
    mount --make-rslave /mnt/gentoo/sys
    mount --rbind /dev /mnt/gentoo/dev
    mount --make-rslave /mnt/gentoo/dev
    mount --bind /run /mnt/gentoo/run
    mount --make-slave /mnt/gentoo/run

    CHROOT_READY=true
    log_success "Portage 和 chroot 环境配置完成"
}

# 同步 Portage 树
sync_portage() {
    log_info "同步 Portage 树 (emerge --sync)..."
    chroot /mnt/gentoo emerge --sync || {
        log_warn "rsync 同步失败，尝试 webrsync..."
        chroot /mnt/gentoo emerge-webrsync || die "Portage 同步失败，请检查网络"
    }
    log_success "Portage 树同步完成"
}

# 配置时区和 locale
configure_locale() {
    log_info "配置时区和 locale..."

    # 时区（在 chroot 中操作，确保 zoneinfo 文件可用）
    chroot /mnt/gentoo /bin/bash -c "ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime"
    echo "${TIMEZONE}" > /mnt/gentoo/etc/timezone

    # Locale
    cat > /mnt/gentoo/etc/locale.gen << 'EOF'
en_US.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
EOF

    log_info "生成 locale..."
    chroot /mnt/gentoo /bin/bash -c "locale-gen"

    # 设置默认 locale（根据初始化系统使用不同配置方式）
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        echo "LANG=en_US.UTF-8" > /mnt/gentoo/etc/locale.conf
    else
        cat > /mnt/gentoo/etc/env.d/02locale << 'EOF'
LANG="en_US.UTF-8"
LC_ALL="en_US.UTF-8"
EOF
    fi

    # 设置系统 locale（使用 eselect）
    chroot /mnt/gentoo /bin/bash -c "eselect locale set en_US.utf8" 2>/dev/null || true

    log_success "Locale 配置完成"
}

# 配置主机名和 fstab
configure_network() {
    log_info "配置主机名和 fstab..."

    # 主机名
    echo "${HOSTNAME}" > /mnt/gentoo/etc/hostname

    # hosts 文件
    cat > /mnt/gentoo/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.${DOMAIN} ${HOSTNAME}
EOF

    # 分区设备路径
    local efi_part sw_part root_part
    efi_part=$(get_part_dev "$DISK" 1)
    sw_part=$(get_part_dev "$DISK" 2)
    root_part=$(get_part_dev "$DISK" 3)

    # 确保 udev 已识别分区
    udevadm settle 2>/dev/null || true

    # 获取 UUID
    local efi_uuid swap_uuid root_uuid
    efi_uuid=$(blkid -s UUID -o value "$efi_part") || die "无法获取 EFI 分区 UUID (${efi_part})"
    swap_uuid=$(blkid -s UUID -o value "$sw_part") || die "无法获取 SWAP 分区 UUID (${sw_part})"
    root_uuid=$(blkid -s UUID -o value "$root_part") || die "无法获取根分区 UUID (${root_part})"

    # 根据文件系统设置挂载选项
    local root_mounts="defaults,noatime"
    if [[ "$ROOT_FS" == "btrfs" ]]; then
        root_mounts="defaults,noatime,compress=zstd:3"
    fi

    # 写入 fstab
    cat > /mnt/gentoo/etc/fstab << EOF
# /etc/fstab
# <设备>                                  <挂载点>    <类型>     <选项>                      <dump> <pass>
UUID=${efi_uuid}   /boot/efi  vfat       defaults,noatime             0      2
UUID=${swap_uuid}  none       swap       sw                           0      0
UUID=${root_uuid}  /          ${ROOT_FS}  ${root_mounts}              0      1

# tmpfs
tmpfs              /tmp       tmpfs      defaults,noatime,mode=1777   0      0
EOF

    log_info "EFI UUID:  $efi_uuid"
    log_info "SWAP UUID: $swap_uuid"
    log_info "ROOT UUID: $root_uuid ($ROOT_FS)"

    log_success "主机名和 fstab 配置完成"
}

# 准备固件目录
install_firmware() {
    log_info "准备固件目录..."

    # 确保固件目录存在
    mkdir -p /mnt/gentoo/lib/firmware

    # 现代 stage3 的 /lib 和 /lib64 应该已经是符号链接
    # 仅在不存在时创建，绝不删除已有目录
    if [[ ! -e /mnt/gentoo/lib ]]; then
        ln -s usr/lib /mnt/gentoo/lib
    fi
    if [[ ! -e /mnt/gentoo/lib64 ]]; then
        ln -s usr/lib /mnt/gentoo/lib64
    fi

    log_success "固件目录准备完成"
}

# 编译安装内核
install_kernel() {
    log_info "安装 Linux 内核..."

    # 安装内核源码
    chroot /mnt/gentoo emerge sys-kernel/gentoo-sources

    # 安装固件
    chroot /mnt/gentoo emerge sys-kernel/linux-firmware

    # 安装 genkernel (自动编译内核工具)
    chroot /mnt/gentoo emerge sys-kernel/genkernel

    # 编译内核（不使用 --menuconfig 以支持非交互环境）
    log_info "编译内核 (这可能需要较长时间，请耐心等待)..."
    chroot /mnt/gentoo genkernel all

    log_success "内核编译完成"
}

# 配置引导程序
install_bootloader() {
    log_info "安装 GRUB 引导程序..."

    # 安装 GRUB for UEFI
    chroot /mnt/gentoo emerge sys-boot/grub

    # 安装到 EFI 分区
    log_info "配置 GRUB..."
    chroot /mnt/gentoo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo

    # 生成 GRUB 配置
    chroot /mnt/gentoo grub-mkconfig -o /boot/grub/grub.cfg

    log_success "引导程序安装完成"
}

# 创建用户
create_users() {
    log_info "创建用户账户..."

    # 设置 root 密码
    echo "root:${ROOT_PASSWORD}" | chroot /mnt/gentoo chpasswd

    # 创建普通用户（如果设置了用户名）
    if [[ -n "${USERNAME:-}" ]]; then
        log_info "创建用户: $USERNAME"
        chroot /mnt/gentoo useradd -m -G wheel,audio,video,usb,input,portage -s /bin/bash "$USERNAME"
        echo "${USERNAME}:${USER_PASSWORD}" | chroot /mnt/gentoo chpasswd

        # 配置 sudo
        if [[ "${ADD_SUDO}" =~ ^[Yy] ]]; then
            # 确保 sudo 已安装
            chroot /mnt/gentoo emerge app-admin/sudo
            echo "${USERNAME} ALL=(ALL) ALL" >> /mnt/gentoo/etc/sudoers
        fi
        log_success "用户 $USERNAME 创建完成"
    else
        log_info "跳过创建普通用户"
    fi

    log_success "用户账户配置完成"
}

# 安装 NetworkManager
install_network_manager() {
    log_info "安装 NetworkManager..."

    chroot /mnt/gentoo emerge net-misc/networkmanager

    # 启用 NetworkManager
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        chroot /mnt/gentoo systemctl enable NetworkManager
    else
        chroot /mnt/gentoo rc-update add NetworkManager default
        # 禁用默认的 OpenRC 网络脚本（由 NetworkManager 接管）
        local ethernet
        ethernet=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | head -1 || true)
        if [[ -n "$ethernet" ]]; then
            chroot /mnt/gentoo rc-update del "net.${ethernet}" default 2>/dev/null || true
        fi
    fi

    log_success "NetworkManager 安装完成"
}

# 安装 KDE Plasma 桌面环境
install_kde_plasma() {
    log_info "安装 KDE Plasma 桌面环境 (这可能需要很长时间)..."

    # 设置 emerge 命令（根据是否使用二进制包）
    local emerge_cmd="emerge"
    if [[ "$USE_BINARY_PACKAGES" == "yes" ]]; then
        emerge_cmd="emerge --getbinpkg --binpkg-respect-use=y"
        log_info "使用预编译二进制包模式 (加快安装速度)"
    else
        log_info "使用源码编译模式"
    fi

    # 更新 @world set
    log_info "更新系统 @world..."
    chroot /mnt/gentoo $emerge_cmd --update --deep --newuse @world

    # 安装 X11
    log_info "安装 X11..."
    chroot /mnt/gentoo $emerge_cmd x11-base/xorg-x11

    # 安装 SDDM 登录管理器（正确的包分类）
    log_info "安装 SDDM..."
    chroot /mnt/gentoo $emerge_cmd x11-misc/sddm

    # 安装 KDE Plasma
    log_info "安装 KDE Plasma..."
    chroot /mnt/gentoo $emerge_cmd kde-plasma/plasma-meta

    # 安装常用应用
    log_info "安装常用应用..."
    chroot /mnt/gentoo $emerge_cmd kde-apps/konsole kde-apps/kate www-client/firefox-bin

    # 启用 SDDM 自动启动
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        chroot /mnt/gentoo systemctl enable sddm
    else
        # OpenRC: 配置 xdm 使用 sddm
        cat > /mnt/gentoo/etc/conf.d/xdm << 'EOF'
DISPLAYMANAGER="sddm"
EOF
        chroot /mnt/gentoo rc-update add xdm default
    fi

    log_success "KDE Plasma 安装完成"
}

# 显示完成信息
show_complete() {
    echo ""
    echo "========================================"
    echo -e "${GREEN}  Gentoo 安装完成！${NC}"
    echo "========================================"
    echo ""
    echo "系统信息:"
    echo "  初始化系统: $INIT_SYSTEM"
    echo "  桌面环境:   KDE Plasma"
    echo "  文件系统:   $ROOT_FS"
    echo "  磁盘:       $DISK"
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
    echo -e "  - ${RED}记得更改 root 密码!${NC}  执行: passwd"
    if [[ -n "${USERNAME:-}" ]]; then
        echo -e "  - ${RED}记得更改 $USERNAME 密码!${NC}  执行: passwd $USERNAME"
    fi
    echo ""
}

# ============ 主函数 ============

main() {
    # 解析命令行参数
    parse_args "$@"

    # 如果只是 dry-run，显示配置后退出
    if $DRY_RUN; then
        echo ""
        echo "========================================"
        echo "  DRY RUN - 仅显示配置，不执行安装"
        echo "========================================"
        show_config
        exit 0
    fi

    check_root
    check_network
    detect_network

    # 自动加载配置（如果没有强制交互模式）
    if ! $FORCE_INTERACTIVE; then
        # 优先使用用户指定的配置文件，其次检查默认位置
        if [[ -n "${CONFIG_TO_LOAD:-}" ]]; then
            load_config "$CONFIG_TO_LOAD"
        elif [[ -f "$CONFIG_FILE" ]]; then
            load_config "$CONFIG_FILE"
        elif [[ -f "$LOCAL_CONFIG" ]]; then
            load_config "$LOCAL_CONFIG"
        fi
    fi

    # 如果没有加载到配置，或者强制交互模式，进入交互配置
    if $FORCE_INTERACTIVE || [[ -z "${HOSTNAME:-}" ]] || [[ -z "${DISK:-}" ]]; then
        interactive_config
        # 交互配置完成后自动保存
        save_config "$CONFIG_FILE"
    else
        # 显示即将使用的配置
        echo ""
        log_info "将使用保存的配置进行安装:"
        echo ""
        echo "  初始化系统: $INIT_SYSTEM"
        echo "  磁盘:       $DISK"
        echo "  主机名:     $HOSTNAME"
        echo "  时区:       $TIMEZONE"
        echo "  文件系统:   $ROOT_FS"
        echo "  二进制包:   $USE_BINARY_PACKAGES"
        echo ""

        # 检查默认密码
        if [[ "$ROOT_PASSWORD" == "gentoo" ]]; then
            echo -e "${YELLOW}⚠ 警告: 正在使用默认 root 密码 'gentoo'，安装后请立即更改！${NC}"
        fi

        read -p "确认开始安装? (y/n) [y]: " confirm
        [[ "$confirm" =~ ^[Nn]$ ]] && exit 0
    fi

    log_info "开始 Gentoo 安装..."
    echo ""

    # 安装步骤（严格按顺序执行）
    partition_disk
    install_stage3
    configure_make_conf
    configure_portage
    sync_portage
    configure_locale
    configure_network
    install_firmware
    install_kernel
    install_bootloader
    create_users
    install_network_manager
    install_kde_plasma

    show_complete
}

# 运行
main "$@"
