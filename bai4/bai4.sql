-- =====================================================================
-- Thao tác & giao dịch — Bài 1 đến Bài 4
-- Yêu cầu: đã nạp seed_truy_van.sql
--   docker exec -i pg-marketplace psql -U postgres -d postgres < seed_truy_van.sql
-- LƯU Ý: các bài ở đây GHI dữ liệu (đổi đơn 61, hủy đơn 63, ...) nên làm lệch số liệu
-- của các bài truy vấn. Chạy xong, nạp lại seed_truy_van.sql để đưa dữ liệu về ban đầu.
--
-- Bài 1 và Bài 2 chạy tuần tự được bằng:  psql -a < bai4.sql (phần Bài 1, Bài 2)
-- Bài 3 và Bài 4 cần HAI PHIÊN psql chạy xen kẽ nên được viết thành kịch bản từng bước
-- (phần comment), mở hai cửa sổ terminal và gõ theo thứ tự.
-- =====================================================================

-- #####################################################################
-- BÀI 1 — Thao tác ghi với RETURNING
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) INSERT một tin đăng mới, dùng RETURNING lấy về id và created_at.
--     (Seed có 1.000 tin nên tin mới sẽ có id = 1001; các lệnh bên dưới dùng id này.)
-- ---------------------------------------------------------------------
INSERT INTO posts (title, description, price, status, seller_id, category_id)
VALUES ('Tin thử nghiệm Bài 4', 'Tin dùng để thử INSERT/UPDATE/DELETE', 1000000, 'available', 1, 1)
RETURNING id, created_at;

-- Kiểm chứng trước (b): SELECT với đúng điều kiện WHERE sẽ dùng, xác nhận chỉ một hàng bị tác động
SELECT id, title, price FROM posts WHERE id = 1001;

-- ---------------------------------------------------------------------
-- (b) UPDATE hạ giá tin đó 10%, RETURNING cho thấy giá mới
-- ---------------------------------------------------------------------
UPDATE posts
SET price = price * 90 / 100
WHERE id = 1001
RETURNING id, price;

-- Kiểm chứng trước (c): xác nhận chỉ một hàng sẽ bị xóa
SELECT id, title, price FROM posts WHERE id = 1001;

-- ---------------------------------------------------------------------
-- (c) DELETE chính tin đó, RETURNING xác nhận hàng đã xóa
-- ---------------------------------------------------------------------
DELETE FROM posts
WHERE id = 1001
RETURNING id, title;

-- Kiểm chứng: thử DELETE một tin đã có đơn (id = 99) -> lỗi khóa ngoại
-- (đây là lỗi mong đợi: orders.post_id tham chiếu posts.id, nên không xóa được tin đang có đơn)
DELETE FROM posts WHERE id = 99;
-- ERROR:  update or delete on table "posts" violates foreign key constraint
--         "orders_post_id_fkey" on table "orders"
-- DETAIL:  Key (id)=(99) is still referenced from table "orders".

-- #####################################################################
-- BÀI 2 — Transaction cho nghiệp vụ nhiều bước
-- #####################################################################

-- ---------------------------------------------------------------------
-- (a) Transaction hoàn tất đơn id = 61: đổi đơn sang completed và đổi tin tương ứng sang sold.
--     (Trước đó: đơn đang confirmed, tin đang reserved.)
-- ---------------------------------------------------------------------
SELECT o.id AS order_id, o.status AS order_status, p.id AS post_id, p.status AS post_status
FROM orders o JOIN posts p ON p.id = o.post_id
WHERE o.id = 61;

BEGIN;

UPDATE orders
SET status = 'completed', updated_at = now()
WHERE id = 61 AND status = 'confirmed';

UPDATE posts
SET status = 'sold'
WHERE id = (SELECT post_id FROM orders WHERE id = 61);

COMMIT;

-- Kiểm chứng sau COMMIT: cả đơn và tin đều đổi trạng thái (completed và sold)
SELECT o.id AS order_id, o.status AS order_status, p.id AS post_id, p.status AS post_status
FROM orders o JOIN posts p ON p.id = o.post_id
WHERE o.id = 61;

-- ---------------------------------------------------------------------
-- (b) Phiên bản thứ hai có MỘT LỆNH SAI và dùng ROLLBACK để hủy toàn bộ (thử trên đơn 62).
--     Lệnh thứ hai cố đặt trạng thái tin không hợp lệ -> vi phạm CHECK -> giao dịch lỗi.
-- ---------------------------------------------------------------------
BEGIN;

