-- =====================================================================
-- Truy vấn dữ liệu — Bài 1 đến Bài 4 (Bài 1-2 Cơ bản, Bài 3-4 Nâng cao)
-- Yêu cầu: đã nạp seed_truy_van.sql (nạp một lần, dùng chung cho cả 4 bài)
--   docker exec -i pg-marketplace psql -U postgres -d postgres < seed_truy_van.sql
-- Chạy file này:
--   docker exec -i pg-marketplace psql -U postgres -d postgres -a < bai2/bai2.sql
-- =====================================================================

-- #####################################################################
-- BÀI 1 — Màn hình tìm kiếm và phân trang (bảng posts)
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Tin available thuộc category_id = 2, giá từ 500.000 đến 5.000.000,
--     sắp xếp giá tăng dần.
--     Kiểm chứng: trả về 16 hàng, mọi hàng nằm trong khoảng giá.
-- ---------------------------------------------------------------------
SELECT id, title, price, status, category_id
FROM posts
WHERE status = 'available'
  AND category_id = 2
  AND price BETWEEN 500000 AND 5000000
ORDER BY price ASC;

-- ---------------------------------------------------------------------
-- (b) Tìm tin theo từ khóa trong tiêu đề, không phân biệt hoa thường (ILIKE).
--     Thay 'laptop' bằng từ khóa cần tìm.
-- ---------------------------------------------------------------------
SELECT id, title, price
FROM posts
WHERE title ILIKE '%laptop%';

-- ---------------------------------------------------------------------
-- (c) Danh sách tin chưa có mô tả.
--     Kiểm chứng: trả về 134 hàng.
-- ---------------------------------------------------------------------
SELECT id, title
FROM posts
WHERE description IS NULL;

-- Đối chứng: viết "= NULL" thì trả về 0 hàng.
-- Giải thích: NULL nghĩa là "không biết giá trị", nên "description = NULL" cho kết quả
-- UNKNOWN (không phải TRUE) với mọi hàng, kể cả hàng có description là NULL, nên WHERE
-- loại hết. So sánh với NULL phải dùng IS NULL / IS NOT NULL.
SELECT id, title
FROM posts
WHERE description = NULL;

-- ---------------------------------------------------------------------
-- (d) Trang thứ 3, pageSize = 10, của danh sách tin available, tin mới nhất trước.
--     Thứ tự ổn định khi created_at trùng nhau: thêm id làm tiêu chí phụ.
--     OFFSET = (3 - 1) * 10 = 20
-- ---------------------------------------------------------------------
SELECT id, title, created_at
FROM posts
WHERE status = 'available'
ORDER BY created_at DESC, id DESC
LIMIT 10 OFFSET 20;

-- ---------------------------------------------------------------------
-- (e) Chạy tiếp trang 1 và trang 2 của cùng truy vấn (d)
-- ---------------------------------------------------------------------
-- Trang 1
SELECT id, title, created_at
FROM posts
WHERE status = 'available'
ORDER BY created_at DESC, id DESC
LIMIT 10 OFFSET 0;

-- Trang 2
SELECT id, title, created_at
FROM posts
WHERE status = 'available'
ORDER BY created_at DESC, id DESC
LIMIT 10 OFFSET 10;

-- ---------------------------------------------------------------------
-- Yêu cầu kiểm chứng (Bài 1, phần e)
-- Gộp ba trang được đúng 30 tin phân biệt, không tin nào xuất hiện ở hai trang
-- (kỳ vọng: tong_hang = 30 và tin_phan_biet = 30)
-- ---------------------------------------------------------------------
SELECT count(*) AS tong_hang, count(DISTINCT id) AS tin_phan_biet
FROM (
    (SELECT id FROM posts WHERE status = 'available' ORDER BY created_at DESC, id DESC LIMIT 10 OFFSET 0)
    UNION ALL
    (SELECT id FROM posts WHERE status = 'available' ORDER BY created_at DESC, id DESC LIMIT 10 OFFSET 10)
    UNION ALL
    (SELECT id FROM posts WHERE status = 'available' ORDER BY created_at DESC, id DESC LIMIT 10 OFFSET 20)
) AS ba_trang;

-- #####################################################################
-- BÀI 2 — Bảng thống kê
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Số tin đăng theo từng trạng thái.
--     Kiểm chứng: tổng các nhóm bằng 1.000 (đúng tổng số hàng của posts).
-- ---------------------------------------------------------------------
SELECT status, count(*) AS so_tin
FROM posts
GROUP BY status
ORDER BY status;

