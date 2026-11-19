-- =====================================================================
-- Mô hình dữ liệu quan hệ — Bài 1 đến Bài 4 (làm nối tiếp trên cùng một database)
-- Chạy trên database trống:
--   docker exec -i pg-marketplace psql -U postgres -d postgres < bai1/bai1.sql
-- Bài 2 tham chiếu users, posts của Bài 1; Bài 3 tham chiếu orders của Bài 2;
-- Bài 4 chèn thêm dữ liệu vào posts.
-- Các lỗi báo ở phần "Yêu cầu kiểm chứng" là lỗi MONG ĐỢI
-- (ràng buộc từ chối dữ liệu sai), không phải lỗi của script.
-- =====================================================================

-- #####################################################################
-- BÀI 1 — Ba bảng cốt lõi và ràng buộc
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Tạo 3 bảng users, categories, posts
--     - Khóa chính tự tăng (SERIAL)
--     - email, slug khai báo UNIQUE
--     - Khóa ngoại từ posts tới users (seller_id) và categories (category_id)
--     - price > 0 (QT5); status chỉ nhận available / reserved / sold,
--       mặc định available; created_at mặc định now()
-- ---------------------------------------------------------------------

-- 1. Bảng users
-- (ràng buộc rating 0-5 được thêm ở mục (c) bằng ALTER TABLE)
CREATE TABLE users (
    id     SERIAL PRIMARY KEY,
    name   VARCHAR(100) NOT NULL,
    email  VARCHAR(255) NOT NULL,
    rating NUMERIC(2,1) DEFAULT 0,
    CONSTRAINT users_email_unique UNIQUE (email)
);

-- 2. Bảng categories
CREATE TABLE categories (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(100) NOT NULL,
    CONSTRAINT categories_slug_unique UNIQUE (slug)
);

-- 3. Bảng posts
-- (cột description được thêm ở mục (c); tiêu đề không được để trống, QT5)
CREATE TABLE posts (
    id          SERIAL PRIMARY KEY,
    title       VARCHAR(255) NOT NULL,
    price       BIGINT       NOT NULL,
    status      VARCHAR(20)  NOT NULL DEFAULT 'available',
    seller_id   INT          NOT NULL,
    category_id INT          NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT posts_title_not_blank CHECK (length(trim(title)) > 0),
    CONSTRAINT posts_price_positive  CHECK (price > 0),
    CONSTRAINT posts_status_valid    CHECK (status IN ('available', 'reserved', 'sold')),
    CONSTRAINT posts_seller_fk       FOREIGN KEY (seller_id)   REFERENCES users(id),
    CONSTRAINT posts_category_fk     FOREIGN KEY (category_id) REFERENCES categories(id)
);

-- ---------------------------------------------------------------------
-- (b) INSERT 2 người dùng, 8 danh mục, 3 tin đăng
-- ---------------------------------------------------------------------

-- 1. INSERT 2 người dùng
INSERT INTO users (name, email, rating) VALUES
('Nguyen Van A', 'vana@example.com', 4.8),
('Tran Thi B',   'thib@example.com', 5.0);

-- 2. INSERT 8 danh mục
INSERT INTO categories (name, slug) VALUES
('Điện thoại',            'dien-thoai'),
('Laptop',                'laptop'),
('Đồ gia dụng',           'do-gia-dung'),
('Nội thất',              'noi-that'),
('Thời trang',            'thoi-trang'),
('Xe cộ',                 'xe-co'),
('Sách & Văn phòng phẩm', 'sach-van-phong-pham'),
('Đồ thể thao',           'do-the-thao');

-- 3. INSERT 3 tin đăng
INSERT INTO posts (title, price, status, seller_id, category_id) VALUES
('iPhone 13 Pro Max 128GB cũ', 12500000, 'available', 1, 1),
('MacBook Air M1 8GB/256GB',   14000000, 'reserved',  1, 2),
('Bàn làm việc gỗ sồi 1m2',      850000, 'available', 2, 4);

-- ---------------------------------------------------------------------
-- (c) Bằng ALTER TABLE, bổ sung:
--     - cột description TEXT cho posts
--     - ràng buộc rating trong khoảng 0-5 cho users
-- ---------------------------------------------------------------------
ALTER TABLE posts
ADD COLUMN description TEXT;

ALTER TABLE users
ADD CONSTRAINT users_rating_range CHECK (rating >= 0 AND rating <= 5);

