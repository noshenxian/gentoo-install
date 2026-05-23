# Gentoo Install Script

Gentoo Linux 自动安装脚本，支持交互式配置和一键安装。

## 功能特性

- 交互式磁盘选择
- 自动检测可用磁盘
- 用户配置（可创建普通用户）
- 时区选择（支持常用时区）
- 中科大/清华大学镜像源
- 预编译二进制包支持（加快安装速度）
- 配置保存和加载
- KDE Plasma 桌面环境

## 系统要求

- x86_64 架构
- UEFI 启动
- 至少 20GB 可用磁盘空间
- 网络连接

## 快速开始

### 1. 下载 Gentoo 最小化安装 ISO

从 [Gentoo 下载页面](https://www.gentoo.org/downloads/) 下载最小化安装 ISO 并制作启动盘。

### 2. 启动并连接网络

```bash
# 有线网络 (DHCP)
dhcpcd

# 无线网络
iwctl
```

### 3. 下载并运行安装脚本

```bash
# 下载脚本
wget https://raw.githubusercontent.com/noshenxian/gentoo-install/main/gentoo-install.sh

# 添加执行权限
chmod +x gentoo-install.sh

# 运行安装（首次会进入交互配置）
./gentoo-install.sh
```

## 使用方法

```bash
# 首次运行 - 进入交互配置
./gentoo-install.sh

# 使用已保存的配置
./gentoo-install.sh

# 查看当前配置
./gentoo-install.sh -s

# 重新配置
./gentoo-install.sh -r

# 使用指定配置文件
./gentoo-install.sh -c /path/to/config.conf

# 仅查看配置，不执行安装
./gentoo-install.sh -d
```

## 配置选项

### 交互式配置

脚本会提示以下配置项：

| 选项 | 说明 | 默认值 |
|------|------|--------|
| 磁盘选择 | 选择安装目标磁盘 | /dev/sda |
| 主机名 | 计算机名称 | gentoo-laptop |
| 时区 | 系统时区 | Asia/Shanghai |
| Root 密码 | root 账户密码 | - |
| 普通用户 | 是否创建普通用户 | yes |
| 用户名 | 普通用户名 | user |
| 用户密码 | 普通用户密码 | - |
| 二进制包 | 是否使用预编译包 | yes |

### 手动配置

编辑脚本顶部的配置区域：

```bash
# 磁盘配置
DISK="/dev/sda"
EFI_SIZE=512
SWAP_SIZE=4096

# 系统配置
HOSTNAME="gentoo-laptop"
TIMEZONE="Asia/Shanghai"

# 二进制包
USE_BINARY_PACKAGES="yes"
```

## 安装流程

1. 分区和格式化 (UEFI + GPT)
2. 下载并解压 Stage3
3. 配置 Portage 和镜像源
4. 配置时区和 locale
5. 配置网络
6. 编译安装 Linux 内核
7. 安装 GRUB 引导程序
8. 安装 KDE Plasma 桌面环境
9. 安装 NetworkManager

## 镜像源

默认使用以下中国镜像源：

- 中科大镜像源: `https://mirrors.ustc.edu.cn/gentoo`
- 清华大学镜像源: `https://mirrors.tuna.tsinghua.edu.cn/gentoo`

## 二进制包

启用二进制包可大幅加快安装速度：

```bash
USE_BINARY_PACKAGES="yes"
```

KDE Plasma 等大型软件包会从预编译仓库下载，而非本地编译。

## 安装后

1. 重启系统
2. 首次登录后配置 WiFi（使用 nmtui 或 Plasma 网络设置）
3. 记得更改 root 密码！

## 故障排除

### 网络问题

```bash
# 检查网络状态
ip link show
ping -c 3 gentoo.org
```

### 分区问题

```bash
# 查看当前分区
lsblk
fdisk -l /dev/sda
```

### 安装失败

```bash
# 重新配置
./gentoo-install.sh -r
```

## License

MIT License

## Contributing

Issues and pull requests are welcome!
