-- =====================================================================
-- Hiệu năng truy vấn — Bài 1 đến Bài 4 (Bài 1-2 Cơ bản, Bài 3-4 Nâng cao)
-- Yêu cầu: nạp seed_hieu_nang.sql (KHÁC seed_truy_van.sql, đừng dùng nhầm)
--   docker exec -i pg-marketplace psql -U postgres -d postgres < seed_hieu_nang.sql
-- Chạy file này (nối tiếp từ Bài 1 đến Bài 4 trên cùng database):
--   docker exec -i pg-marketplace psql -U postgres -d postgres -a < bai5/bai5.sql
-- Các bài làm nối tiếp: chỉ mục tạo ở bài trước còn dùng ở bài sau. Muốn chạy lại
-- từ đầu thì nạp lại seed_hieu_nang.sql (seed không tạo chỉ mục, nên đưa mọi thứ
-- về trạng thái ban đầu).
-- Thời gian trong EXPLAIN ANALYZE khác nhau giữa các máy và các lần chạy;
-- điều cần so sánh là DẠNG KẾ HOẠCH và TỈ LỆ thời gian trước/sau.
-- =====================================================================

-- #####################################################################
-- BÀI 1 — Đọc EXPLAIN, thêm chỉ mục và đo lại
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) EXPLAIN cho ba truy vấn lọc posts theo seller_id = 555, category_id = 3
--     và id = 12345. Ghi lại loại scan, cost và rows của từng truy vấn.
--     Kiểm chứng: truy vấn theo id đã dùng Index Scan ngay từ đầu (id là khóa chính
--     nên đã có chỉ mục posts_pkey); hai truy vấn còn lại là Seq Scan.
-- ---------------------------------------------------------------------
-- Truy vấn 1: theo seller_id (~100 hàng / 200.000)
EXPLAIN ANALYZE SELECT * FROM posts WHERE seller_id = 555;

-- Truy vấn 2: theo category_id (~25.000 hàng / 200.000)
EXPLAIN ANALYZE SELECT * FROM posts WHERE category_id = 3;

-- Truy vấn 3: theo id
EXPLAIN ANALYZE SELECT * FROM posts WHERE id = 12345;

-- Giải thích: PostgreSQL tự tạo chỉ mục B-tree cho khóa chính, nên tìm theo id đi thẳng
-- vào chỉ mục (Index Scan, rows=1). seller_id và category_id chưa có chỉ mục nào
-- (seed cố ý không tạo), planner chỉ còn cách đọc toàn bộ bảng: Seq Scan, rồi
-- lọc bỏ gần hết hàng ("Rows Removed by Filter").

-- ---------------------------------------------------------------------
-- (b) Tạo chỉ mục cho seller_id, chạy lại truy vấn đầu và so sánh.
--     Kiểm chứng: chuyển sang kế hoạch dùng chỉ mục (Bitmap Heap Scan), thời gian giảm
--     rất nhiều (hàng chục lần).
-- ---------------------------------------------------------------------
CREATE INDEX idx_posts_seller_id ON posts (seller_id);
ANALYZE posts;

EXPLAIN ANALYZE SELECT * FROM posts WHERE seller_id = 555;

-- ---------------------------------------------------------------------
-- (c) Tạo chỉ mục cho category_id, chạy lại truy vấn thứ hai và so sánh.
--     Kiểm chứng: cũng chuyển sang dùng chỉ mục nhưng chỉ nhanh hơn khoảng 2 lần,
--     vì mỗi danh mục chiếm tới ~25.000 trong 200.000 hàng.
-- ---------------------------------------------------------------------
CREATE INDEX idx_posts_category_id ON posts (category_id);
ANALYZE posts;

EXPLAIN ANALYZE SELECT * FROM posts WHERE category_id = 3;