-- ---------------------------------------------------------------------
-- Yêu cầu kiểm chứng (Bài 1)
-- 4 lệnh INSERT sai dưới đây đều PHẢI bị từ chối, thông báo lỗi nêu đúng
-- tên ràng buộc bị vi phạm.
-- ---------------------------------------------------------------------

-- 1. Lỗi trùng email -> vi phạm "users_email_unique"
INSERT INTO users (name, email) VALUES ('Khong Thi Van', 'vana@example.com');

-- 2. Lỗi giá âm (price = -5000) -> vi phạm "posts_price_positive"
INSERT INTO posts (title, price, seller_id, category_id) VALUES ('Tai nghe lỗi', -5000, 1, 1);

-- 3. Lỗi khóa ngoại không tồn tại (seller_id = 999) -> vi phạm "posts_seller_fk"
INSERT INTO posts (title, price, seller_id, category_id) VALUES ('Chuột không dây', 200000, 999, 2);

-- 4. Lỗi rating ngoài khoảng 0-5 (rating = 7) -> vi phạm "users_rating_range"
INSERT INTO users (name, email, rating) VALUES ('Pham Van D', 'vand@example.com', 7);

-- #####################################################################
-- BÀI 2 — Sửa thiết kế vi phạm chuẩn hóa
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Hai vấn đề của bảng orders_flat, kèm hậu quả cụ thể
-- ---------------------------------------------------------------------
-- Vấn đề 1: cột image_urls chứa NHIỀU giá trị trong một ô ('a.jpg, b.jpg, c.jpg')
--           -> vi phạm dạng chuẩn 1 (1NF: mỗi ô chỉ một giá trị nguyên tử).
--   Hậu quả: - Không đếm được số ảnh của tin bằng SQL thường; muốn xóa/sửa
--              một ảnh phải cắt chuỗi thủ công, dễ hỏng dữ liệu.
--            - Không đặt được ràng buộc cho từng URL, không bắt được URL trùng
--              hoặc rỗng; không tìm theo một ảnh cụ thể bằng chỉ mục.
--
-- Vấn đề 2: seller_name, seller_email (và post_title) lặp lại ở mọi dòng của
--           cùng một người bán/tin đăng -> thông tin người bán phụ thuộc vào
--           người bán chứ không phụ thuộc vào đơn hàng (phụ thuộc bắc cầu,
--           vi phạm 3NF) -> dư thừa dữ liệu.
--   Hậu quả: - Dị thường cập nhật: người bán đổi email thì phải UPDATE mọi dòng
--              của họ; sửa sót một dòng là cùng một người có 2 email khác nhau.
--            - Tốn dung lượng và không có chỗ lưu người bán chưa có đơn nào.

-- Dựng lại bảng chưa chuẩn hóa để có dữ liệu thật mà chuyển đổi
CREATE TABLE orders_flat (
    id           BIGSERIAL PRIMARY KEY,
    post_title   VARCHAR(200),
    seller_name  VARCHAR(100),
    seller_email VARCHAR(255),
    image_urls   TEXT,           -- 'a.jpg, b.jpg, c.jpg'
    status       VARCHAR(20)
);

INSERT INTO orders_flat (post_title, seller_name, seller_email, image_urls, status) VALUES
('iPhone 13 Pro Max 128GB cũ', 'Nguyen Van A', 'vana@example.com', 'a.jpg, b.jpg, c.jpg', 'pending'),
('iPhone 13 Pro Max 128GB cũ', 'Nguyen Van A', 'vana@example.com', 'a.jpg, b.jpg, c.jpg', 'cancelled'),
('Bàn làm việc gỗ sồi 1m2',    'Tran Thi B',   'thib@example.com', 'ban1.jpg',            'pending');

-- ---------------------------------------------------------------------
-- (b) DDL thay thế: orders và post_images
--     (người bán đã nằm ở users, tin đăng ở posts từ Bài 1)
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    id         SERIAL PRIMARY KEY,
    post_id    INT         NOT NULL,
    buyer_id   INT         NOT NULL,
    amount     BIGINT      NOT NULL,
    status     VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT orders_post_fk         FOREIGN KEY (post_id)  REFERENCES posts(id),
    CONSTRAINT orders_buyer_fk        FOREIGN KEY (buyer_id) REFERENCES users(id),
    CONSTRAINT orders_amount_positive CHECK (amount > 0),
    CONSTRAINT orders_status_valid    CHECK (status IN ('pending', 'confirmed', 'completed', 'cancelled'))
);

