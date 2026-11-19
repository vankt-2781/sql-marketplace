-- =====================================================================
-- Truy vấn dữ liệu — JOIN (Bài 1 đến Bài 4)
-- Yêu cầu: đã nạp seed_truy_van.sql (dùng chung với bai2.sql, không cần nạp lại)
--   docker exec -i pg-marketplace psql -U postgres -d postgres < seed_truy_van.sql
-- Chạy file này:
--   docker exec -i pg-marketplace psql -U postgres -d postgres -a < bai3/bai3.sql
-- =====================================================================

-- #####################################################################
-- BÀI 1 — Màn hình danh sách tin và lịch sử đơn hàng
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Trang danh sách: 20 tin available mới nhất, mỗi hàng gồm tiêu đề, giá,
--     tên danh mục, tên người bán và rating của người bán (posts, categories, users).
-- ---------------------------------------------------------------------
SELECT p.id, p.title, p.price,
       c.name   AS category_name,
       u.name   AS seller_name,
       u.rating AS seller_rating
FROM posts p
JOIN categories c ON c.id = p.category_id
JOIN users u      ON u.id = p.seller_id
WHERE p.status = 'available'
ORDER BY p.created_at DESC, p.id DESC
LIMIT 20;

-- ---------------------------------------------------------------------
-- (b) Bỏ LIMIT và đếm số hàng.  Kiểm chứng: đúng 550 hàng = tổng số tin available.
-- ---------------------------------------------------------------------
SELECT count(*) AS so_hang_sau_join
FROM posts p
JOIN categories c ON c.id = p.category_id
JOIN users u      ON u.id = p.seller_id
WHERE p.status = 'available';

SELECT count(*) AS tong_tin_available     -- đối chiếu: cũng 550
FROM posts
WHERE status = 'available';

-- Vì sao INNER JOIN ở đây không làm mất hàng nào: posts.category_id và posts.seller_id
-- đều NOT NULL và là khóa ngoại tới categories(id) và users(id). Mỗi tin vì thế luôn có
-- đúng một danh mục và đúng một người bán, nên mọi hàng của posts đều tìm được hàng khớp
-- ở hai bảng kia và không bị loại, cũng không bị nhân bản (quan hệ n-1).

-- ---------------------------------------------------------------------
-- (c) Trang lịch sử đơn của một người mua (buyer_id = 100, có 10 đơn trong dữ liệu):
--     mã đơn, trạng thái, số tiền, tiêu đề tin, tên danh mục; đơn mới nhất trước.
-- ---------------------------------------------------------------------
SELECT o.id AS order_id, o.status, o.amount,
       p.title, c.name AS category_name
FROM orders o
JOIN posts p      ON p.id = o.post_id
JOIN categories c ON c.id = p.category_id
WHERE o.buyer_id = 100
ORDER BY o.created_at DESC, o.id DESC;

-- ---------------------------------------------------------------------
-- (d) Đối chiếu 2 hàng đầu của (c) (đơn 71 và 234) với dữ liệu gốc, truy vấn từng bảng theo id
-- ---------------------------------------------------------------------
SELECT id, post_id, buyer_id, amount, status FROM orders     WHERE id IN (71, 234);
SELECT id, title, category_id                FROM posts      WHERE id IN (71, 234);
SELECT id, name                              FROM categories WHERE id = 6;

-- #####################################################################
-- BÀI 2 — LEFT JOIN và vị trí điều kiện lọc
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Toàn bộ tin kèm tổng số đơn của mỗi tin.  Kiểm chứng: 1.000 hàng, tin chưa có
--     đơn nhận giá trị 0.  Dùng COUNT(o.id) (không dùng COUNT(*)) để tin không có đơn ra 0.
-- ---------------------------------------------------------------------
SELECT p.id, p.title, COUNT(o.id) AS order_count
FROM posts p
LEFT JOIN orders o ON o.post_id = p.id
GROUP BY p.id, p.title
ORDER BY p.id;

-- ---------------------------------------------------------------------
-- (b) Thêm cột số đơn completed, đặt điều kiện trạng thái trong ON.
--     Kiểm chứng: vẫn 1.000 hàng, tin chưa có đơn completed nhận 0.
-- ---------------------------------------------------------------------
SELECT p.id, p.title,
       COUNT(o.id) AS completed_order_count
FROM posts p
LEFT JOIN orders o ON o.post_id = p.id AND o.status = 'completed'
GROUP BY p.id, p.title
ORDER BY p.id;

-- ---------------------------------------------------------------------
-- (c) Viết lại bản đặt điều kiện đó trong WHERE.  Kiểm chứng: chỉ còn 350 hàng.
-- ---------------------------------------------------------------------
SELECT p.id, p.title,
       COUNT(o.id) AS completed_order_count
