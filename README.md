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
./panel up            # khởi động MySQL đích (mysql80) + canal-server + canal-adapter
./panel new           # thêm 1 nguồn: nhập host/user/db, chọn bảng (tự nạp lại canal)
./panel etl <tên>     # tự tạo bảng ở đích + đổ data cũ + bật realtime
./panel status        # kiểm tra đồng bộ
```

## Cấu trúc repo

```
panel                      # CLI chính (9 lệnh)
canal-healthcheck.sh       # panel status gọi cái này
docker-compose.yml         # MySQL đích + canal-server + canal-adapter (+ admin nếu cần)
docker-compose.lab.yml     # overlay CHỈ để test local (thêm MySQL 5.5 giả làm game)
canal/base-conf/           # conf GỐC Canal — panel init copy sang server-conf
canal-multi/templates/     # khuôn instance.properties + canal.properties (panel dùng sinh config)
init/                      # schema MySQL mẫu (cho lab test)
docs/
  panel-cli-guide.md       # ⭐ hướng dẫn đầy đủ panel + bug đã fix
```

## Được sinh ra khi chạy (KHÔNG nằm trong repo — xem .gitignore)
- `.panel/servers/*.conf` — đăng ký mỗi nguồn (chứa mật khẩu → không commit)
- `canal/server-conf/` — copy từ base-conf + instance của mỗi nguồn
- `canal/adapter-conf/` — application.yml + mapping .yml

## Tài liệu
- **Hướng dẫn từng bước (đã kiểm chứng):** [docs/huong-dan-test-local-va-vps.md](docs/huong-dan-test-local-va-vps.md) — test local + chạy thật VPS qua ngrok.
- **Tra cứu lệnh:** [docs/panel-cli-guide.md](docs/panel-cli-guide.md) — mọi lệnh, quy trình, bug đã fix.

## Test local (không có DB game thật)
Dựng thêm MySQL 5.5 giả làm nguồn:
```bash
docker compose -f docker-compose.yml -f docker-compose.lab.yml up -d
./panel new   # host nguồn = mysql55, port 3306
```

## Lưu ý khi lên VPS thật
Chạy y hệt máy local: `./panel init && ./panel up`. Compose dùng mạng Docker (bridge), các container
gọi nhau bằng tên service (`canal-server`, `mysql80`) — KHÔNG cần sửa gì trong `panel`.
Nguồn (DB game) ở ngoài → nhập host/port khi `./panel new` (vd host/port ngrok, hoặc IP game thật).

## An toàn
- KHÔNG commit: dump data (`*.sql`), `.panel/` (mật khẩu). Đã chặn trong `.gitignore`.
- Đổi mọi mật khẩu mẫu (`root`, `cdc`) trước khi dùng thật.