CREATE TABLE post_images (
    id         SERIAL PRIMARY KEY,
    post_id    INT          NOT NULL,
    url        VARCHAR(500) NOT NULL,
    sort_order INT          NOT NULL DEFAULT 1,
    CONSTRAINT post_images_post_fk       FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
    CONSTRAINT post_images_url_not_blank CHECK (length(trim(url)) > 0),
    CONSTRAINT post_images_unique_order  UNIQUE (post_id, sort_order)
);

-- ---------------------------------------------------------------------
-- (c) Đưa HÀNG ĐẦU TIÊN của orders_flat sang thiết kế mới
-- ---------------------------------------------------------------------
-- Hàng đầu tiên: id nhỏ nhất của orders_flat.
-- Người bán đã có ở users (khớp theo email), tin đăng đã có ở posts (khớp theo
-- tiêu đề + người bán) nên không cần INSERT lại.

-- 1) Tách chuỗi image_urls thành mỗi ảnh một hàng trong post_images
INSERT INTO post_images (post_id, url, sort_order)
SELECT p.id, u.url, u.ord
FROM orders_flat f
JOIN users s ON s.email = f.seller_email
JOIN posts p ON p.title = f.post_title AND p.seller_id = s.id
CROSS JOIN LATERAL regexp_split_to_table(f.image_urls, '\s*,\s*') WITH ORDINALITY AS u(url, ord)
WHERE f.id = (SELECT min(id) FROM orders_flat);

-- 2) Tạo đơn hàng trong orders. orders_flat không có người mua và số tiền nên
--    lấy người mua là Tran Thi B (thib@example.com), amount = giá của tin.
INSERT INTO orders (post_id, buyer_id, amount, status)
SELECT p.id,
       (SELECT id FROM users WHERE email = 'thib@example.com'),
       p.price,
       f.status
FROM orders_flat f
JOIN users s ON s.email = f.seller_email
JOIN posts p ON p.title = f.post_title AND p.seller_id = s.id
WHERE f.id = (SELECT min(id) FROM orders_flat);

-- ---------------------------------------------------------------------
-- Yêu cầu kiểm chứng (Bài 2)
-- ---------------------------------------------------------------------

-- 1) Ba URL ảnh của hàng đó nằm trên ba hàng riêng của post_images
SELECT id, post_id, url, sort_order FROM post_images ORDER BY post_id, sort_order;

-- 2) Đổi email người bán chỉ cần 1 lệnh UPDATE trên 1 hàng (kết quả: UPDATE 1).
--    Dùng giao dịch + ROLLBACK để không làm thay đổi dữ liệu.
BEGIN;

UPDATE users SET email = 'vana.moi@example.com' WHERE id = 1;

-- Mọi tin của người bán này tự thấy email mới, không phải sửa thêm hàng nào
SELECT p.id AS post_id, p.title, u.email AS seller_email
FROM posts p JOIN users u ON u.id = p.seller_id
WHERE u.id = 1;

ROLLBACK;

-- #####################################################################
-- BÀI 3 — Ràng buộc có điều kiện
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Bảng reviews: stars trong khoảng 1-5, mỗi đơn chỉ một đánh giá (QT6)
-- ---------------------------------------------------------------------
CREATE TABLE reviews (
    id          SERIAL PRIMARY KEY,
    order_id    INT         NOT NULL,
    reviewer_id INT         NOT NULL,
    reviewee_id INT         NOT NULL,
    stars       INT         NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT reviews_order_fk      FOREIGN KEY (order_id)    REFERENCES orders(id),
    CONSTRAINT reviews_reviewer_fk   FOREIGN KEY (reviewer_id) REFERENCES users(id),
    CONSTRAINT reviews_reviewee_fk   FOREIGN KEY (reviewee_id) REFERENCES users(id),
    CONSTRAINT reviews_stars_range   CHECK (stars BETWEEN 1 AND 5),
    CONSTRAINT reviews_not_self      CHECK (reviewer_id <> reviewee_id),
    CONSTRAINT reviews_order_unique  UNIQUE (order_id)   -- mỗi đơn chỉ một đánh giá
);

-- ---------------------------------------------------------------------
-- (b) Chỉ mục cho QT3: mỗi tin đăng chỉ có tối đa một đơn chưa kết thúc
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX one_active_order_per_post
    ON orders (post_id)
    WHERE status IN ('pending', 'confirmed');

-- ---------------------------------------------------------------------
-- Yêu cầu kiểm chứng (Bài 3)
-- ---------------------------------------------------------------------

