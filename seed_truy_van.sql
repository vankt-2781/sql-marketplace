-- ============================================================
-- seed_truy_van.sql
-- Học liệu kèm topic "Truy vấn dữ liệu" — Học phần SQL
-- Chương trình đào tạo tech stack Node.js (mini-project: hệ thống mua bán đồ cũ)
--
-- Nội dung: tạo schema 5 bảng + dữ liệu mẫu
--   200 người dùng, 8 danh mục, 1.000 tin đăng, 600 đơn, 300 đánh giá
--
-- Cách chạy:  psql -U <user> -d <database> -f seed_truy_van.sql
-- Script an toàn khi chạy lại (xóa và tạo lại toàn bộ bảng).
-- Yêu cầu: PostgreSQL 14+
-- ============================================================

BEGIN;

DROP TABLE IF EXISTS reviews  CASCADE;
DROP TABLE IF EXISTS orders   CASCADE;
DROP TABLE IF EXISTS posts    CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS users    CASCADE;

-- ------------------------------------------------------------
-- 1. Schema (theo topic "Mô hình dữ liệu quan hệ")
-- ------------------------------------------------------------

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
  price       BIGINT NOT NULL CHECK (price > 0),          -- quy tắc 5
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

-- Quy tắc 3: mỗi tin tối đa một đơn đang hoạt động (partial unique index)
CREATE UNIQUE INDEX one_active_order_per_post
ON orders (post_id)
WHERE status IN ('pending', 'confirmed');