-- ---------------------------------------------------------------------
-- (d) Vì sao mức cải thiện của hai chỉ mục chênh nhau nhiều
-- ---------------------------------------------------------------------
-- Chỉ mục giúp ích tỉ lệ thuận với việc nó LOẠI BỎ được bao nhiêu hàng.
--  - seller_id = 555 chỉ khớp ~100 hàng (0,05% bảng): đi qua chỉ mục rồi đọc đúng
--    ~100 hàng ở khoảng 110 trang, bỏ qua hơn 99,9% dữ liệu -> nhanh hơn hàng chục lần.
--  - category_id = 3 khớp ~25.000 hàng (~12% bảng), rải khắp mọi trang của bảng:
--    vẫn phải đọc gần như toàn bộ các trang (nhiều hàng khớp trên mỗi trang), chỉ tiết
--    kiệm được việc kiểm tra điều kiện lọc từng hàng -> chỉ nhanh hơn ~2 lần.
-- Nói gọn: chỉ mục phát huy khi điều kiện CHỌN LỌC (ít hàng); cột ít giá trị phân biệt
-- (8 danh mục) cho lợi ích nhỏ.

-- #####################################################################
-- BÀI 2 — Chỉ mục cho trang "tin đăng của tôi"
-- #####################################################################
-- Trang này lọc theo seller_id và sắp xếp created_at DESC, lấy 20 tin.

-- ---------------------------------------------------------------------
-- (a) Chạy EXPLAIN ANALYZE với chỉ mục hiện có (idx_posts_seller_id từ Bài 1)
--     và tìm bước Sort trong kế hoạch.
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT * FROM posts
WHERE seller_id = 555
ORDER BY created_at DESC
LIMIT 20;
-- Kế hoạch có nút "Sort" (top-N heapsort): chỉ mục seller_id tìm ra ~100 hàng của người bán
-- nhưng KHÔNG sắp thứ tự theo created_at, nên phải đọc cả ~100 hàng rồi sắp xếp, mới lấy được 20.

-- ---------------------------------------------------------------------
-- (b) Đề xuất và tạo chỉ mục phù hợp cho CẢ điều kiện lọc lẫn thứ tự sắp xếp
--     rồi đo lại.
--     Kiểm chứng: không còn bước sắp xếp riêng, không còn nút Sort; dữ liệu lấy
--     theo đúng thứ tự từ chỉ mục.
-- ---------------------------------------------------------------------
-- Chỉ mục kết hợp: cột lọc bằng (=) đứng trước, cột sắp xếp đứng sau, đúng chiều DESC.
CREATE INDEX idx_posts_seller_created ON posts (seller_id, created_at DESC);
ANALYZE posts;

EXPLAIN ANALYZE
SELECT * FROM posts
WHERE seller_id = 555
ORDER BY created_at DESC
LIMIT 20;
-- Trong chỉ mục, các hàng của một seller_id nằm kề nhau và đã sắp theo created_at DESC, nên
-- planner đi vào seller_id = 555 rồi đọc 20 mục đầu tiên là dừng (Limit + Index Scan).

-- ---------------------------------------------------------------------
-- (c) Đánh đổi khi thêm chỉ mục này (xét tới thao tác đăng tin mới)
-- ---------------------------------------------------------------------
-- 1) Mỗi INSERT/UPDATE/DELETE trên posts phải cập nhật thêm mọi chỉ mục của bảng
--    (hiện đã có posts_pkey, idx_posts_seller_id, idx_posts_category_id và chỉ mục mới):
--    đăng tin mới chậm hơn một chút và tốn thêm dung lượng đĩa/bộ nhớ.
-- 2) Chỉ mục (seller_id, created_at) đã bao quát mọi truy vấn lọc theo seller_id đơn thuần
--    (cột đầu tiên), nên idx_posts_seller_id thành dư thừa; có thể DROP để bớt chi phí ghi.
--    Ở bài này vẫn giữ lại để các bài sau đối chiếu.

-- #####################################################################
-- BÀI 3 — Composite index và covering index
-- #####################################################################
-- Để kế hoạch ở Bài 3 không bị nhiễu bởi các chỉ mục theo seller_id của Bài 1-2,
-- gỡ chúng trước khi bắt đầu (idx_posts_seller_created đã bao quát idx_posts_seller_id).
DROP INDEX idx_posts_seller_id;
DROP INDEX idx_posts_seller_created;

-- ---------------------------------------------------------------------
-- (a) Tạo INDEX (seller_id, status) rồi kiểm tra bằng EXPLAIN ba truy vấn:
--     lọc cả hai cột, chỉ lọc seller_id, chỉ lọc status.
--     Kiểm chứng: hai truy vấn đầu dùng được chỉ mục, truy vấn chỉ lọc status rơi
--     về Seq Scan.
-- ---------------------------------------------------------------------
CREATE INDEX idx_posts_seller_status ON posts (seller_id, status);
ANALYZE posts;

