# canal-cdc-panel

Bộ công cụ đồng bộ dữ liệu **MySQL → MySQL** bằng Canal (CDC / Change Data Capture), quản lý qua CLI `panel`.
Dùng để tạo **bản sao (replica)** của DB game ở nơi khác (vd panel admin trên VPS Singapore), giảm độ trễ query.

- **1 canal-server + 1 canal-adapter** phục vụ **nhiều nguồn** cùng lúc → mỗi nguồn 1 database đích riêng.
- Đọc binlog (KHÔNG trigger, KHÔNG Kafka, KHÔNG viết code) — chỉ file cấu hình do `panel` tự sinh.
- Đã kiểm chứng: MySQL 5.5.62 → MySQL 8.0, data game thật.

## Yêu cầu
- Docker + Docker Compose
- Nguồn MySQL đã bật binlog (`log_bin=ON`, `binlog_format=ROW`) + user có quyền `REPLICATION SLAVE, REPLICATION CLIENT, SELECT`

## Chạy nhanh (clone về là chạy)

```bash
git clone <repo-url> canal-cdc-panel && cd canal-cdc-panel
./panel init          # check docker + dựng cấu trúc conf (copy base-conf -> server-conf)
./panel up            # khởi động MySQL đích + canal-server + canal-adapter
./panel new           # thêm 1 nguồn: nhập host/user/db, chọn bảng
# tạo cấu trúc bảng ở đích (xem docs/panel-cli-guide.md) rồi:
./panel up            # nạp nguồn mới
./panel etl <tên>     # nạp data cũ 1 lần
./panel status        # kiểm tra đồng bộ
```

## Cấu trúc repo

```
panel                      # CLI chính (9 lệnh)
canal-healthcheck.sh       # panel status gọi cái này
docker-compose.yml         # MySQL đích + canal-server + canal-adapter (+ admin nếu cần)
canal/base-conf/           # conf GỐC Canal — panel init copy sang server-conf
canal-multi/templates/     # khuôn instance.properties + canal.properties (panel dùng sinh config)
init/                      # schema MySQL mẫu (cho lab test)
docs/
  panel-cli-guide.md       # ⭐ hướng dẫn đầy đủ panel + bug đã fix
  canal-deploy-*.md        # hướng dẫn triển khai local -> VPS (ngrok/tunnel)
```

## Được sinh ra khi chạy (KHÔNG nằm trong repo — xem .gitignore)
- `.panel/servers/*.conf` — đăng ký mỗi nguồn (chứa mật khẩu → không commit)
- `canal/server-conf/` — copy từ base-conf + instance của mỗi nguồn
- `canal/adapter-conf/` — application.yml + mapping .yml

## Tài liệu
- **Bắt đầu ở đây:** [docs/panel-cli-guide.md](docs/panel-cli-guide.md) — mọi lệnh, quy trình, bug đã fix.
- Triển khai local→VPS: [docs/canal-deploy-local-mysql55-to-vps-mysql80-guide.md](docs/canal-deploy-local-mysql55-to-vps-mysql80-guide.md)

## Lưu ý khi lên VPS thật
Lab dùng mạng Docker (tên service `mysql80`, `canal-server`). VPS thật thường `network_mode: host` → sửa 2 biến đầu file `panel`:
```bash
CANAL_SERVER_HOST=127.0.0.1:11111
DST_JDBC_HOST=127.0.0.1:3306
```

## An toàn
- KHÔNG commit: dump data (`*.sql`), `.panel/` (mật khẩu). Đã chặn trong `.gitignore`.
- Đổi mọi mật khẩu mẫu (`root`, `cdc`) trước khi dùng thật.
