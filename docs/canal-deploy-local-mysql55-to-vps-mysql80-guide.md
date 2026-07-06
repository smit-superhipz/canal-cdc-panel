# Hướng dẫn cài Canal trên VPS Singapore — replicate MySQL 5.5 (local) → MySQL 8.0 (VPS)

Mục tiêu: Canal chạy trên **VPS Singapore**, đọc binlog từ **MySQL 5.5 ở máy local**, ghi vào **MySQL 8.0 trên VPS** (bản sao cho admin panel).

```
MÁY LOCAL (nhà)                         VPS SINGAPORE
┌──────────────────┐   ngrok tcp 3306   ┌─────────────────────────────┐
│ MySQL 5.5 :3306  │◄─ địa chỉ public ──│ canal-server  (đọc binlog)  │
│ (giả game)       │  0.tcp.ngrok:xxxxx │ canal-adapter (ghi đích)    │
│                  │                    │ MySQL 8.0 :3306 (bản sao)   │
│ chạy ngrok       │───────────────────►│ admin panel                 │
└──────────────────┘                    └─────────────────────────────┘
```

> **Vì sao cần ngrok?** Máy local nấp sau router (NAT) — VPS ngoài Internet không gọi thẳng vào MySQL 5.5 được. ngrok cấp cho máy local một **địa chỉ public** (vd `0.tcp.ap.ngrok.io:15432`) mà VPS gõ vào được. Đây là cách **giống game thật nhất**: Canal trỏ tới `<host>:<port>` y như trỏ tới IP game thật — khi chuyển sang game thật chỉ đổi mỗi dòng địa chỉ.
>
> ⚠️ **Bản ngrok free: địa chỉ đổi mỗi lần khởi động lại** → phải sửa lại 2 file Canal (`instance.properties` + `application.yml`) rồi restart. Muốn cố định → ngrok trả phí (static TCP address).
>
> **Phương án 2 (ghi chú cuối bài):** SSH reverse tunnel — địa chỉ cố định, hoàn toàn free, nhưng cần login VPS để mở.

---

## PHẦN A — Máy LOCAL: chuẩn bị MySQL 5.5

### A1. Bật binlog cho MySQL 5.5
Sửa file cấu hình MySQL (`my.cnf` / `my.ini`), trong mục `[mysqld]` thêm:
```ini
[mysqld]
log-bin=mysql-bin
binlog-format=ROW
server-id=1
```
Khởi động lại MySQL. Kiểm tra:
```sql
SHOW VARIABLES LIKE 'log_bin';        -- phải = ON
SHOW VARIABLES LIKE 'binlog_format';  -- phải = ROW
SHOW VARIABLES LIKE 'server_id';      -- phải != 0
```

### A2. Tạo user cho Canal đọc binlog
```sql
CREATE USER 'cdc'@'%' IDENTIFIED BY 'cdc123';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'cdc'@'%';
FLUSH PRIVILEGES;
```
> Nếu MySQL 5.5 chỉ nghe `127.0.0.1`: sửa `bind-address = 0.0.0.0` trong my.cnf — nhưng với SSH tunnel thì KHÔNG cần, vì tunnel nối vào localhost của local.

### A3. Mở địa chỉ public bằng ngrok (chạy TRÊN máy local)
Cài ngrok (macOS): `brew install ngrok` — rồi đăng ký tài khoản free lấy authtoken, chạy 1 lần:
```bash
ngrok config add-authtoken <TOKEN_CUA_BAN>
```
Mở tunnel TCP tới MySQL 5.5:
```bash
ngrok tcp 3306
```
ngrok in ra dòng như:
```
Forwarding   tcp://0.tcp.ap.ngrok.io:15432 -> localhost:3306
```
→ **Ghi lại `0.tcp.ap.ngrok.io` và `15432`** — đây là host + port Canal sẽ trỏ tới (Phần B4/B5). Giữ cửa sổ này chạy.

> ⚠️ Mỗi lần tắt/bật lại ngrok, host+port ĐỔI → phải sửa lại B4 + B5 rồi `docker compose restart`.
> Vì cổng này public, **bắt buộc đặt user/mật khẩu MySQL mạnh** (ai biết địa chỉ cũng thử gõ được).

---

## PHẦN B — VPS SINGAPORE: cài Docker + MySQL 8.0 + Canal

### B1. Cài Docker (nếu chưa có)
```bash
curl -fsSL https://get.docker.com | sh
docker version   # kiểm tra
```

### B2. Tạo thư mục dự án
```bash
mkdir -p ~/canal-replica/canal/adapter-conf/rdb
cd ~/canal-replica
```