-- Kiểm chứng: tổng các nhóm (kỳ vọng: 1000)
SELECT sum(so_tin) AS tong_cac_nhom
FROM (SELECT count(*) AS so_tin FROM posts GROUP BY status) AS t;

-- ---------------------------------------------------------------------
-- (b) Doanh thu (SUM(amount)) của các đơn completed theo từng tháng.
--     Kiểm chứng: đề nêu 12 hàng. Lưu ý: seed sinh created_at tương đối theo now()
--     (đơn completed trải đúng 12 tháng trước ngày chạy), nên số tháng lịch có đơn
--     là 12 hoặc 13 tùy ngày chạy. Khi chạy ngày 19/11/2026: 13 tháng
--     (hai đầu dải chỉ có vài đơn) — truy vấn vẫn đúng.
-- ---------------------------------------------------------------------
SELECT date_trunc('month', created_at)::date AS thang,
       SUM(amount) AS doanh_thu
FROM orders
WHERE status = 'completed'
GROUP BY date_trunc('month', created_at)
ORDER BY thang;

-- ---------------------------------------------------------------------
-- (c) Các danh mục có trên 70 tin đang bán.
--     Điều kiện trạng thái đặt ở WHERE (lọc từng hàng trước khi gom nhóm),
--     điều kiện đếm đặt ở HAVING (lọc nhóm sau khi gom).
--     Kiểm chứng: trả về 4 danh mục.
-- ---------------------------------------------------------------------
SELECT c.id, c.name, count(*) AS so_tin_dang_ban
FROM posts p
JOIN categories c ON c.id = p.category_id
WHERE p.status = 'available'
GROUP BY c.id, c.name
HAVING count(*) > 70
ORDER BY so_tin_dang_ban DESC;

-- ---------------------------------------------------------------------
-- (d) Điểm trung bình stars của từng người bán, tính từ reviews theo reviewee_id.
--     Kiểm chứng: trả về 156 người bán.
-- ---------------------------------------------------------------------
SELECT reviewee_id AS seller_id,
       ROUND(AVG(stars), 2) AS diem_trung_binh
FROM reviews
GROUP BY reviewee_id
ORDER BY reviewee_id;

-- #####################################################################
-- BÀI 3 — Báo cáo bằng CTE và xếp hạng
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) CTE seller_revenue: doanh thu đơn completed theo người bán, ghép tên người bán,
--     lọc doanh thu trên 20 triệu, sắp xếp giảm dần.
--     Kiểm chứng: trả về 81 người bán.
-- ---------------------------------------------------------------------
WITH seller_revenue AS (
    SELECT p.seller_id, SUM(o.amount) AS revenue
    FROM orders o
    JOIN posts p ON p.id = o.post_id
    WHERE o.status = 'completed'
    GROUP BY p.seller_id
)
SELECT sr.seller_id, u.name, sr.revenue
FROM seller_revenue sr
JOIN users u ON u.id = sr.seller_id
WHERE sr.revenue > 20000000
ORDER BY sr.revenue DESC;

-- Kiểm tra kết quả trung gian: chạy riêng SELECT * FROM seller_revenue
WITH seller_revenue AS (
    SELECT p.seller_id, SUM(o.amount) AS revenue
    FROM orders o
    JOIN posts p ON p.id = o.post_id
    WHERE o.status = 'completed'
    GROUP BY p.seller_id
)
SELECT * FROM seller_revenue ORDER BY revenue DESC;

-- ---------------------------------------------------------------------
-- (b) Xếp hạng người bán theo rating giảm dần bằng cả RANK() và ROW_NUMBER()
--     trong cùng một truy vấn.
--     Kiểm chứng: 40 người cùng rating = 5.0 đều nhận hạng 1 ở RANK(), người kế tiếp
--     nhận hạng 41; ROW_NUMBER() đánh số liên tục 1 đến 40 cho nhóm đó.
--     RANK() chừa khoảng trống sau các hạng đồng, ROW_NUMBER() luôn tăng 1 nên phải
--     thêm id làm tiêu chí phụ để thứ tự ổn định.
-- ---------------------------------------------------------------------
SELECT id, name, rating,
       RANK()       OVER (ORDER BY rating DESC)       AS rank_no,
       ROW_NUMBER() OVER (ORDER BY rating DESC, id)   AS row_no
FROM users
ORDER BY rating DESC, id;

