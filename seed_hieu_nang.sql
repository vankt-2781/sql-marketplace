-- ============================================================
-- seed_hieu_nang.sql
-- Học liệu kèm topic "Hiệu năng truy vấn" — Học phần SQL
-- Chương trình đào tạo tech stack Node.js (mini-project: hệ thống mua bán đồ cũ)
--
-- Nội dung: schema 5 bảng + dữ liệu LỚN để quan sát rõ chênh lệch
--   quét tuần tự / quét theo chỉ mục trong EXPLAIN và EXPLAIN ANALYZE.
--     2.000 người dùng, 8 danh mục, 200.000 tin đăng, 65.000 đơn
--
--   Script KHÔNG tạo chỉ mục trên posts.seller_id và posts.category_id
--   — để học viên tự đo trước/sau khi CREATE INDEX ở bài tập.
--
-- Cách chạy:  psql -U <user> -d <database> -f seed_hieu_nang.sql
-- An toàn khi chạy lại (drop-recreate). Yêu cầu PostgreSQL 14+.
-- Thời gian nạp: khoảng 3–10 giây tùy máy.
-- ============================================================

BEGIN;

DROP TABLE IF EXISTS reviews    CASCADE;
DROP TABLE IF EXISTS orders     CASCADE;
DROP TABLE IF EXISTS posts      CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS users      CASCADE;

