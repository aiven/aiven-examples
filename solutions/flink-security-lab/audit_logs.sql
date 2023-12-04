CREATE TABLE audit_logs (
    user_id INT PRIMARY KEY,
    login_attempts BIGINT NOT NULL,
    distinct_ips BIGINT NOT NULL,
    time_since_last_login VARCHAR(255)
);
