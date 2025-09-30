#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Cloudflare DNS 记录更新脚本
# 用法: ./update-dns.sh -k API密钥 -u 邮箱 -z 域名 -h 主机记录 -i IP地址 [-t A|AAAA] [-l 120]

# 默认配置
CFKEY=""
CFUSER=""
CFZONE_NAME=""
CFRECORD_NAME=""
TARGET_IP=""
CFRECORD_TYPE="A"
CFTTL=120

# 获取参数
while getopts k:u:z:h:i:t:l: opts; do
  case ${opts} in
    k) CFKEY=${OPTARG} ;;
    u) CFUSER=${OPTARG} ;;
    z) CFZONE_NAME=${OPTARG} ;;
    h) CFRECORD_NAME=${OPTARG} ;;
    i) TARGET_IP=${OPTARG} ;;
    t) CFRECORD_TYPE=${OPTARG} ;;
    l) CFTTL=${OPTARG} ;;
  esac
done

# 检查必需参数
if [ -z "$CFKEY" ]; then
  echo "错误: 缺少 API 密钥 (-k)"
  echo "使用方法: $0 -k API密钥 -u 邮箱 -z 域名 -h 主机记录 -i IP地址"
  exit 1
fi

if [ -z "$CFUSER" ]; then
  echo "错误: 缺少用户邮箱 (-u)"
  exit 1
fi

if [ -z "$CFZONE_NAME" ]; then
  echo "错误: 缺少域名 (-z)"
  exit 1
fi

if [ -z "$CFRECORD_NAME" ]; then
  echo "错误: 缺少主机记录 (-h)"
  exit 1
fi

if [ -z "$TARGET_IP" ]; then
  echo "错误: 缺少目标 IP 地址 (-i)"
  exit 1
fi

# 验证记录类型
if [ "$CFRECORD_TYPE" != "A" ] && [ "$CFRECORD_TYPE" != "AAAA" ]; then
  echo "错误: 记录类型只能是 A (IPv4) 或 AAAA (IPv6)"
  exit 1
fi

# 如果主机记录不是完整域名，则补全
if [ "$CFRECORD_NAME" != "$CFZONE_NAME" ] && ! [ -z "${CFRECORD_NAME##*$CFZONE_NAME}" ]; then
  CFRECORD_NAME="$CFRECORD_NAME.$CFZONE_NAME"
  echo "=> 补全为完整域名: $CFRECORD_NAME"
fi

echo "========================================="
echo "Cloudflare DNS 更新"
echo "========================================="
echo "域名: $CFZONE_NAME"
echo "记录: $CFRECORD_NAME"
echo "类型: $CFRECORD_TYPE"
echo "目标IP: $TARGET_IP"
echo "TTL: $CFTTL"
echo "========================================="

# 获取 Zone ID
echo "正在获取 Zone ID..."
CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" \
  | grep -Po '(?<="id":")[^"]*' | head -1)

if [ -z "$CFZONE_ID" ]; then
  echo "错误: 无法获取 Zone ID，请检查域名和 API 凭证"
  exit 1
fi
echo "Zone ID: $CFZONE_ID"

# 获取 Record ID
echo "正在获取 Record ID..."
CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" \
  | grep -Po '(?<="id":")[^"]*' | head -1)

if [ -z "$CFRECORD_ID" ]; then
  echo "错误: 无法获取 Record ID，请检查主机记录是否存在"
  exit 1
fi
echo "Record ID: $CFRECORD_ID"

# 更新 DNS 记录
echo "正在更新 DNS 记录..."
RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$TARGET_IP\",\"ttl\":$CFTTL}")

# 检查结果
if [ "$RESPONSE" != "${RESPONSE%success*}" ] && [ "$(echo $RESPONSE | grep "\"success\":true")" != "" ]; then
  echo "========================================="
  echo "✓ DNS 更新成功!"
  echo "  $CFRECORD_NAME -> $TARGET_IP"
  echo "========================================="
  exit 0
else
  echo "========================================="
  echo "✗ DNS 更新失败"
  echo "响应: $RESPONSE"
  echo "========================================="
  exit 1
fi
