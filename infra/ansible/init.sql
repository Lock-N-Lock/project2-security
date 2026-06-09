-- 테이블이 없을 경우 users 테이블 생성
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY, 
    username VARCHAR(50) UNIQUE NOT NULL, 
    password VARCHAR(255) NOT NULL, 
    account_number VARCHAR(20) UNIQUE NOT NULL, 
    balance BIGINT NOT NULL DEFAULT 0
);

-- 테이블이 없을 경우 transactions 테이블 생성 (users 테이블의 id를 참조)
CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY, 
    user_id INT REFERENCES users(id), 
    target_account VARCHAR(20) NOT NULL, 
    title VARCHAR(100) NOT NULL, 
    amount BIGINT NOT NULL, 
    created_at TIMESTAMP DEFAULT NOW()
);

-- users 샘플 데이터 5개 삽입 (중복 방지 설정)
INSERT INTO users (username, password, account_number, balance) VALUES
('user1', '$2b$12$eImiTXuWVxfM37uY4JANjOuh883gXhD.k06497B.jYtGgQ2yG', '1002-001', 100000),
('user2', '$2b$12$eImiTXuWVxfM37uY4JANjOuh883gXhD.k06497B.jYtGgQ2yG', '1002-002', 250000),
('user3', '$2b$12$eImiTXuWVxfM37uY4JANjOuh883gXhD.k06497B.jYtGgQ2yG', '1002-003', 50000),
('user4', '$2b$12$eImiTXuWVxfM37uY4JANjOuh883gXhD.k06497B.jYtGgQ2yG', '1002-004', 1200000),
('user5', '$2b$12$eImiTXuWVxfM37uY4JANjOuh883gXhD.k06497B.jYtGgQ2yG', '1002-005', 0),
('user6', '$2b$12$eImiTXuWVxfM37uY4JANjOuh883gXhD.k06497B.jYtGgQ2yG', '1002-006', 18900)
ON CONFLICT (username) DO NOTHING;

-- transactions 샘플 데이터 5개 삽입 (외래키 id 자동 조회를 위해 서브쿼리 사용)
INSERT INTO transactions (user_id, target_account, title, amount) VALUES
((SELECT id FROM users WHERE username='user1'), '1002-002', '송금', 10000),
((SELECT id FROM users WHERE username='user2'), '1002-003', '용돈', 50000),
((SELECT id FROM users WHERE username='user3'), '1002-004', '식비 정산', 15000),
((SELECT id FROM users WHERE username='user4'), '1002-001', '중고 물품 거래', 200000),
((SELECT id FROM users WHERE username='user1'), '1002-005', '커피 기프티콘', 5000);