-- ---------------------------------------------------------------------
-- (c) 3 tin mới nhất của mỗi danh mục bằng ROW_NUMBER() OVER (PARTITION BY ...).
--     Kiểm chứng: trả về tối đa 24 hàng (8 danh mục x 3).
-- ---------------------------------------------------------------------
SELECT id, title, category_id, created_at, rn
FROM (
    SELECT p.id, p.title, p.category_id, p.created_at,
           ROW_NUMBER() OVER (PARTITION BY p.category_id
                              ORDER BY p.created_at DESC, p.id DESC) AS rn
    FROM posts p
) ranked
WHERE rn <= 3
ORDER BY category_id, rn;

-- #####################################################################
-- BÀI 4 — Viết lại correlated subquery
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Truy vấn gốc: danh sách tin available kèm số đơn và thời điểm đơn gần nhất.
--     Hai subquery trong SELECT này là CORRELATED vì cả hai tham chiếu cột của truy vấn
--     ngoài (o.post_id = p.id). Chúng không chạy độc lập được và phải thực thi lại cho
--     TỪNG hàng của posts (550 tin -> 550 lần, mỗi subquery), thể hiện ở SubPlan với
--     loops = 550 trong kế hoạch.
-- ---------------------------------------------------------------------
SELECT p.id, p.title,
       (SELECT COUNT(*) FROM orders o WHERE o.post_id = p.id) AS order_count,
       (SELECT MAX(o.created_at) FROM orders o WHERE o.post_id = p.id) AS last_order_at
FROM posts p
WHERE p.status = 'available';

-- ---------------------------------------------------------------------
-- (b) Viết lại bằng LEFT JOIN + GROUP BY cho cùng kết quả.
--     Dùng COUNT(o.id) chứ không phải COUNT(*): tin chưa có đơn vẫn có 1 hàng sau
--     LEFT JOIN (cột của orders là NULL); COUNT(o.id) bỏ qua NULL nên trả 0 đúng,
--     COUNT(*) sẽ trả 1 sai.
-- ---------------------------------------------------------------------
SELECT p.id, p.title,
       COUNT(o.id)       AS order_count,
       MAX(o.created_at) AS last_order_at
FROM posts p
LEFT JOIN orders o ON o.post_id = p.id
WHERE p.status = 'available'
GROUP BY p.id, p.title;

-- ---------------------------------------------------------------------
-- (c) So sánh hai phiên bản bằng EXPLAIN ANALYZE
-- ---------------------------------------------------------------------
-- Bản cũ: có SubPlan với loops = 550, thời gian thực thi lớn hơn rõ rệt
EXPLAIN ANALYZE
SELECT p.id, p.title,
       (SELECT COUNT(*) FROM orders o WHERE o.post_id = p.id) AS order_count,
       (SELECT MAX(o.created_at) FROM orders o WHERE o.post_id = p.id) AS last_order_at
FROM posts p
WHERE p.status = 'available';

-- Bản viết lại: chỉ một lần tổng hợp (HashAggregate trên Hash Right Join), thời gian thấp hơn nhiều
EXPLAIN ANALYZE
SELECT p.id, p.title,
       COUNT(o.id)       AS order_count,
       MAX(o.created_at) AS last_order_at
FROM posts p
LEFT JOIN orders o ON o.post_id = p.id
WHERE p.status = 'available'
GROUP BY p.id, p.title;

-- ---------------------------------------------------------------------
-- Yêu cầu kiểm chứng (Bài 4)
-- Hai phiên bản cùng trả về 550 hàng, giá trị từng cột trùng khớp
-- (kỳ vọng: cả hai chiều EXCEPT đều trả so_hang_khac_nhau = 0)
-- ---------------------------------------------------------------------
SELECT count(*) AS so_hang_khac_nhau FROM (
    (SELECT p.id, p.title,
            (SELECT COUNT(*) FROM orders o WHERE o.post_id = p.id),
            (SELECT MAX(o.created_at) FROM orders o WHERE o.post_id = p.id)
     FROM posts p WHERE p.status = 'available')
    EXCEPT
    (SELECT p.id, p.title, COUNT(o.id), MAX(o.created_at)
     FROM posts p LEFT JOIN orders o ON o.post_id = p.id
     WHERE p.status = 'available' GROUP BY p.id, p.title)
) AS d1;

SELECT count(*) AS so_hang_khac_nhau FROM (
    (SELECT p.id, p.title, COUNT(o.id), MAX(o.created_at)
     FROM posts p LEFT JOIN orders o ON o.post_id = p.id
     WHERE p.status = 'available' GROUP BY p.id, p.title)
    EXCEPT
    (SELECT p.id, p.title,
            (SELECT COUNT(*) FROM orders o WHERE o.post_id = p.id),
            (SELECT MAX(o.created_at) FROM orders o WHERE o.post_id = p.id)
     FROM posts p WHERE p.status = 'available')
) AS d2;
