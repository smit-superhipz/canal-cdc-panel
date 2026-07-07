# Hướng dẫn chạy CDC replicate MySQL → MySQL (đã kiểm chứng thực tế)

Tài liệu này hướng dẫn **từng bước đã test thành công**: đồng bộ dữ liệu từ MySQL nguồn
sang bản sao MySQL 8.0 bằng `panel`. Có 2 phần:
- **PHẦN 1 — Test ở máy local** (dựng nguồn giả bằng Docker)
- **PHẦN 2 — Chạy thật trên VPS** (nguồn = DB game qua ngrok)

Đã kiểm chứng: 2 nguồn cùng lúc, charset lẫn lộn (utf8mb4 + latin1), tiếng Việt không vỡ,
realtime INSERT/UPDATE/DELETE, khớp 100% số dòng.

---

## Khái niệm (đọc 1 lần cho hiểu)

```
NGUỒN (MySQL game)  ──Canal đọc binlog──►  ĐÍCH (MySQL 8.0 = bản sao)  ◄── panel/web đọc
```

- **Nguồn**: DB game (chỉ đọc, KHÔNG đụng vào).
- **Đích**: bản sao MySQL 8.0 đặt cạnh panel → query nhanh (khỏi bay sang VN).
- **Canal**: phần mềm chép thay đổi từ nguồn sang đích, KHÔNG cần viết code.
- **panel**: CLI gói mọi thao tác thành vài lệnh.

Luồng chỉ **3 lệnh**: `up` (dựng máy) → `new` (khai báo nguồn) → `etl` (tạo bảng + đổ data + bật realtime).

---

# PHẦN 1 — TEST Ở MÁY LOCAL

Mục tiêu: chạy thử toàn bộ trong máy Sếp, nguồn giả là MySQL 5.5 trong Docker.

## B1. Dựng stack (nguồn giả + đích + canal)

```bash
cd canal-cdc-panel
./panel init
docker compose -f docker-compose.yml -f docker-compose.lab.yml up -d
```
> File `docker-compose.lab.yml` chỉ dùng để test — nó thêm con MySQL 5.5 giả làm nguồn.

Đợi ~30 giây cho MySQL khỏe.

## B2. Tạo user cdc + data nguồn mẫu

MySQL 5.5 tạo user bằng cú pháp cũ (KHÔNG có `CREATE USER IF NOT EXISTS`):
```bash
docker exec lab-mysql55 mysql -uroot -proot -e "GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'cdc'@'%' IDENTIFIED BY 'cdc123'; FLUSH PRIVILEGES;"
```

Tạo 1 DB nguồn mẫu có tiếng Việt:
```bash
docker exec -i lab-mysql55 mysql -uroot -proot <<'SQL'
CREATE DATABASE shopdb DEFAULT CHARSET=utf8mb4;
USE shopdb;
CREATE TABLE users(id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(100), gold INT);
INSERT INTO users(name,gold) VALUES ('Nguyễn Văn A',100),('Trần Thị B',200);
SQL
```

## B3. Khai báo nguồn + đổ data

```bash
./panel new
```
Nhập:
| Hỏi | Nhập |
|---|---|
| Tên server | `s1` |
| host | `host.docker.internal` |
| port | `3355` |
| user | `cdc` |
| password | `cdc123` |
| database nguồn | `shopdb` |
| database đích | (Enter) |
| Chọn bảng | `all` |

Rồi:
```bash
./panel etl s1        # tự tạo bảng + đổ data cũ + bật realtime
./panel status        # phải thấy KHỚP
```

## B4. Kiểm chứng realtime

```bash
# sửa nguồn
docker exec lab-mysql55 mysql -uroot -proot -e "INSERT INTO shopdb.users(name,gold) VALUES ('Phạm Thị C',999);"
sleep 6
# xem đích
docker exec lab-mysql80 mysql -uroot -proot -e "SELECT * FROM shopdb_s1.users;"
```
Thấy "Phạm Thị C" ở đích (không vỡ tiếng Việt) = **thành công**.

## B5. Thêm nguồn thứ 2 (test nhiều nguồn)

Y hệt B2+B3 nhưng đổi tên `s2` và database khác. panel tự nạp lại canal, 2 nguồn chạy song song.

---

# PHẦN 2 — CHẠY THẬT TRÊN VPS SINGAPORE

Nguồn = DB game thật ở máy local/VN, đưa ra ngoài bằng **ngrok**.

```
MÁY LOCAL (có DB game)          NGROK              VPS SINGAPORE
  MySQL :<cổng>      ──►  0.tcp.ap.ngrok.io:XXXXX  ──►  canal + MySQL 8.0 (bản sao)
```

## B1. Máy local — chạy ngrok đúng cổng MySQL nguồn

```bash
ngrok tcp 3355        # thay 3355 = cổng MySQL nguồn thật của Sếp
```
Ghi lại dòng `Forwarding` → vd `0.tcp.ap.ngrok.io:16174`. **Giữ cửa sổ này mở.**

> ⚠️ Ngrok free đổi địa chỉ mỗi lần khởi động lại. Đổi địa chỉ thì phải khai báo lại nguồn.

## B2. Máy local — tạo user cdc trên MySQL nguồn

MySQL 5.5:
```bash
docker exec <mysql-nguồn> mysql -uroot -p<pass> -e "GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'cdc'@'%' IDENTIFIED BY 'cdc123'; FLUSH PRIVILEGES;"
```
> Nếu MySQL nguồn là 5.7/8.0 thì dùng: `CREATE USER 'cdc'@'%' IDENTIFIED BY 'cdc123'; GRANT ...`

