#!/usr/bin/env bash
# =============================================================
# canal-healthcheck.sh — kiểm tra sức khỏe đồng bộ Canal (đa nguồn).
# Đọc registry .panel/servers/*.conf → kiểm tra TỪNG server:
#   [1] tiến trình sống  [2] số dòng nguồn↔đích  [3] lệch cấu trúc (đổi tên/thêm/xóa cột, TRUNCATE)
#
# Dùng qua panel:  ./panel status      (hoặc chạy trực tiếp: ./canal-healthcheck.sh)
# =============================================================
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_DIR="$ROOT/.panel/servers"
DST_CONTAINER="${DST_CONTAINER:-lab-mysql80}"   # container MySQL đích + làm máy trạm mysql client
DST_ROOT_PASS="${DST_ROOT_PASS:-root}"

R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[36m'; N=$'\e[0m'
ok(){ echo "${G}✓${N} $1"; }; warn(){ echo "${Y}!${N} $1"; }; err(){ echo "${R}✗${N} $1"; }

# mysql qua container đích: q <host> <port> <user> <pass> <db> "<sql>"
q(){ docker exec "$DST_CONTAINER" mysql -h"$1" -P"$2" -u"$3" -p"$4" ${5:+"$5"} -sN -e "$6" 2>/dev/null; }

echo "===== CANAL HEALTHCHECK ====="

# [1] tiến trình
echo ""; echo "[1] Tiến trình:"
for c in lab-canal-server lab-canal-adapter; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
  [ "$st" = "running" ] && ok "$c: running" || err "$c: ${st:-KHÔNG TỒN TẠI}"
done

# không có registry → báo và thoát
ls "$REG_DIR"/*.conf >/dev/null 2>&1 || { echo ""; warn "chưa có nguồn nào (.panel/servers rỗng) — dùng ./panel new"; exit 0; }

# duyệt từng server trong registry
for f in "$REG_DIR"/*.conf; do
  ( source "$f"
    echo ""; echo "${B}== $NAME : $SRC_HOST:$SRC_PORT/$SRC_DB → $DST_DB ==${N}"

    for t in $TABLES; do
      # [2] số dòng nguồn ↔ đích
      s=$(q "$SRC_HOST" "$SRC_PORT" "$SRC_USER" "$SRC_PASS" "$SRC_DB" "SELECT COUNT(*) FROM \`$t\`;")
      d=$(q "$DST_CONTAINER" 3306 root "$DST_ROOT_PASS" "$DST_DB" "SELECT COUNT(*) FROM \`$t\`;")
      if [ -z "$s" ] || [ -z "$d" ]; then err "$t: không đọc được (nguồn='$s' đích='$d')"
      elif [ "$s" = "$d" ]; then ok "$t: nguồn=$s đích=$d (KHỚP)"
      else warn "$t: nguồn=$s đích=$d (LỆCH $((s-d)) — đang trễ / thiếu / TRUNCATE?)"; fi

      # [3] lệch cấu trúc: so danh sách cột nguồn↔đích
      cs=$(q "$SRC_HOST" "$SRC_PORT" "$SRC_USER" "$SRC_PASS" "" "SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY COLUMN_NAME) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$SRC_DB' AND TABLE_NAME='$t';")
      cd=$(q "$DST_CONTAINER" 3306 root "$DST_ROOT_PASS" "" "SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY COLUMN_NAME) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DST_DB' AND TABLE_NAME='$t';")
      [ "$cs" = "$cd" ] || err "$t: LỆCH CỘT — nguồn[$cs] vs đích[$cd] → kiểm tra ALTER/đổi tên cột!"
    done
  )
done

echo ""; echo "===== HẾT ====="