FROM posts p
LEFT JOIN orders o ON o.post_id = p.id
WHERE o.status = 'completed'
GROUP BY p.id, p.title
ORDER BY p.id;

-- So sánh số hàng của hai phiên bản: (b) = 1000, (c) = 350
SELECT
  (SELECT count(*) FROM (SELECT p.id FROM posts p
                         LEFT JOIN orders o ON o.post_id = p.id AND o.status = 'completed'
                         GROUP BY p.id) x) AS phien_ban_ON,
  (SELECT count(*) FROM (SELECT p.id FROM posts p
                         LEFT JOIN orders o ON o.post_id = p.id
                         WHERE o.status = 'completed'
                         GROUP BY p.id) y) AS phien_ban_WHERE;

-- Giải thích cơ chế: LEFT JOIN giữ MỌI hàng bên trái; hàng nào không có hàng khớp ở bên
-- phải thì các cột của orders là NULL.  Điều kiện trong ON chỉ quyết định hàng nào của orders
-- "được ghép", nên tin không có đơn completed vẫn được giữ lại (với o.* là NULL, đếm ra 0).
-- WHERE thì chạy SAU khi join, lọc trên kết quả đã ghép: hàng không khớp có o.status = NULL,
-- mà "NULL = 'completed'" là UNKNOWN nên bị loại.  Kết quả là các hàng "giữ lại" bị loại hết,
-- LEFT JOIN trở thành INNER JOIN, chỉ còn 350 tin có đơn completed.

-- #####################################################################
-- BÀI 3 — JOIN một bảng nhiều lần và anti-join
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Trang đánh giá: 20 đánh giá mới nhất gồm số sao, nhận xét, tên người viết và tên
--     người được đánh giá (users JOIN hai lần, dùng bí danh khác nhau).
-- ---------------------------------------------------------------------
SELECT r.id, r.stars, r.comment,
       w.name AS reviewer_name,
       e.name AS reviewee_name
FROM reviews r
JOIN users w ON w.id = r.reviewer_id
JOIN users e ON e.id = r.reviewee_id
ORDER BY r.created_at DESC, r.id DESC
LIMIT 20;

-- Kiểm chứng: không hàng nào hai cột tên trùng nhau (kỳ vọng 0) — đúng QT1, người mua
-- khác người bán.
SELECT count(*) AS so_hang_trung_ten
FROM reviews r
JOIN users w ON w.id = r.reviewer_id
JOIN users e ON e.id = r.reviewee_id
WHERE w.name = e.name;

-- ---------------------------------------------------------------------
-- (b) Tin available chưa từng có đơn nào — viết bằng cả NOT EXISTS và LEFT JOIN ... IS NULL.
-- ---------------------------------------------------------------------
-- Cách 1: NOT EXISTS
SELECT p.id, p.title
FROM posts p
WHERE p.status = 'available'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.post_id = p.id)
ORDER BY p.id;

-- Cách 2: LEFT JOIN ... IS NULL
SELECT p.id, p.title
FROM posts p
LEFT JOIN orders o ON o.post_id = p.id
WHERE p.status = 'available'
  AND o.id IS NULL
ORDER BY p.id;

-- Kiểm chứng: hai cách cùng trả về 457 hàng với cùng tập id (hai chiều EXCEPT đều 0 hàng)
SELECT
  (SELECT count(*) FROM posts p WHERE p.status = 'available'
     AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.post_id = p.id)) AS not_exists_rows,
  (SELECT count(*) FROM posts p LEFT JOIN orders o ON o.post_id = p.id
     WHERE p.status = 'available' AND o.id IS NULL)                  AS left_join_rows,
  (SELECT count(*) FROM (
      (SELECT p.id FROM posts p WHERE p.status = 'available'
         AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.post_id = p.id))
      EXCEPT
      (SELECT p.id FROM posts p LEFT JOIN orders o ON o.post_id = p.id
         WHERE p.status = 'available' AND o.id IS NULL)) a)          AS chenh_lech_1,
  (SELECT count(*) FROM (
      (SELECT p.id FROM posts p LEFT JOIN orders o ON o.post_id = p.id
         WHERE p.status = 'available' AND o.id IS NULL)
      EXCEPT
      (SELECT p.id FROM posts p WHERE p.status = 'available'
         AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.post_id = p.id))) b) AS chenh_lech_2;

-- ---------------------------------------------------------------------
-- (c) Người dùng chưa từng đặt mua đơn nào.  Kiểm chứng: 9 người dùng.
-- ---------------------------------------------------------------------
-- Cách 1: NOT EXISTS
SELECT u.id, u.name
FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.buyer_id = u.id)
ORDER BY u.id;

