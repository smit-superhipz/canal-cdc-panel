-- Đích MySQL 8.0 (giả bản sao Singapore). Tạo bảng RỖNG khớp cấu trúc nguồn.
-- Giữ charset latin1 cho khớp nguồn 5.5 (tránh vỡ tiếng Việt/Hán).

CREATE TABLE IF NOT EXISTS t_char (
  aid       INT PRIMARY KEY,
  accname   VARCHAR(64),
  charname  VARCHAR(64),
  level     INT DEFAULT 1,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS account (
  id        INT PRIMARY KEY,
  name      VARCHAR(64),
  point     INT DEFAULT 0,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- Thêm index tùy ý ở ĐÂY (bản sao của mình, không đụng game) — ví dụ:
-- CREATE INDEX idx_char_accname ON t_char(accname);