-- Lọc cả hai cột: dùng chỉ mục (cả hai điều kiện nằm trong Index Cond)
EXPLAIN ANALYZE SELECT * FROM posts WHERE seller_id = 555 AND status = 'available';

-- Chỉ lọc seller_id (cột ĐẦU của chỉ mục): vẫn dùng được chỉ mục
EXPLAIN ANALYZE SELECT * FROM posts WHERE seller_id = 555;

-- Chỉ lọc status (cột THỨ HAI): rơi về Seq Scan
EXPLAIN ANALYZE SELECT * FROM posts WHERE status = 'available';

-- Giải thích: chỉ mục nhiều cột được sắp theo cột đầu rồi mới tới cột sau (quy tắc "tiền tố
-- bên trái"). Truy vấn không có điều kiện trên cột đầu (seller_id) thì không "đi vào" chỉ mục
-- được. Hơn nữa status chỉ có 3 giá trị và 'available' chiếm 70% bảng nên dù có chỉ mục cũng
-- không có lợi.

-- ---------------------------------------------------------------------
-- (b) Truy vấn chỉ lấy seller_id, price: tạo chỉ mục (seller_id) INCLUDE (price),
--     chạy VACUUM posts, rồi xác nhận kế hoạch.
--     Kiểm chứng: kế hoạch là Index Only Scan với Heap Fetches: 0.
--     Thử bỏ qua bước VACUUM: khi visibility map chưa cập nhật, kế hoạch vẫn là
--     Bitmap Heap Scan dù chỉ mục đã đủ cột.
-- ---------------------------------------------------------------------
-- Đưa bảng về trạng thái "chưa VACUUM": tắt autovacuum cho bảng này (để nó không tự dọn
-- chen ngang) và ghi lại toàn bộ hàng một lần (price = price, giá trị không đổi) để xóa
-- hết visibility map. Đây chính là điều xảy ra trên bảng vừa bị ghi nhiều mà chưa được VACUUM.
ALTER TABLE posts SET (autovacuum_enabled = off);
UPDATE posts SET price = price;

CREATE INDEX idx_posts_seller_cover ON posts (seller_id) INCLUDE (price);
ANALYZE posts;

-- Kiểm tra visibility map: relallvisible = 0 nghĩa là chưa có trang nào được đánh dấu
-- "tất cả hàng đều nhìn thấy"
SELECT relpages, relallvisible FROM pg_class WHERE relname = 'posts';

-- Chưa VACUUM: dù chỉ mục đã chứa đủ seller_id và price, kế hoạch vẫn là Bitmap Heap Scan
-- (phải ra bảng chính kiểm tra tính hiển thị của từng hàng)
EXPLAIN ANALYZE SELECT seller_id, price FROM posts WHERE seller_id = 555;

-- VACUUM cập nhật visibility map
VACUUM posts;

SELECT relpages, relallvisible FROM pg_class WHERE relname = 'posts';

-- Đã VACUUM: Index Only Scan, Heap Fetches: 0 (không cần đọc bảng chính)
EXPLAIN ANALYZE SELECT seller_id, price FROM posts WHERE seller_id = 555;

-- Bật lại autovacuum như mặc định
ALTER TABLE posts RESET (autovacuum_enabled);

-- #####################################################################
-- BÀI 4 — Hai vấn đề sinh từ tầng ứng dụng
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) N+1: tổng số truy vấn của đoạn mã ở trang "Bài toán N+1", một truy vấn
--     SQL thay thế toàn bộ vòng lặp, và biểu hiện khi dùng ORM.
--     (Giả định đoạn mã của trang đó: lấy 20 tin available mới nhất rồi trong vòng
--     lặp, với từng tin gọi thêm một truy vấn lấy người bán theo seller_id.)
--     Kiểm chứng: số truy vấn giảm từ 21 xuống 1; truy vấn thay thế trả đủ 20 tin
--     kèm tên người bán.
-- ---------------------------------------------------------------------
-- Tổng số truy vấn của đoạn mã: 1 (lấy danh sách) + 20 (mỗi tin một truy vấn lấy người bán)
-- = 21 truy vấn, mỗi truy vấn là một lượt đi-về tới database.