### B3. Tạo `docker-compose.yml`
```yaml
services:
  # MySQL 8.0 — bản sao cho admin panel
  mysql80:
    image: mysql:8.0
    container_name: replica-mysql80
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: <MAT_KHAU_MANH>
      MYSQL_DATABASE: gamedb
    command:
      - --character-set-server=latin1        # khớp game 5.5 (tránh vỡ tiếng Việt/Hán)
      - --collation-server=latin1_swedish_ci
    ports:
      - "127.0.0.1:3306:3306"                # chỉ nghe localhost VPS (panel cùng máy)
    volumes:
      - mysql80_data:/var/lib/mysql

  # Canal server — đọc binlog MySQL 5.5 local (qua SSH tunnel cổng 3355)
  canal-server:
    image: canal/canal-server:v1.1.7
    container_name: replica-canal-server
    restart: always
    network_mode: host                        # để chạm localhost:3355 (đầu tunnel) dễ nhất
    volumes:
      - ./canal/instance.properties:/home/admin/canal-server/conf/example/instance.properties

  # Canal adapter — ghi thẳng vào MySQL 8.0
  canal-adapter:
    image: slpcat/canal-adapter:v1.1.5
    container_name: replica-canal-adapter
    restart: always
    network_mode: host
    depends_on:
      - canal-server
      - mysql80
    volumes:
      - ./canal/application.yml:/opt/canal-adapter/conf/application.yml
      - ./canal/adapter-conf/rdb:/opt/canal-adapter/conf/rdb

volumes:
  mysql80_data:
```

> **`network_mode: host`**: cho container dùng chung mạng với VPS → gõ `localhost:3355` (đầu tunnel) và `localhost:3306` (MySQL 8.0) đều chạm được. Đơn giản hơn cầu nối mạng Docker.

### B4. Tạo `canal/instance.properties` (canal-server đọc gì)
```properties
# Đọc MySQL 5.5 local qua địa chỉ ngrok (ĐỔI theo dòng ngrok in ra ở A3)
canal.instance.master.address=0.tcp.ap.ngrok.io:15432
canal.instance.dbUsername=cdc
canal.instance.dbPassword=cdc123
canal.instance.connectionCharset=ISO-8859-1
canal.instance.defaultDatabaseName=gamedb
canal.instance.mysql.slaveId=1234
canal.instance.filter.regex=gamedb\\.t_char,gamedb\\.account
canal.instance.gtidon=false
```
> Đổi `filter.regex` thành đủ các bảng game cần đồng bộ (ngăn cách bằng dấu phẩy).

### B5. Tạo `canal/application.yml` (canal-adapter ghi đâu)
```yaml
server:
  port: 8081
canal.conf:
  mode: tcp
  flatMessage: true
  syncBatchSize: 1000
  retries: -1
  consumerProperties:
    canal.tcp.server.host: 127.0.0.1:11111
    canal.tcp.batch.size: 500
  srcDataSources:
    defaultDS:
      # ĐỔI theo địa chỉ ngrok ở A3 (dùng cho ETL nạp data cũ)
      url: jdbc:mysql://0.tcp.ap.ngrok.io:15432/gamedb?useUnicode=true&characterEncoding=latin1
      username: cdc
      password: cdc123
  canalAdapters:
    - instance: example
      groups:
        - groupId: g1
          outerAdapters:
            - name: rdb
              key: mysql80
              properties:
                jdbc.driverClassName: com.mysql.jdbc.Driver
                jdbc.url: jdbc:mysql://127.0.0.1:3306/gamedb?useUnicode=true&characterEncoding=latin1
                jdbc.username: root
                jdbc.password: <MAT_KHAU_MANH>
```

### B6. Tạo file mapping mỗi bảng — `canal/adapter-conf/rdb/account.yml`
```yaml
dataSourceKey: defaultDS
destination: example
groupId: g1
outerAdapterKey: mysql80
concurrent: true
dbMapping:
  database: gamedb
  table: account
  targetTable: account
  targetPk:
    id: id
  mapAll: true
```
Và `canal/adapter-conf/rdb/t_char.yml` (đổi `account`→`t_char`, `id`→`aid`). **Mỗi bảng game = 1 file.**

---

## PHẦN C — Chạy & kiểm tra

