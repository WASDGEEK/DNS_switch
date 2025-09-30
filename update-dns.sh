#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Cloudflare DNS 记录更新脚本
# 用法: ./update-dns.sh [-c config.yml] 或使用命令行参数覆盖配置文件

# 默认配置文件路径
CONFIG_FILE="config.yml"

# 解析 YAML 配置文件的函数
parse_yaml() {
  local file=$1
  local prefix=$2
  
  if [ ! -f "$file" ]; then
    return
  fi
  
  # 简单的 YAML 解析（支持基本的 key: value 格式）
  while IFS=': ' read -r key value; do
    # 跳过空行和注释
    [[ -z "$key" || "$key" =~ ^#.*$ ]] && continue
    
    # 移除前后空格和引号
    key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^["'\'']*//;s/["'\'']*$//')
    
    # 跳过空值
    [[ -z "$value" ]] && continue
    
    # 设置变量
    case "$key" in
      api_key|CFKEY) CFKEY="$value" ;;
      email|CFUSER) CFUSER="$value" ;;
      zone|CFZONE_NAME) CFZONE_NAME="$value" ;;
      record|CFRECORD_NAME) CFRECORD_NAME="$value" ;;
      ip|TARGET_IP) TARGET_IP="$value" ;;
      type|CFRECORD_TYPE) CFRECORD_TYPE="$value" ;;
      ttl|CFTTL) CFTTL="$value" ;;
    esac
  done < "$file"
}

# 初始化默认值
CFKEY=""
CFUSER=""
CFZONE_NAME=""
CFRECORD_NAME=""
TARGET_IP=""
CFRECORD_TYPE="A"
CFTTL=120

# 获取参数（包括配置文件路径）
while getopts c:k:u:z:h:i:t:l: opts; do
  case ${opts} in
    c) CONFIG_FILE=${OPTARG} ;;
    k) CFKEY_CLI=${OPTARG} ;;
    u) CFUSER_CLI=${OPTARG} ;;
    z) CFZONE_NAME_CLI=${OPTARG} ;;
    h) CFRECORD_NAME_CLI=${OPTARG} ;;
    i) TARGET_IP_CLI=${OPTARG} ;;
    t) CFRECORD_TYPE_CLI=${OPTARG} ;;
    l) CFTTL_CLI=${OPTARG} ;;
  esac
done

# 读取配置文件
if [ -f "$CONFIG_FILE" ]; then
  echo "正在读取配置文件: $CONFIG_FILE"
  parse_yaml "$CONFIG_FILE"
else
  echo "警告: 配置文件 $CONFIG_FILE 不存在，使用命令行参数"
fi

# 命令行参数覆盖配置文件
[ ! -z "${CFKEY_CLI:-}" ] && CFKEY="$CFKEY_CLI"
[ ! -z "${CFUSER_CLI:-}" ] && CFUSER="$CFUSER_CLI"
[ ! -z "${CFZONE_NAME_CLI:-}" ] && CFZONE_NAME="$CFZONE_NAME_CLI"
[ ! -z "${CFRECORD_NAME_CLI:-}" ] && CFRECORD_NAME="$CFRECORD_NAME_CLI"
[ ! -z "${TARGET_IP_CLI:-}" ] && TARGET_IP="$TARGET_IP_CLI"
[ ! -z "${CFRECORD_TYPE_CLI:-}" ] && CFRECORD_TYPE="$CFRECORD_TYPE_CLI"
[ ! -z "${CFTTL_CLI:-}" ] && CFTTL="$CFTTL_CLI"

# 检查必需参数
if [ -z "$CFKEY" ]; then
  echo "错误: 缺少 API 密钥"
  echo "请在 config.yml 中配置或使用 -k 参数"
  exit 1
fi

if [ -z "$CFUSER" ]; then
  echo "错误: 缺少用户邮箱"
  echo "请在 config.yml 中配置或使用 -u 参数"
  exit 1
fi

if [ -z "$CFZONE_NAME" ]; then
  echo "错误: 缺少域名"
  echo "请在 config.yml 中配置或使用 -z 参数"
  exit 1
fi

if [ -z "$CFRECORD_NAME" ]; then
  echo "错误: 缺少主机记录"
  echo "请在 config.yml 中配置或使用 -h 参数"
  exit 1
fi

if [ -z "$TARGET_IP" ]; then
  echo "错误: 缺少目标 IP 地址"
  echo "请在 config.yml 中配置或使用 -i 参数"
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