CREATE TABLE users (
  id            BIGSERIAL PRIMARY KEY,
  name          VARCHAR(100) NOT NULL,
  email         VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  rating        NUMERIC(2,1) NOT NULL DEFAULT 0 CHECK (rating BETWEEN 0 AND 5),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE categories (
  id   BIGSERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  slug VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE posts (
  id          BIGSERIAL PRIMARY KEY,
  title       VARCHAR(200) NOT NULL,
  description TEXT,
  price       BIGINT NOT NULL CHECK (price > 0),          -- QT5
  status      VARCHAR(20) NOT NULL DEFAULT 'available'
              CHECK (status IN ('available', 'reserved', 'sold')),
  seller_id   BIGINT NOT NULL REFERENCES users(id),
  category_id BIGINT NOT NULL REFERENCES categories(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE orders (
  id         BIGSERIAL PRIMARY KEY,
  post_id    BIGINT NOT NULL REFERENCES posts(id),
  buyer_id   BIGINT NOT NULL REFERENCES users(id),
  amount     BIGINT NOT NULL CHECK (amount > 0),
  status     VARCHAR(20) NOT NULL DEFAULT 'pending'
             CHECK (status IN ('pending', 'confirmed', 'completed', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- QT3: mỗi tin tối đa một đơn đang hoạt động (partial unique index)
-- Giữ giống schema của seed_truy_van.sql để hai học liệu đồng nhất.
CREATE UNIQUE INDEX one_active_order_per_post
ON orders (post_id)
WHERE status IN ('pending', 'confirmed');

CREATE TABLE reviews (
  id          BIGSERIAL PRIMARY KEY,
  order_id    BIGINT NOT NULL UNIQUE REFERENCES orders(id),  -- QT6
  reviewer_id BIGINT NOT NULL REFERENCES users(id),
  reviewee_id BIGINT NOT NULL REFERENCES users(id),
  stars       INT NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Ghi chú: bảng reviews để trống có chủ đích — topic Hiệu năng không dùng tới,
-- không nạp dữ liệu thừa làm chậm thời gian dựng môi trường.

SELECT setseed(0.42);

-- ------------------------------------------------------------
-- 2.000 người dùng
-- ------------------------------------------------------------
INSERT INTO users (name, email, password_hash, created_at)
SELECT 'Người dùng ' || i, 'user' || i || '@example.com', md5('pw' || i),
       now() - (floor(random()*730)::int || ' days')::interval
FROM generate_series(1, 2000) AS i;

-- ------------------------------------------------------------
-- 8 danh mục
-- ------------------------------------------------------------
INSERT INTO categories (name, slug) VALUES
  ('Xe cộ','xe-co'), ('Đồ điện tử','do-dien-tu'), ('Nội thất','noi-that'),
  ('Sách','sach'), ('Quần áo','quan-ao'), ('Đồ gia dụng','do-gia-dung'),
  ('Thể thao','the-thao'), ('Khác','khac');

-- ------------------------------------------------------------
-- 200.000 tin đăng
--   Trạng thái lấy từ MỘT giá trị ngẫu nhiên r cho mỗi hàng, nên tỷ lệ
--   đúng như khai báo: 70% available, 10% reserved, 20% sold.
--   (Viết CASE với hai lời gọi random() riêng sẽ cho tỷ lệ khác hẳn.)
--   ~15% tin không có mô tả (phục vụ bài tập IS NULL).
-- ------------------------------------------------------------
INSERT INTO posts (title, description, price, status, seller_id, category_id, created_at)
SELECT
  (ARRAY['Xe đạp cũ','iPhone cũ','Bàn học gỗ','Loa bluetooth','Tủ quần áo',
         'Sách lập trình','Áo khoác da','Máy xay','Giày chạy bộ','Bàn phím cơ'
  ])[1 + floor(g.r1*10)::int] || ' #' || g.i,
  CASE WHEN g.r2 < 0.15 THEN NULL ELSE 'Mô tả cho tin số ' || g.i END,
  (5 + floor(g.r3*1995)::bigint) * 10000,
  CASE WHEN g.r4 < 0.70 THEN 'available'
       WHEN g.r4 < 0.80 THEN 'reserved'
       ELSE 'sold' END,
  1 + floor(g.r5*2000)::bigint,
  1 + floor(g.r6*8)::bigint,
  now() - (floor(g.r7*700)::int || ' days')::interval
FROM (
  SELECT i, random() AS r1, random() AS r2, random() AS r3, random() AS r4,
            random() AS r5, random() AS r6, random() AS r7
  FROM generate_series(1, 200000) AS i
) AS g;

-- ------------------------------------------------------------
-- Đơn hàng — SUY TỪ trạng thái tin để dữ liệu nhất quán nghiệp vụ:
--   tin reserved  → 1 đơn pending hoặc confirmed  (QT2/QT3)
--   tin sold      → 1 đơn completed
--   5.000 tin available ngẫu nhiên → 1 đơn cancelled (lịch sử đơn bị hủy)
--   Người mua luôn khác người bán (QT1): dịch vòng từ seller_id.
--   amount chốt theo giá tin tại thời điểm đặt.
-- ------------------------------------------------------------

-- (a) tin reserved → đơn đang hoạt động
INSERT INTO orders (post_id, buyer_id, amount, status, created_at, updated_at)
SELECT
  p.id,
  ((p.seller_id - 1 + 1 + floor(random()*1999)::bigint) % 2000) + 1,
  p.price,
  CASE WHEN random() < 0.60 THEN 'pending' ELSE 'confirmed' END,
  p.created_at + (floor(random()*20)::int || ' days')::interval,
  p.created_at + (floor(random()*25)::int || ' days')::interval
FROM posts p
WHERE p.status = 'reserved';

-- (b) tin sold → đơn completed
INSERT INTO orders (post_id, buyer_id, amount, status, created_at, updated_at)
SELECT
  p.id,
  ((p.seller_id - 1 + 1 + floor(random()*1999)::bigint) % 2000) + 1,
  p.price,
  'completed',
  p.created_at + (floor(random()*20)::int || ' days')::interval,
  p.created_at + (floor(random()*30)::int || ' days')::interval
FROM posts p
WHERE p.status = 'sold';

-- (c) 5.000 tin available → đơn cancelled (không vi phạm QT3)
INSERT INTO orders (post_id, buyer_id, amount, status, created_at, updated_at)
SELECT
  p.id,
  ((p.seller_id - 1 + 1 + floor(random()*1999)::bigint) % 2000) + 1,
  p.price,
  'cancelled',
  p.created_at + (floor(random()*10)::int || ' days')::interval,
  p.created_at + (floor(random()*15)::int || ' days')::interval
FROM (
  SELECT * FROM posts WHERE status = 'available' ORDER BY random() LIMIT 5000
) p;

COMMIT;

-- ------------------------------------------------------------
-- Cập nhật thống kê cho bộ tối ưu.
-- CỐ Ý chỉ chạy ANALYZE, KHÔNG chạy VACUUM: bài tập Nâng cao yêu cầu học
-- viên tự chạy VACUUM để thấy điều kiện có Index Only Scan (visibility map).
-- ------------------------------------------------------------
ANALYZE;

-- ------------------------------------------------------------
-- Kiểm tra nhanh sau khi nạp
-- ------------------------------------------------------------
SELECT 'users' AS bang, COUNT(*) FROM users
UNION ALL SELECT 'posts',   COUNT(*) FROM posts
UNION ALL SELECT 'orders',  COUNT(*) FROM orders;

SELECT status, COUNT(*) FROM posts  GROUP BY status ORDER BY status;
SELECT status, COUNT(*) FROM orders GROUP BY status ORDER BY status;

-- Kiểm tính nhất quán: cả ba truy vấn dưới đây phải trả về 0.
SELECT COUNT(*) AS loi_don_hoat_dong_tren_tin_khong_reserved
FROM orders o JOIN posts p ON p.id = o.post_id
WHERE o.status IN ('pending','confirmed') AND p.status <> 'reserved';

SELECT COUNT(*) AS loi_don_completed_tren_tin_khong_sold
FROM orders o JOIN posts p ON p.id = o.post_id
WHERE o.status = 'completed' AND p.status <> 'sold';

SELECT COUNT(*) AS loi_tin_sold_khong_co_don
FROM posts p
WHERE p.status = 'sold'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.post_id = p.id);

-- Gợi ý: chưa có chỉ mục trên posts.category_id / posts.seller_id.
-- Chạy thử để thấy quét tuần tự:
--   EXPLAIN SELECT * FROM posts WHERE category_id = 3;