UPDATE orders
SET status = 'completed', updated_at = now()
WHERE id = 62;

UPDATE posts
SET status = 'khong_hop_le'            -- lệnh sai: vi phạm CHECK (status IN ('available','reserved','sold'))
WHERE id = (SELECT post_id FROM orders WHERE id = 62);

ROLLBACK;                               -- hủy cả lệnh đúng ở trên, không để dữ liệu nửa vời

-- Kiểm chứng sau ROLLBACK: không bản ghi nào thay đổi (đơn 62 vẫn confirmed, tin 62 vẫn reserved)
SELECT o.id AS order_id, o.status AS order_status, p.id AS post_id, p.status AS post_status
FROM orders o JOIN posts p ON p.id = o.post_id
WHERE o.id = 62;

-- ---------------------------------------------------------------------
-- (c) Ba nghiệp vụ — nghiệp vụ nào cần transaction?
-- ---------------------------------------------------------------------
--   1) Đổi tiêu đề một tin:  UPDATE posts SET title = ... WHERE id = ...
--      KHÔNG cần transaction: chỉ MỘT câu lệnh, mà mỗi câu lệnh đơn lẻ trong PostgreSQL
--      đã tự thành một giao dịch (hoặc thành công hết, hoặc không đổi gì).
--   2) Hủy đơn (đổi đơn sang cancelled VÀ trả tin về available):
--      CẦN transaction: có HAI bảng cần đổi cùng nhau. Nếu chỉ đổi đơn mà lỗi trước khi trả
--      tin về available thì tin bị kẹt ở reserved dù không còn đơn nào (dữ liệu mâu thuẫn).
--      Hai thay đổi phải cùng thành công hoặc cùng hủy.
--   3) Ghi một đánh giá mới:  INSERT INTO reviews ...
--      KHÔNG cần transaction: chỉ MỘT câu INSERT, tự nó là nguyên tử; các ràng buộc
--      (stars 1-5, UNIQUE(order_id), khóa ngoại) đã được kiểm tra ngay trong lệnh đó.
--   Quy tắc chung: cần transaction khi nghiệp vụ gồm NHIỀU câu lệnh ghi mà kết quả chỉ đúng
--   khi tất cả cùng xảy ra.

-- ---------------------------------------------------------------------
-- (d) Transaction cho nghiệp vụ hủy đơn (thử trên đơn 63: confirmed, tin 63 đang reserved)
-- ---------------------------------------------------------------------
SELECT o.id AS order_id, o.status AS order_status, p.id AS post_id, p.status AS post_status
FROM orders o JOIN posts p ON p.id = o.post_id
WHERE o.id = 63;

BEGIN;

UPDATE orders
SET status = 'cancelled', updated_at = now()
WHERE id = 63 AND status IN ('pending', 'confirmed');   -- chỉ hủy được đơn chưa kết thúc

UPDATE posts
SET status = 'available'
WHERE id = (SELECT post_id FROM orders WHERE id = 63);

COMMIT;

SELECT o.id AS order_id, o.status AS order_status, p.id AS post_id, p.status AS post_status
FROM orders o JOIN posts p ON p.id = o.post_id
WHERE o.id = 63;

-- #####################################################################
-- BÀI 3 (Nâng cao) — Hai phiên song song: lost update và khóa hàng
-- #####################################################################
-- Cách làm: mở HAI terminal, mỗi terminal vào psql:
--     docker exec -it pg-marketplace psql -U postgres -d postgres
-- Gọi là Phiên 1 và Phiên 2. Gõ các lệnh theo ĐÚNG thứ tự bước (1, 2, 3, ...).
-- Mức cô lập mặc định của PostgreSQL: READ COMMITTED.