-- Truy vấn thứ 1: lấy danh sách 20 tin
SELECT id, title, price, seller_id
FROM posts
WHERE status = 'available'
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- Truy vấn thứ 2..21: lặp 20 lần, mỗi lần với một seller_id (ví dụ minh họa với seller 1 và 2)
SELECT name FROM users WHERE id = 1;
SELECT name FROM users WHERE id = 2;
-- ... (lặp tiếp cho tới tin thứ 20)

-- MỘT truy vấn thay thế toàn bộ vòng lặp: JOIN users ngay trong truy vấn đầu
SELECT p.id, p.title, p.price, u.name AS seller_name
FROM posts p
JOIN users u ON u.id = p.seller_id
WHERE p.status = 'available'
ORDER BY p.created_at DESC, p.id DESC
LIMIT 20;

-- Kiểm chứng: truy vấn thay thế trả đủ 20 hàng, mỗi hàng có tên người bán
SELECT count(*) AS so_hang, count(seller_name) AS so_hang_co_ten_nguoi_ban
FROM (
    SELECT p.id, u.name AS seller_name
    FROM posts p
    JOIN users u ON u.id = p.seller_id
    WHERE p.status = 'available'
    ORDER BY p.created_at DESC, p.id DESC
    LIMIT 20
) AS t;

-- Biểu hiện khi dùng ORM (học phần NestJS): vấn đề này rất hay xuất hiện NGẦM. Ví dụ với
-- TypeORM, gọi postRepository.find() lấy 20 tin rồi trong vòng lặp truy cập post.seller
-- (quan hệ lazy) hoặc gọi userRepository.findOne() cho từng tin: ORM âm thầm sinh 1 + 20
-- truy vấn mà code trông rất gọn. Cách tránh: nạp quan hệ cùng lúc bằng
-- find({ relations: { seller: true } }) hoặc QueryBuilder().leftJoinAndSelect('p.seller', 'u')
-- để ORM sinh một câu JOIN như trên; và bật log truy vấn khi phát triển để đếm số câu SQL.

-- ---------------------------------------------------------------------
-- (b) Keyset pagination: tạo chỉ mục (created_at DESC, id DESC), đo EXPLAIN ANALYZE
--     cho LIMIT 20 OFFSET 100000, rồi lấy mốc (created_at, id) của hàng cuối trang
--     đó, viết phiên bản keyset và đo lại.
--     Kiểm chứng: bản OFFSET chậm hơn rất nhiều bản keyset; nêu đánh đổi của keyset.
-- ---------------------------------------------------------------------
CREATE INDEX idx_posts_created_id ON posts (created_at DESC, id DESC);
ANALYZE posts;

-- Bản OFFSET: phải đi qua 100.000 mục trong chỉ mục rồi VỨT chúng đi, mới lấy được 20 hàng
-- (xem "actual ... rows=100020" ở nút Index Scan: đọc 100.020 hàng để trả 20)
EXPLAIN ANALYZE
SELECT * FROM posts
ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 100000;

-- Lấy mốc (created_at, id) của hàng CUỐI của trang đó (hàng thứ 100.020), lưu vào biến psql
SELECT created_at AS last_created_at, id AS last_id
FROM posts
ORDER BY created_at DESC, id DESC
OFFSET 100019 LIMIT 1
\gset

SELECT :'last_created_at' AS moc_created_at, :last_id AS moc_id;

-- Bản keyset: lấy 20 hàng NGAY SAU mốc bằng so sánh bộ (created_at, id), không có OFFSET
EXPLAIN ANALYZE
SELECT * FROM posts
WHERE (created_at, id) < (:'last_created_at', :last_id)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- Đánh đổi của keyset:
--  + Thời gian gần như không đổi dù ở trang nào: chỉ mục nhảy thẳng tới mốc rồi đọc 20 mục,
--    không phải bỏ qua N hàng như OFFSET (OFFSET càng sâu càng chậm).
--  + Kết quả ổn định khi có tin mới được thêm giữa các lần tải trang (OFFSET có thể lặp/sót hàng).
--  - Chỉ đi tuần tự "trang kế tiếp/trang trước", KHÔNG nhảy thẳng tới trang số N tùy ý.
--  - Ứng dụng phải giữ và gửi lại mốc (created_at, id) của hàng cuối mỗi trang; cần có thứ tự
--    sắp xếp duy nhất (thêm id làm tiêu chí phụ) và một chỉ mục khớp đúng thứ tự đó.
