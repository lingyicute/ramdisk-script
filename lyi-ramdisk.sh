#!/bin/bash
 
set -euo pipefail

# 检查是否有足够的权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：本脚本需要 root 权限才能挂载 ramdisk 。请使用 sudo 运行。"
    exit 1
fi

echo "正在检查 lyi-ramdisk 是否已挂载..."

MOUNT_DIR="$(pwd)/lyi-ramdisk"
if mountpoint -q "$MOUNT_DIR"; then
  echo "错误：lyi-ramdisk 已经挂载为 ramdisk。如需重新设置，请先卸载它。"
  exit 1
fi

echo "正在检查 lyi-ramdisk 文件夹是否存在..."
if [ -d "lyi-ramdisk" ]; then
    echo "lyi-ramdisk 文件夹已存在，跳过创建。"
    if [ "$(ls -A lyi-ramdisk)" ]; then
        echo "警告：lyi-ramdisk 目录非空。继续挂载将覆盖现有内容。"
        read -p "是否继续？(y/n) " confirm
        case "$confirm" in
            [Yy]) ;;
			*) exit 1 ;;
		esac
    fi
else
    mkdir -p lyi-ramdisk
    echo "创建 lyi-ramdisk 文件夹成功。"
fi

echo "正在计算可用内存大小..."
if grep -q 'MemAvailable:' /proc/meminfo; then
    available_mem=$(grep 'MemAvailable:' /proc/meminfo | awk '{print $2}')
else
    MemFree=$(grep 'MemFree:' /proc/meminfo | awk '{print $2}')
    Buffers=$(grep 'Buffers:' /proc/meminfo | awk '{print $2}')
    Cached=$(grep '^Cached:' /proc/meminfo | awk '{print $2}')
    available_mem=$((MemFree + Buffers + Cached))
fi
ramdisk_size=$(($available_mem * 80 / 100))
echo "可用内存: $available_mem KB，将使用 $ramdisk_size KB (80%) 作为ramdisk大小。"

echo "正在挂载 lyi-ramdisk 为ramdisk..."
mount -t tmpfs -o size=${ramdisk_size}k,mode=777 tmpfs "$MOUNT_DIR"
if [ $? -eq 0 ]; then
    echo "挂载 lyi-ramdisk 为 ramdisk 成功。"
else
    echo "挂载 lyi-ramdisk 为 ramdisk 失败，请检查您的权限。"
    exit 1
fi

echo "正在创建 clean.sh 脚本..."
cat > lyi-ramdisk/clean.sh << 'EOF'
#!/bin/bash
# 检查是否有足够的权限
if [ "$(id -u)" -ne 0 ]; then
    echo "警告：您可能没有足够的权限清空某些文件。如果遇到权限问题，请尝试使用sudo运行。"
fi

if ! mountpoint -q "$(dirname "$0")"; then
    echo "错误：目录未挂载，拒绝清理以避免数据损坏。"
    exit 1
fi

cd "$(dirname "$0")" || { echo "错误：无法进入 lyi-ramdisk 目录"; exit 1; }
echo "正在清空 lyi-ramdisk 目录内容..."
# 查找并删除当前目录下除了clean.sh和stop.sh之外的所有文件
find . -type f -not -name "clean.sh" -not -name "stop.sh" -exec rm -f "{}" \;
# 删除所有子目录
find . -mindepth 1 -type d -exec rm -rf "{}" \;
echo "清空 lyi-ramdisk 目录内容完成。"
EOF
chmod +x lyi-ramdisk/clean.sh
echo "创建 clean.sh 脚本成功。"

echo "正在创建 stop.sh 脚本..."
cat > lyi-ramdisk/stop.sh << 'EOF'
#!/bin/bash
# 检查是否有足够的权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：本脚本需要root权限才能卸载ramdisk。请使用sudo运行。"
    exit 1
fi

# 获取ramdisk的绝对路径
RAMDISK_PATH=$(cd "$(dirname "$0")" && pwd)

# 检查当前目录是否在ramdisk中
if [[ "$(pwd)" == "$RAMDISK_PATH"* ]]; then
    echo "错误：请先退出 lyi-ramdisk 目录后再运行此脚本。"
    echo "例如：cd / 然后再运行 sudo $RAMDISK_PATH/stop.sh"
    exit 1
fi

echo "正在卸载 lyi-ramdisk..."
umount "${RAMDISK_PATH}"
if [ $? -eq 0 ]; then
    echo "卸载 lyi-ramdisk 成功。"
    echo "正在删除 lyi-ramdisk 目录..."
    rm -rf "${RAMDISK_PATH}"
    if [ $? -eq 0 ]; then
        echo "删除 lyi-ramdisk 目录成功。"
    else
        echo "删除 lyi-ramdisk 目录失败，请检查目录是否为空或权限是否足够。"
    fi
else
    echo "卸载 lyi-ramdisk 失败，请检查是否有进程正在使用该目录。"
fi
EOF
chmod +x lyi-ramdisk/stop.sh
echo "创建 stop.sh 脚本成功。"
echo "----------------------------------------------"
echo "ramdisk 设置完成！"
echo "----------------------------------------------"
echo "lyi-ramdisk 目录已挂载为 ramdisk，大小为：$ramdisk_size KB"
echo "您可以在 lyi-ramdisk 目录中存储临时文件，这些文件将存储在内存中"
echo "----------------------------------------------"
echo "提供的管理工具："
echo "1. sudo ./lyi-ramdisk/clean.sh - 清空 ramdisk 中的所有内容（保留管理脚本）"
echo "2. sudo ./lyi-ramdisk/stop.sh - 卸载 ramdisk 并删除目录（请先退出 lyi-ramdisk 目录再运行）"
echo "----------------------------------------------"
echo "请注意：系统重启后，ramdisk中的数据会丢失"
echo "----------------------------------------------"