### C1. Tạo bảng rỗng trên MySQL 8.0 (khớp cấu trúc game)
Cách nhanh: dump cấu trúc từ local rồi nạp lên VPS 8.0 (chỉ cấu trúc, chưa cần data):
```bash
# trên LOCAL: xuất cấu trúc (không data)
mysqldump -u root -p --no-data --default-character-set=latin1 gamedb t_char account > schema.sql
# copy schema.sql lên VPS, rồi trên VPS nạp vào 8.0:
docker exec -i replica-mysql80 mysql -uroot -p<MAT_KHAU_MANH> gamedb < schema.sql
```

### C2. Bật Canal
```bash
cd ~/canal-replica
docker compose up -d
docker compose ps                          # đợi mysql80 healthy, canal up
docker logs replica-canal-server 2>&1 | tail   # tìm dòng "binlog dump"
docker logs replica-canal-adapter 2>&1 | grep -i subscribe
```

### C3. Nạp data cũ (ETL — LÀM 1 LẦN, bắt buộc)
```bash
curl -X POST "http://127.0.0.1:8081/etl/rdb/mysql80/account.yml"
curl -X POST "http://127.0.0.1:8081/etl/rdb/mysql80/t_char.yml"
# kết quả mong đợi: {"succeeded":true,"resultMessage":"导入RDB 数据：N 条"}
```

### C4. Test realtime
```bash
# trên LOCAL: sửa data
mysql -u root -p gamedb -e "UPDATE account SET point=12345 WHERE id=1;"
# trên VPS: kiểm tra bản sao (sau vài giây)
docker exec replica-mysql80 mysql -uroot -p<MAT_KHAU_MANH> gamedb -e "SELECT id,point FROM account WHERE id=1;"
```
Nếu đích đổi theo → **thành công**.

---

## PHẦN D — Giữ đường kết nối chạy bền (quan trọng)

Đường kết nối local→VPS chết là ngừng đồng bộ. Giữ nó chạy liên tục.

### Cách chính: ngrok (đang dùng ở A3)
- Giữ cửa sổ `ngrok tcp 3306` chạy. Muốn chạy nền bền: dùng ngrok agent như service, hoặc `nohup ngrok tcp 3306 &`.
- ⚠️ Mỗi lần ngrok khởi động lại, **host+port đổi** → sửa lại B4 + B5 rồi `docker compose restart canal-server canal-adapter`.
- Muốn địa chỉ **cố định** (khỏi sửa mỗi lần) → nâng cấp ngrok trả phí lấy **static TCP address**.

### Phương án 2: SSH reverse tunnel (địa chỉ cố định, hoàn toàn free)
Nếu ngại địa chỉ ngrok đổi liên tục, thay ngrok bằng SSH tunnel — địa chỉ cố định `localhost:3355`:
```bash
# trên LOCAL — cần login được vào VPS
brew install autossh
autossh -M 0 -f -N \
  -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" \
  -R 3355:localhost:3306 root@<IP_VPS_SING>
```
Rồi đổi địa chỉ trong B4/B5 thành `127.0.0.1:3355`, và thêm `network_mode: host` cho canal-server/adapter trong compose (để chạm `localhost:3355` của VPS).
- `-f` chạy nền, `autossh` tự nối lại khi rớt mạng.
- Ưu: địa chỉ cố định, free. Nhược: cần key SSH vào VPS.

---

## Checklist tổng

- [ ] Local: binlog ON + ROW, user `cdc` tạo xong
- [ ] Local: `ngrok tcp 3306` đang chạy, đã ghi lại host:port
- [ ] VPS: đã điền host:port ngrok vào B4 + B5
- [ ] VPS: Docker cài xong
- [ ] VPS: MySQL 8.0 chạy + đã nạp schema bảng
- [ ] VPS: 3 file cấu hình canal + mỗi bảng 1 file mapping
- [ ] VPS: `docker compose up -d`, thấy "binlog dump" + "subscribe succeed"
- [ ] Chạy ETL nạp data cũ 1 lần
- [ ] Test realtime khớp

## Lưu ý bảo mật
- MySQL 8.0 chỉ nghe `127.0.0.1` (panel cùng VPS) — KHÔNG mở ra Internet.
- SSH tunnel đã mã hóa — data local→VPS đi qua đường an toàn.
- Mật khẩu `cdc123` / `<MAT_KHAU_MANH>` chỉ là ví dụ — đổi thành mật khẩu thật, đừng commit lên git.

## Câu hỏi chưa giải quyết
- Bảng game thật nào cần sync (mới có t_char + account mẫu)? → cần kết quả file `plans/check-game-db-for-canal.sql`.
- Bảng nào thiếu khóa chính / dùng BLOB? → xử lý riêng nếu có.
- Có cần canal-admin (UI web) trên VPS không? (tốn thêm ~220MB RAM, UI tiếng Trung).