-- ---------------------------------------------------------------------
-- (a) Tái hiện lost update trên tin id = 451 (giá 4.080.000, trên 1 triệu)
-- ---------------------------------------------------------------------
-- Bước 1  [Phiên 1]  BEGIN;
-- Bước 2  [Phiên 1]  SELECT price FROM posts WHERE id = 451;        -- đọc được 4080000
-- Bước 3  [Phiên 2]  BEGIN;
-- Bước 4  [Phiên 2]  SELECT price FROM posts WHERE id = 451;        -- cũng đọc 4080000
-- Bước 5  [Phiên 1]  -- tự tính giá giảm 100.000 trong ứng dụng rồi ghi lại giá trị đã tính
--                    UPDATE posts SET price = 3980000 WHERE id = 451;
--                    COMMIT;
-- Bước 6  [Phiên 2]  -- cùng đọc 4080000 nên cũng tính ra 3980000
--                    UPDATE posts SET price = 3980000 WHERE id = 451;
--                    COMMIT;
-- Kiểm chứng:        SELECT price FROM posts WHERE id = 451;
--                    -> 3980000: hai lần giảm 100.000 nhưng giá cuối chỉ giảm MỘT lần
--                    (cập nhật của một phiên bị mất: lost update).
--
-- Viết lại đúng bằng UPDATE ... SET price = price - ... (đặt lại giá về 4080000 trước):
--     UPDATE posts SET price = 4080000 WHERE id = 451;
-- Chạy lại cùng kịch bản, nhưng ở Bước 5 và Bước 6 mỗi phiên dùng:
--     UPDATE posts SET price = price - 100000 WHERE id = 451;
-- Kết quả: giá cuối = 3880000 (giảm đủ hai lần).
-- Giải thích: "price = price - 100000" được tính BÊN TRONG cơ sở dữ liệu trên giá trị hiện tại
-- của hàng. Phiên 2 phải chờ khóa hàng mà Phiên 1 giữ; khi Phiên 1 COMMIT, Phiên 2 đọc lại
-- phiên bản hàng mới nhất (3980000) rồi mới trừ tiếp, nên không mất cập nhật. Cách cũ tính
-- giá trong ứng dụng từ giá trị đã đọc trước đó (đã cũ), nên ghi đè lên kết quả của phiên kia.

-- ---------------------------------------------------------------------
-- (b) Hai phiên cùng đặt mua tin available chưa có đơn (id = 500), CÓ FOR UPDATE
-- ---------------------------------------------------------------------
-- Cả hai phiên chạy cùng một trình tự (Phiên 1: buyer_id = 10, Phiên 2: buyer_id = 20):
--     BEGIN;
--     SELECT id, status FROM posts WHERE id = 500 AND status = 'available' FOR UPDATE;
--     INSERT INTO orders (post_id, buyer_id, amount)
--     SELECT p.id, <buyer_id>, p.price
--     FROM posts p
--     WHERE p.id = 500
--       AND p.status = 'available'
--       AND NOT EXISTS (SELECT 1 FROM orders o
--                       WHERE o.post_id = p.id AND o.status IN ('pending', 'confirmed'));
--     COMMIT;
-- Thứ tự thực hiện:
--   Bước 1  [Phiên 1]  BEGIN; rồi SELECT ... FOR UPDATE;    -- Phiên 1 khóa hàng của tin 500
--   Bước 2  [Phiên 2]  BEGIN; rồi SELECT ... FOR UPDATE;    -- Phiên 2 BỊ CHỜ (treo) tại đây
--   Bước 3  [Phiên 1]  INSERT ... (buyer_id = 10);  COMMIT;  -- kết quả: INSERT 0 1
--   Bước 4  [Phiên 2]  tự chạy tiếp sau khi Phiên 1 COMMIT; chạy INSERT ... (buyer_id = 20);
--                      kết quả: INSERT 0 0 (đơn đã có, điều kiện NOT EXISTS không còn đúng)
--                      rồi COMMIT;
-- Kiểm chứng:  SELECT id, post_id, buyer_id, status FROM orders WHERE post_id = 500;
--              -> chỉ MỘT đơn; chỉ một phiên tạo được đơn, phiên còn lại nhận INSERT 0 0.