CREATE TABLE reviews (
  id          BIGSERIAL PRIMARY KEY,
  order_id    BIGINT NOT NULL UNIQUE REFERENCES orders(id),  -- quy tắc 6
  reviewer_id BIGINT NOT NULL REFERENCES users(id),
  reviewee_id BIGINT NOT NULL REFERENCES users(id),
  stars       INT NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- 2. Dữ liệu mẫu (sinh ngẫu nhiên có seed cố định — kết quả
--    giống nhau giữa các lần chạy trong cùng phiên bản PostgreSQL)
-- ------------------------------------------------------------

SELECT setseed(0.42);

-- 2.1. 200 người dùng
INSERT INTO users (name, email, password_hash, created_at)
SELECT
  'Người dùng ' || i,
  'user' || i || '@example.com',
  md5('password' || i),
  now() - (random() * 540 || ' days')::interval
FROM generate_series(1, 200) AS i;

-- 2.2. 8 danh mục
INSERT INTO categories (name, slug) VALUES
  ('Xe cộ',         'xe-co'),
  ('Đồ điện tử',    'do-dien-tu'),
  ('Nội thất',      'noi-that'),
  ('Sách',          'sach'),
  ('Quần áo',       'quan-ao'),
  ('Đồ gia dụng',   'do-gia-dung'),
  ('Thể thao',      'the-thao'),
  ('Khác',          'khac');

-- 2.3. 1.000 tin đăng
--   Trạng thái gán theo dải id để nhất quán với đơn hàng sinh ở bước sau:
--     id 001–100: reserved  (sẽ có đơn pending/confirmed)
--     id 101–450: sold      (sẽ có đơn completed)
--     id 451–1000: available
--   ~15% tin không có mô tả (phục vụ bài tập IS NULL)
INSERT INTO posts (title, description, price, status, seller_id, category_id, created_at)
SELECT
  (ARRAY[
    'Xe đạp cũ', 'iPhone 12 cũ', 'Bàn học gỗ', 'Loa bluetooth',
    'Tủ quần áo', 'Sách lập trình', 'Áo khoác da', 'Máy xay sinh tố',
    'Giày chạy bộ', 'Bàn phím cơ'
  ])[1 + floor(random() * 10)::int] || ' #' || i,
  CASE WHEN random() < 0.15 THEN NULL
       ELSE 'Đồ dùng còn tốt, mô tả chi tiết cho tin số ' || i || '.'
  END,
  (5 + floor(random() * 1995)::bigint) * 10000,          -- 50.000 – 20.000.000 VND
  CASE
    WHEN i <= 100 THEN 'reserved'
    WHEN i <= 450 THEN 'sold'
    ELSE 'available'
  END,
  1 + floor(random() * 200)::bigint,
  1 + floor(random() * 8)::bigint,
  now() - (30 + random() * 335 || ' days')::interval      -- rải trong ~12 tháng
FROM generate_series(1, 1000) AS i;

-- 2.4. 600 đơn hàng
--   Người mua luôn khác người bán (quy tắc 1): buyer = dịch vòng từ seller.
--   amount chốt theo giá tin tại thời điểm đặt (bằng price hiện tại của tin).

-- (a) 60 đơn pending — mỗi đơn một tin riêng (id 1–60)
INSERT INTO orders (post_id, buyer_id, amount, status, created_at, updated_at)
SELECT
  p.id,
  ((p.seller_id - 1 + 1 + floor(random() * 199)::bigint) % 200) + 1,
  p.price,
  'pending',
  p.created_at + (random() * 20 + 1 || ' days')::interval,
  p.created_at + (random() * 20 + 1 || ' days')::interval
FROM posts p
WHERE p.id BETWEEN 1 AND 60;

-- (b) 40 đơn confirmed — mỗi đơn một tin riêng (id 61–100)
INSERT INTO orders (post_id, buyer_id, amount, status, created_at, updated_at)
SELECT
  p.id,
  ((p.seller_id - 1 + 1 + floor(random() * 199)::bigint) % 200) + 1,
  p.price,
  'confirmed',
  p.created_at + (random() * 20 + 1 || ' days')::interval,
  p.created_at + (random() * 25 + 2 || ' days')::interval
FROM posts p
WHERE p.id BETWEEN 61 AND 100;

-- (c) 350 đơn completed — mỗi đơn một tin riêng (id 101–450, tin đã sold)
INSERT INTO orders (post_id, buyer_id, amount, status, created_at, updated_at)
SELECT
  p.id,
  ((p.seller_id - 1 + 1 + floor(random() * 199)::bigint) % 200) + 1,
  p.price,
  'completed',
  p.created_at + (random() * 20 + 1 || ' days')::interval,
  p.created_at + (random() * 30 + 5 || ' days')::interval
FROM posts p
WHERE p.id BETWEEN 101 AND 450;

-- (d) 150 đơn cancelled — tin ngẫu nhiên trong dải 101–1000
--     (lịch sử đơn bị hủy; không vi phạm chỉ mục one_active_order_per_post)
INSERT INTO orders (post_id, buyer_id, amount, status, created_at, updated_at)
SELECT
  p.id,
  ((p.seller_id - 1 + 1 + floor(random() * 199)::bigint) % 200) + 1,
  p.price,
  'cancelled',
  p.created_at + (random() * 10 || ' days')::interval,
  p.created_at + (random() * 15 + 1 || ' days')::interval
FROM (
  SELECT * FROM posts WHERE id BETWEEN 101 AND 1000 ORDER BY random() LIMIT 150
) p;

-- 2.5. 300 đánh giá — chỉ trên đơn completed, mỗi đơn tối đa 1 (quy tắc 6)
--      Người viết = người mua; người được đánh giá = người bán của tin.
INSERT INTO reviews (order_id, reviewer_id, reviewee_id, stars, comment, created_at)
SELECT
  o.id,
  o.buyer_id,
  p.seller_id,
  (ARRAY[5,5,5,5,4,4,4,3,3,2])[1 + floor(random() * 10)::int],
  (ARRAY[
    'Giao dịch nhanh gọn, hàng đúng mô tả.',
    'Người bán thân thiện, đồ dùng tốt.',
    'Hàng ổn so với giá.',
    'Đóng gói cẩn thận, sẽ ủng hộ tiếp.',
    'Sản phẩm hơi cũ hơn mô tả một chút.'
  ])[1 + floor(random() * 5)::int],
  o.updated_at + (random() * 7 + 1 || ' days')::interval
FROM orders o
JOIN posts p ON p.id = o.post_id
WHERE o.status = 'completed'
ORDER BY o.id
LIMIT 300;

-- 2.6. Đồng bộ users.rating (giá trị dẫn xuất — denormalization từ reviews)
UPDATE users u
SET rating = sub.avg_stars
FROM (
  SELECT reviewee_id, ROUND(AVG(stars)::numeric, 1) AS avg_stars
  FROM reviews
  GROUP BY reviewee_id
) sub
WHERE u.id = sub.reviewee_id;

COMMIT;

-- ------------------------------------------------------------
-- 3. Kiểm tra nhanh sau khi nạp
-- ------------------------------------------------------------
SELECT 'users'      AS bang, COUNT(*) FROM users
UNION ALL SELECT 'categories', COUNT(*) FROM categories
UNION ALL SELECT 'posts',      COUNT(*) FROM posts
UNION ALL SELECT 'orders',     COUNT(*) FROM orders
UNION ALL SELECT 'reviews',    COUNT(*) FROM reviews;

SELECT status, COUNT(*) FROM posts  GROUP BY status ORDER BY status;
SELECT status, COUNT(*) FROM orders GROUP BY status ORDER BY status;
