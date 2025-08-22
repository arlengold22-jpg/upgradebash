#!/bin/bash
# CentOS7 升级 OpenSSL + OpenSSH 脚本（带自动修复）
# root 用户执行

set -e

OPENSSL_VERSION="1.1.1w"   # OpenSSL LTS
OPENSSH_VERSION="9.7p1"    # OpenSSH 最新版
SRC_DIR="/usr/local/src"

echo "[1/7] 安装依赖..."
yum -y groupinstall "Development Tools"
yum -y install wget tar gcc make zlib-devel pam-devel

mkdir -p $SRC_DIR
cd $SRC_DIR

echo "[2/7] 升级 OpenSSL..."
wget -O openssl.tar.gz https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz
tar xzf openssl.tar.gz
cd openssl-$OPENSSL_VERSION
./config --prefix=/usr --openssldir=/etc/ssl --shared
make -j$(nproc)
make install
ldconfig
echo "当前 OpenSSL: $(openssl version)"
cd ..

echo "[3/7] 升级 OpenSSH..."
wget -O openssh.tar.gz https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-$OPENSSH_VERSION.tar.gz
tar xzf openssh.tar.gz
cd openssh-$OPENSSH_VERSION
./configure --prefix=/usr --sysconfdir=/etc/ssh --with-pam --with-ssl-engine
make -j$(nproc)
make install
cd ..

echo "[4/7] 配置 systemd..."
cat >/usr/lib/systemd/system/sshd.service <<EOF
[Unit]
Description=OpenSSH server daemon
After=network.target

[Service]
ExecStart=/usr/sbin/sshd -D
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "[5/7] 生成缺失的 host key..."
ssh-keygen -A

echo "[6/7] 修复 host key 权限..."
chmod 600 /etc/ssh/ssh_host_*_key || true
chmod 644 /etc/ssh/ssh_host_*_key.pub || true
chown root:root /etc/ssh/ssh_host_* || true

echo "[7/7] 修复配置并启动 sshd..."
# 注释掉不再支持的配置
sed -i 's/^[[:space:]]*GSSAPIAuthentication/#&/' /etc/ssh/sshd_config || true
sed -i 's/^[[:space:]]*GSSAPICleanupCredentials/#&/' /etc/ssh/sshd_config || true

systemctl daemon-reexec
systemctl enable sshd
systemctl restart sshd

echo "✅ 升级完成!"
echo -n "OpenSSL 版本: "; openssl version
echo -n "OpenSSH 版本: "; ssh -V
systemctl status sshd -l --no-pager | head -20

