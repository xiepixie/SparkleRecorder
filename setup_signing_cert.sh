#!/bin/bash
set -e

CERT_NAME="Apple Development: TinyRecorder Local"
CER_PATH="/tmp/tiny_local.cer"
KEY_PATH="/tmp/tiny_local.key"
P12_PATH="/tmp/tiny_local.p12"
PASSWORD="local_dev_pass"

echo "============================================="
echo "  正在创建本地自签名代码签名证书以保持系统授权  "
echo "============================================="

# 1. 生成自签名证书
echo "→ 1/4. 正在生成 2048 位开发私钥和证书..."
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
  -subj "/CN=${CERT_NAME}/O=Local Developer/C=CN" \
  -keyout "${KEY_PATH}" -out "${CER_PATH}" 2>/dev/null

# 2. 打包为 PKCS12 (.p12)
echo "→ 2/4. 正在打包证书..."
if openssl pkcs12 -export -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -inkey "${KEY_PATH}" -in "${CER_PATH}" -out "${P12_PATH}" -passout pass:${PASSWORD} 2>/dev/null; then
    :
elif openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -inkey "${KEY_PATH}" -in "${CER_PATH}" -out "${P12_PATH}" -passout pass:${PASSWORD} 2>/dev/null; then
    :
else
    openssl pkcs12 -export -inkey "${KEY_PATH}" -in "${CER_PATH}" -out "${P12_PATH}" -passout pass:${PASSWORD}
fi

# 3. 导入到登录钥匙串
echo "→ 3/4. 正在导入到您的登录钥匙串中..."
security import "${P12_PATH}" -k ~/Library/Keychains/login.keychain-db -P ${PASSWORD} -T /usr/bin/codesign || true

# 4. 提升为系统受信任证书 (需要 root 权限，可能会弹出密码框)
echo "→ 4/4. 正在请求系统管理员权限以将证书设为'始终信任'..."
echo "       [提示] 终端稍后可能会提示您输入 Mac 开机密码以更新系统信任设置"
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "${CER_PATH}"

# 清理临时文件
rm -f "${KEY_PATH}" "${CER_PATH}" "${P12_PATH}"

echo "============================================="
echo "✅ 证书创建并信任成功！"
echo "   证书名称: ${CERT_NAME}"
echo "============================================="