-- Chuẩn bị: một đơn đã hoàn tất để đánh giá (tin 3 của Tran Thi B, người mua là Nguyen Van A)
INSERT INTO orders (post_id, buyer_id, amount, status) VALUES (3, 1, 850000, 'completed');

-- 1) Đánh giá đầu tiên cho đơn đó: thành công
INSERT INTO reviews (order_id, reviewer_id, reviewee_id, stars)
VALUES ((SELECT max(id) FROM orders), 1, 2, 5);

-- 2) Đánh giá thứ hai cho cùng một đơn -> bị từ chối: "reviews_order_unique"
INSERT INTO reviews (order_id, reviewer_id, reviewee_id, stars)
VALUES ((SELECT max(id) FROM orders), 2, 1, 4);

-- 3) Số sao ngoài khoảng 1-5 -> bị từ chối: "reviews_stars_range"
INSERT INTO reviews (order_id, reviewer_id, reviewee_id, stars)
VALUES (1, 1, 2, 6);

-- 4) Đơn pending thứ hai cho cùng một tin (tin 1 đang có đơn 1 ở trạng thái pending)
--    -> bị từ chối: "one_active_order_per_post"
INSERT INTO orders (post_id, buyer_id, amount, status) VALUES (1, 2, 12500000, 'pending');

-- 5) Chuyển đơn cũ sang cancelled ...
UPDATE orders SET status = 'cancelled' WHERE id = 1;

-- 6) ... thì tạo được đơn mới cho tin đó
INSERT INTO orders (post_id, buyer_id, amount, status) VALUES (1, 2, 12500000, 'pending');

-- Kết quả cuối: tin 1 chỉ còn một đơn đang hoạt động
SELECT id, post_id, buyer_id, amount, status FROM orders ORDER BY id;

-- #####################################################################
-- BÀI 4 — Chỉ mục và cách đo
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Chèn 30.000 tin đăng bằng generate_series, phân bổ trên các danh mục
--     hiện có (id 1-8), rồi ANALYZE posts để planner có thống kê.
--     Phân bổ lệch có chủ đích (danh mục 8 chỉ ~1% số tin) để có một truy vấn
--     "chọn ít hàng", là trường hợp chỉ mục phát huy tác dụng.
-- ---------------------------------------------------------------------
INSERT INTO posts (title, price, status, seller_id, category_id)
SELECT
    'Tin đăng số ' || g,
    (50000 + (g % 500) * 10000),                 -- giá luôn > 0 (QT5)
    'available',
    1 + (g % 2),                                 -- người bán: user 1 hoặc 2
    CASE
        WHEN g % 100 < 40 THEN 1                 -- ~40%
        WHEN g % 100 < 65 THEN 2                 -- ~25%
        WHEN g % 100 < 80 THEN 3                 -- ~15%
        WHEN g % 100 < 90 THEN 4                 -- ~10%
        WHEN g % 100 < 95 THEN 5                 -- ~5%
        WHEN g % 100 < 98 THEN 6                 -- ~3%
        WHEN g % 100 < 99 THEN 7                 -- ~1%
        ELSE 8                                   -- ~1%
    END
FROM generate_series(1, 30000) AS g;

ANALYZE posts;

-- Kiểm tra phân bổ theo danh mục
SELECT category_id, count(*) AS so_tin
FROM posts
GROUP BY category_id
ORDER BY category_id;

-- ---------------------------------------------------------------------
-- (b) EXPLAIN ANALYZE truy vấn lọc theo category_id, KHI CHƯA CÓ CHỈ MỤC
--     Đường truy cập mong đợi: Seq Scan on posts
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT * FROM posts WHERE category_id = 8;

-- ---------------------------------------------------------------------
-- (c) Tạo chỉ mục cho category_id, ANALYZE rồi đo lại
-- ---------------------------------------------------------------------
CREATE INDEX idx_posts_category_id ON posts (category_id);

ANALYZE posts;

-- Đường truy cập mong đợi: Index Scan hoặc Bitmap Heap Scan, thời gian giảm rõ rệt
EXPLAIN ANALYZE
SELECT * FROM posts WHERE category_id = 8;

-- ---------------------------------------------------------------------
-- Đối chứng: điều kiện lọc chiếm quá nhiều hàng (danh mục 1, 2, 3: ~80% bảng)
-- Dù đã có chỉ mục vẫn là Seq Scan -> đó là lựa chọn ĐÚNG của planner, vì phải
-- đọc phần lớn bảng thì quét tuần tự rẻ hơn đi qua chỉ mục.
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT * FROM posts WHERE category_id IN (1, 2, 3);