Yêu cầu nguồn: đã bật binlog (`log_bin=ON`, `binlog_format=ROW`).

## B3. VPS — lấy code + khởi động

```bash
git clone <repo-url> canal-cdc-panel && cd canal-cdc-panel
./panel init       # tự cài Docker nếu thiếu + dựng conf
./panel up         # bật MySQL đích + canal-server + canal-adapter
```
> KHÔNG sửa gì trong file `panel`. Chạy y hệt local.

## B4. VPS — khai báo nguồn (dùng địa chỉ ngrok)

```bash
./panel new
```
| Hỏi | Nhập |
|---|---|
| Tên server | `s1` |
| host | `0.tcp.ap.ngrok.io` (host ngrok B1) |
| port | `16174` (port ngrok B1) |
| user | `cdc` |
| password | `cdc123` |
| database nguồn | tên DB game (vd `tlbbdb`) |
| database đích | (Enter → `tlbbdb_s1`) |
| Chọn bảng | `all` hoặc `1,2,5` |

## B5. VPS — tạo bảng + đổ data + bật realtime

```bash
./panel etl s1
./panel status
```
`etl` tự copy khung bảng từ nguồn sang đích rồi đổ data cũ. Realtime bật ngay sau đó.

---

## Lệnh panel đầy đủ

| Lệnh | Việc |
|---|---|
| `./panel init` | check docker + dựng cấu trúc conf |
| `./panel up` | bật MySQL đích + canal-server + canal-adapter |
| `./panel new` | thêm 1 nguồn (tự nạp lại canal) |
| `./panel etl <tên>` | tạo khung bảng đích + đổ data cũ + bật realtime |
| `./panel status` | kiểm tra nguồn ↔ đích khớp số dòng |
| `./panel list` | liệt kê nguồn đã cấu hình |
| `./panel logs [tên]` | xem log canal |
| `./panel rm <tên>` | xóa 1 nguồn (chạy `up` sau đó để áp dụng) |
| `./panel down` | tắt toàn bộ |

---

## Lưu ý & xử lý sự cố (từ test thực tế)

**1. Log có dòng `Received EOF packet ... duplicate slaveId` lặp lại — BÌNH THƯỜNG.**
Đây là đặc tính MySQL 5.5 (bản cũ): khi DB vắng khách >30 giây, nó tự ngắt kết nối,
canal nối lại sau vài giây. **KHÔNG mất data** — đã test insert lúc vắng, data vẫn tới đủ,
chỉ trễ vài giây. Game thật đông người → gần như không gặp. Bỏ qua dòng log này.

**2. `panel new` dừng ngay sau "database nguồn"** = không kết nối được nguồn.
panel sẽ in lỗi thật + gợi ý. Thường do: địa chỉ ngrok đã đổi, hoặc user `cdc` chưa tạo,
hoặc sai mật khẩu. Sửa xong chạy lại `./panel new`.

**3. `mysqldump ... Access denied ... LOCK TABLES`** — đã xử lý sẵn trong panel
(dùng `--single-transaction`, không cần quyền LOCK). Nếu tự chạy dump tay thì nhớ thêm cờ này.

**4. Tiếng Việt bị vỡ ở đích** — kiểm tra charset. panel tự dò utf8mb4/latin1 theo từng DB nguồn.
Nếu nguồn trộn charset ở mức cột (hiếm), báo lại để xử lý riêng.

**5. Thêm/xóa nguồn xong nhớ để panel nạp lại canal.** `new` tự làm; `rm` thì chạy `./panel up` sau.

**6. ETL in ra rỗng (`orders ->` không có `succeeded`) + status báo đích=0.**
Nghĩa là canal-adapter KHÔNG khởi động được. Nguyên nhân hay gặp: có 1 nguồn cũ (vd `s1`)
đang trỏ vào **địa chỉ ngrok đã chết** (ngrok free đổi địa chỉ mỗi lần khởi động lại).
Adapter boot phải kết nối MỌI nguồn → 1 nguồn hỏng làm sập cả adapter → nguồn tốt cũng chết.
Cách sửa: xóa nguồn cũ hỏng rồi tạo lại với địa chỉ ngrok mới:
```bash
./panel rm <tên-nguồn-cũ>
./panel up
./panel list          # xác nhận đã sạch
./panel new           # tạo lại với địa chỉ ngrok hiện tại
```

**7. Nhập "database đích" — chỉ bấm Enter.** Để panel tự đặt `<db>_<tên>` (vd `shopdb_s1`).
Đừng gõ đè tên trùng với nguồn khác, kẻo 2 nguồn ghi đè lên cùng 1 database đích.

**8. 1 nguồn chết KHÔNG làm sập nguồn khác (van chặn).** Khi `panel up`, panel ping thử từng nguồn:
nguồn nào không kết nối được sẽ **tạm bỏ qua** (in cảnh báo màu đỏ), các nguồn còn sống vẫn chạy bình thường.
Khi nguồn chết sống lại (vd sửa địa chỉ ngrok), chạy lại `./panel up` — panel tự nạp lại nó.
→ Vì vậy nên chạy `./panel up` lại mỗi khi địa chỉ ngrok đổi, hoặc sau khi 1 nguồn gặp sự cố.
