-- Nguồn MySQL 5.5 (giả DB game). Tạo bảng giả + user cho Canal.
-- Chạy tự động khi container mysql55 khởi tạo lần đầu.

-- Bảng nhân vật giả (giống t_char)
CREATE TABLE IF NOT EXISTS t_char (
  aid       INT PRIMARY KEY AUTO_INCREMENT,
  accname   VARCHAR(64),
  charname  VARCHAR(64),
  level     INT DEFAULT 1,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS account (
  id        INT PRIMARY KEY AUTO_INCREMENT,
  name      VARCHAR(64),
  point     INT DEFAULT 0,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- Dữ liệu mẫu để test bootstrap (initial load)
INSERT INTO account (name, point) VALUES ('user_a', 100), ('user_b', 200);
INSERT INTO t_char (accname, charname, level) VALUES
  ('user_a', 'DaiHiep', 50),
  ('user_b', 'TieuLong', 30);

-- User cho Canal: đọc binlog (giống một replication slave). KHÔNG cần tạo trigger.
CREATE USER 'cdc'@'%' IDENTIFIED BY 'cdc';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'cdc'@'%';

FLUSH PRIVILEGES;