-- ---------------------------------------------------------------------
-- (c) Đặt lại trạng thái ban đầu và chạy lại (b) KHÔNG dùng FOR UPDATE
-- ---------------------------------------------------------------------
-- Đặt lại:      DELETE FROM orders WHERE post_id = 500;
-- Cả hai phiên chạy cùng trình tự như (b) nhưng BỎ dòng "SELECT ... FOR UPDATE":
--   Bước 1  [Phiên 1]  BEGIN;  INSERT INTO orders ... (buyer_id = 10);   -- INSERT 0 1, chưa COMMIT
--   Bước 2  [Phiên 2]  BEGIN;  INSERT INTO orders ... (buyer_id = 20);
--                      -- Phiên 2 KHÔNG thấy đơn chưa commit của Phiên 1 nên điều kiện NOT EXISTS đúng,
--                      -- nó cố INSERT và bị CHỜ vì chỉ mục duy nhất one_active_order_per_post
--   Bước 3  [Phiên 1]  COMMIT;
--   Bước 4  [Phiên 2]  nhận lỗi:
--        ERROR:  duplicate key value violates unique constraint "one_active_order_per_post"
--        DETAIL:  Key (post_id)=(500) already exists.
--                      rồi gõ COMMIT; -> PostgreSQL trả lời ROLLBACK (giao dịch đã lỗi nên không commit được)
-- Khác biệt về phía ứng dụng:
--   - Có FOR UPDATE: phiên thua cuộc KHÔNG gặp lỗi; nó chờ rồi nhận INSERT 0 0 (0 hàng được chèn),
--     ứng dụng chỉ cần kiểm tra số hàng chèn = 0 để báo "tin đã có người đặt".
--   - Không có FOR UPDATE: phiên thua cuộc nhận NGOẠI LỆ (mã lỗi 23505), COMMIT biến thành
--     ROLLBACK; ứng dụng phải bắt lỗi này (và thường phải chạy lại cả giao dịch) để báo cho người dùng.
--   Chỉ mục duy nhất vẫn đảm bảo không có hai đơn hoạt động trên một tin, nhưng FOR UPDATE cho
--   luồng xử lý gọn hơn, không phải dựa vào bắt lỗi.

-- #####################################################################
-- BÀI 4 (Nâng cao) — Tái hiện và phòng tránh deadlock
-- #####################################################################
-- Dùng hai tin A = 452 và B = 453.

-- (a) Tái hiện deadlock: phiên 1 UPDATE tin A rồi tin B; phiên 2 UPDATE tin B rồi tin A,
--     mỗi lệnh cách nhau một khoảng để kịp đan xen.
--   Bước 1  [Phiên 1]  BEGIN;  UPDATE posts SET price = price + 1 WHERE id = 452;   -- khóa tin A
--   Bước 2  [Phiên 2]  BEGIN;  UPDATE posts SET price = price + 1 WHERE id = 453;   -- khóa tin B
--   Bước 3  [Phiên 1]  UPDATE posts SET price = price + 1 WHERE id = 453;           -- chờ khóa B (Phiên 2 giữ)
--   Bước 4  [Phiên 2]  UPDATE posts SET price = price + 1 WHERE id = 452;           -- chờ khóa A (Phiên 1 giữ)
--   -> hai phiên chờ nhau thành vòng. Sau khoảng 1 giây (deadlock_timeout) PostgreSQL báo:
--        ERROR:  deadlock detected
--        DETAIL:  Process ... waits for ShareLock on transaction ...; blocked by process ...
--      và HỦY một phiên (nạn nhân); phiên còn lại tiếp tục chạy được. Gõ COMMIT; ở phiên còn lại.
--   Dọn dẹp:  ROLLBACK; ở phiên bị hủy.

-- (b) Viết lại: cả hai phiên cập nhật hai tin theo CÙNG THỨ TỰ id tăng dần (452 rồi 453)
--   Bước 1  [Phiên 1]  BEGIN;  UPDATE posts SET price = price + 1 WHERE id = 452;
--   Bước 2  [Phiên 2]  BEGIN;  UPDATE posts SET price = price + 1 WHERE id = 452;   -- chờ Phiên 1
--   Bước 3  [Phiên 1]  UPDATE posts SET price = price + 1 WHERE id = 453;  COMMIT;
--   Bước 4  [Phiên 2]  tự chạy tiếp; UPDATE posts SET price = price + 1 WHERE id = 453;  COMMIT;
--   -> không còn deadlock, cả hai phiên đều hoàn tất.
-- Giải thích: deadlock xảy ra khi có VÒNG CHỜ (Phiên 1 giữ A chờ B, Phiên 2 giữ B chờ A).
-- Nếu mọi giao dịch luôn khóa các hàng theo cùng một thứ tự (ví dụ id tăng dần), thì phiên nào
-- giành được hàng đầu tiên sẽ đi tiếp, phiên kia chỉ chờ ở hàng ĐẦU và chưa giữ khóa nào mà
-- phiên trước cần. Không bao giờ có hai phiên cùng giữ thứ người kia đang chờ, nên vòng chờ
-- không thể hình thành, và việc chờ chỉ là xếp hàng bình thường.
