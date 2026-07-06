# panel — CLI quản lý CDC Canal đa nguồn

Công cụ gói mọi thao tác Canal thành vài lệnh. Thay vì nhớ docker/curl/sửa file, chỉ gõ `./panel <lệnh>`.
Đã kiểm chứng thực tế: 1 canal-server + 1 canal-adapter phục vụ **nhiều nguồn** cùng lúc → mỗi nguồn 1 database đích riêng.

## Kiến trúc

```
1 canal-server ─┬─ instance s1 (đọc binlog game S1) ─┐
                ├─ instance s2 (đọc binlog game S2) ─┤
                └─ instance s3 (...)                 │
1 canal-adapter ── ghi vào ──> MySQL 8.0: tlbbdb_s1 / tlbbdb_s2 / tlbbdb_s3
```

**Nguồn sự thật** = `.panel/servers/<name>.conf` (mỗi nguồn 1 file khai báo).
Từ đó panel **sinh lại tự động**: instance.properties + mapping .yml + canal.destinations + application.yml.
→ KHÔNG bao giờ sửa file config Canal bằng tay.

## Cây thư mục

```
panel                         # CLI (file này)
canal-healthcheck.sh          # panel status gọi cái này
docker-compose.yml            # mount canal/server-conf + canal/adapter-conf (cố định)
.panel/servers/<name>.conf    # đăng ký mỗi nguồn (nguồn sự thật)
canal/server-conf/            # panel sinh: canal.properties + <name>/instance.properties
canal/adapter-conf/           # panel sinh: application.yml + rdb/<name>_<table>.yml
canal-multi/templates/        # template gốc (instance.properties, canal.properties)
```

## Các lệnh

| Lệnh | Việc |
|---|---|
| `./panel init` | Sang VPS mới: check docker + kiểm tra cấu trúc |
| `./panel new` | Thêm 1 nguồn: hỏi tên/nguồn/đích/chọn bảng → sinh hết config |
| `./panel up` | (Re)khởi động server+adapter — dùng sau `new`/`rm` |
| `./panel down` | Tắt toàn bộ |
| `./panel etl <name>` | Nạp data cũ (initial load) cho 1 nguồn |
| `./panel status` | Kiểm tra sức khỏe từng nguồn (sống/chết, lệch dòng, lệch cột) |
| `./panel logs [name]` | Xem log canal |
| `./panel list` | Liệt kê các nguồn đã cấu hình |
| `./panel rm <name>` | Xóa 1 nguồn |

## Quy trình thêm 1 nguồn (2 bước)

```bash
./panel new           # 1. khai báo + chọn bảng (đánh số "1,3,5"/"all"). Tự nạp lại canal.
./panel etl <name>    # 2. tự tạo khung bảng ở đích + đổ data cũ + bật realtime
```

`panel new` tự gọi `up` ở cuối (recreate server+adapter để Canal nhận nguồn mới).
`panel etl` tự copy khung bảng nguồn→đích trước khi đổ data:
- chỉ tạo bảng CHƯA có ở đích (bảng đã có → giữ nguyên, không mất data)
- dùng `mysqldump --single-transaction` (KHÔNG cần quyền LOCK TABLES trên nguồn)

## Quy trình đồng bộ ĐÚNG (2 nhịp — nhớ kỹ)

1. **Nạp data cũ (ETL)** — `./panel etl <name>` — LÀM 1 LẦN. Bỏ qua thì UPDATE/DELETE dòng cũ vô nghĩa (đích rỗng).
2. **Realtime** — tự động sau khi canal chạy. Sửa nguồn → đích cập nhật sau vài giây.

## Panel tự lo giùm (không phải nghĩ)

- **Charset**: tự nhận utf8mb4 / latin1 của nguồn → set đúng Canal + JDBC (tránh vỡ tiếng Việt).
- **slaveId**: mỗi nguồn 1 số riêng (1234, 1235...) — không trùng, tránh rớt kết nối.
- **canal.destinations**: tự thêm tên nguồn mới.
- **tsdb.enable=false**: bắt buộc, nếu không instance mới lỗi GetConnectionTimeout.
- **database đích**: tự tạo (rỗng) với đúng charset.

## Các bug đã fix (đừng vấp lại)

| Triệu chứng | Nguyên nhân | Đã xử lý trong panel |
|---|---|---|
| adapter `NullPointerException` khi khởi động | `application.yml` thiếu 3 dòng `timeout:` `accessKey:` `secretKey:` | panel luôn sinh đủ |
| instance mới `GetConnectionTimeout` (không đọc binlog) | thiếu `canal.instance.tsdb.enable=false` | panel ép false mỗi instance |
| ETL báo `Task not found` | gọi sai tên file mapping | panel dùng đúng `<name>_<table>.yml` |
| adapter `Broken pipe`, ngừng sync | recreate server mà không recreate adapter | `panel up` recreate CẢ hai |

## Lưu ý khi lên VPS thật (giống hệt lab)

Chạy y hệt: `./panel init && ./panel up`. Compose dùng mạng Docker (bridge) → container gọi nhau bằng
tên service (`canal-server`, `mysql80`). KHÔNG cần sửa `panel`. Nguồn (DB game) ở ngoài → khi `./panel new`
nhập `SRC_HOST`/port là địa chỉ nguồn thật (IP game hoặc host+port ngrok/tunnel).

> Chỉ khi tự đổi compose sang `network_mode: host` mới cần override `CANAL_SERVER_HOST`/`DST_JDBC_HOST` = `127.0.0.1`.

## Ép RAM (nếu VPS chật)

Canal (Java) mặc định chiếm ~1.2GB/tiến trình. Ép xuống qua biến môi trường trong docker-compose:
```yaml
environment:
  JAVA_OPTS: "-Xms256m -Xmx512m"   # canal-server / canal-adapter
```

## Câu hỏi chưa giải quyết

- Bảng game có cột BLOB / thiếu khóa chính → panel bỏ qua bảng thiếu PK; BLOB cần test riêng.
- ETL data rất lớn (bảng vài triệu dòng) có thể Deadlock/timeout khi nạp 1 phát → cân nhắc chia nhỏ hoặc nạp lúc tải thấp.
- DB game trộn charset (account=utf8mb4, t_char=latin1) → mỗi database 1 charset; nếu 1 database có bảng trộn charset thì cần kiểm tra thêm.