-- Cách 2: NOT IN với subquery SELECT buyer_id FROM orders (cùng kết quả 9 người)
SELECT u.id, u.name
FROM users u
WHERE u.id NOT IN (SELECT buyer_id FROM orders)
ORDER BY u.id;

-- Giải thích: NOT IN cho cùng kết quả vì orders.buyer_id khai báo NOT NULL, nên tập con của
-- subquery không bao giờ chứa NULL.
-- Khi subquery CÓ NULL thì NOT IN cho kết quả sai: "x NOT IN (a, b, NULL)" nghĩa là
-- "x <> a AND x <> b AND x <> NULL"; vế cuối luôn UNKNOWN nên cả biểu thức không bao giờ TRUE
-- và WHERE loại mọi hàng -> trả về 0 hàng dù thực tế có người dùng chưa mua gì.
-- Minh họa: thêm một giá trị NULL vào subquery thì NOT IN trả về 0 hàng, còn NOT EXISTS vẫn đúng.
SELECT count(*) AS not_in_khi_co_null
FROM users u
WHERE u.id NOT IN (SELECT NULL::bigint UNION ALL SELECT buyer_id FROM orders);
-- Vì vậy NOT EXISTS an toàn hơn khi cột của subquery có thể NULL.

-- #####################################################################
-- BÀI 4 — Nhân bản hàng khi tổng hợp trên JOIN 1-n
-- #####################################################################

-- Báo cáo mỗi người bán: số tin đã đăng và tổng số đơn nhận được.

-- ---------------------------------------------------------------------
-- (a) Phiên bản SAI: JOIN trực tiếp users -> posts -> orders rồi COUNT(p.id).
--     Mỗi tin có k đơn thì sau join xuất hiện k hàng, nên tin bị đếm k lần.
-- ---------------------------------------------------------------------
SELECT u.id AS seller_id,
       COUNT(p.id) AS post_count,   -- bị đếm nhân bản
       COUNT(o.id) AS order_count
FROM users u
LEFT JOIN posts p  ON p.seller_id = u.id
LEFT JOIN orders o ON o.post_id   = p.id
GROUP BY u.id
ORDER BY u.id;

-- ---------------------------------------------------------------------
-- (b) Phiên bản ĐÚNG, cách 1: COUNT(DISTINCT p.id)
-- ---------------------------------------------------------------------
SELECT u.id AS seller_id,
       COUNT(DISTINCT p.id) AS post_count,
       COUNT(o.id)          AS order_count
FROM users u
LEFT JOIN posts p  ON p.seller_id = u.id
LEFT JOIN orders o ON o.post_id   = p.id
GROUP BY u.id
ORDER BY u.id;

-- Cách 2: CTE tổng hợp từng quan hệ trước khi ghép (không nhân bản vì mỗi CTE có 1 hàng/người bán)
WITH post_counts AS (
    SELECT seller_id, COUNT(*) AS post_count
    FROM posts
    GROUP BY seller_id
), order_counts AS (
    SELECT p.seller_id, COUNT(o.id) AS order_count
    FROM posts p
    JOIN orders o ON o.post_id = p.id
    GROUP BY p.seller_id
)
SELECT u.id AS seller_id,
       COALESCE(pc.post_count, 0)  AS post_count,
       COALESCE(oc.order_count, 0) AS order_count
FROM users u
LEFT JOIN post_counts pc  ON pc.seller_id = u.id
LEFT JOIN order_counts oc ON oc.seller_id = u.id
ORDER BY u.id;

-- Kiểm chứng: số tin của một người bán ở phiên bản (b) khớp SELECT COUNT(*) FROM posts WHERE seller_id = ...
SELECT COUNT(*) AS so_tin_that FROM posts WHERE seller_id = 3;

-- Chỉ ra chênh lệch của phiên bản (a) trên người bán id = 3: (a) cho 7 tin, thực tế chỉ có 5
SELECT u.id AS seller_id,
       COUNT(p.id)          AS post_count_phien_ban_a,
       COUNT(DISTINCT p.id) AS post_count_phien_ban_b
FROM users u
LEFT JOIN posts p  ON p.seller_id = u.id
LEFT JOIN orders o ON o.post_id   = p.id
WHERE u.id = 3
GROUP BY u.id;

-- Số người bán bị lệch giữa (a) và (b): kỳ vọng 51
SELECT count(*) AS so_nguoi_ban_bi_lech
FROM (
    SELECT u.id
    FROM users u
    LEFT JOIN posts p  ON p.seller_id = u.id
    LEFT JOIN orders o ON o.post_id   = p.id
    GROUP BY u.id
    HAVING COUNT(p.id) <> COUNT(DISTINCT p.id)
) t;
