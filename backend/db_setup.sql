-- Satellite Data Viewer Database Setup
-- データベース作成と選択

CREATE DATABASE IF NOT EXISTS satellite_viewer CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE satellite_viewer;

-- ====================
-- テーブル削除（再作成用）
-- ====================

DROP TABLE IF EXISTS observations;
DROP TABLE IF EXISTS climate_normals;
DROP TABLE IF EXISTS locations;

-- ====================
-- 1. locations テーブル（観測地点）
-- ====================

CREATE TABLE locations (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    latitude DECIMAL(10, 7) NOT NULL,
    longitude DECIMAL(11, 7) NOT NULL,
    prefecture VARCHAR(50),
    city VARCHAR(100),
    nearest_station_id VARCHAR(10),
    nearest_station_name VARCHAR(100),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ====================
-- 2. observations テーブル（衛星観測データ）
-- ====================

CREATE TABLE observations (
    id INT PRIMARY KEY AUTO_INCREMENT,
    location_id INT NOT NULL,
    observation_date DATE NOT NULL,
    lst DECIMAL(5, 2) COMMENT '地表面温度（℃）',
    ndvi DECIMAL(5, 3) COMMENT '植生指標（0-1）',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE,
    INDEX idx_location_date (location_id, observation_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ====================
-- 3. climate_normals テーブル（気象庁平年値）
-- ====================

CREATE TABLE climate_normals (
    id INT PRIMARY KEY AUTO_INCREMENT,
    station_id VARCHAR(10) NOT NULL,
    station_name VARCHAR(100) NOT NULL,
    month INT NOT NULL COMMENT '月（1-12）',
    avg_temp DECIMAL(4, 1) COMMENT '平均気温（℃）',
    max_temp DECIMAL(4, 1) COMMENT '最高気温（℃）',
    min_temp DECIMAL(4, 1) COMMENT '最低気温（℃）',
    precipitation DECIMAL(6, 1) COMMENT '降水量（mm）',
    UNIQUE KEY unique_station_month (station_id, month)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ====================
-- サンプルデータ挿入
-- ====================

-- locations: Nanaka Farm（熊本県山鹿市）
INSERT INTO locations (name, latitude, longitude, prefecture, city, nearest_station_id, nearest_station_name)
VALUES ('Nanaka Farm', 32.8032000, 130.7075000, '熊本県', '山鹿市', '86', '熊本');

-- observations: 2026-01-08以降の7日分のサンプルデータ
INSERT INTO observations (location_id, observation_date, lst, ndvi) VALUES
(1, '2026-01-08', 18.23, 0.745),
(1, '2026-01-09', 19.15, 0.752),
(1, '2026-01-10', 18.87, 0.748),
(1, '2026-01-11', 19.54, 0.756),
(1, '2026-01-12', 18.66, 0.743),
(1, '2026-01-13', 19.92, 0.761),
(1, '2026-01-14', 20.18, 0.758);

-- climate_normals: 熊本（station_id=86）の12ヶ月分の平年値
-- 参考: 気象庁の平年値データ（1991-2020年）
INSERT INTO climate_normals (station_id, station_name, month, avg_temp, max_temp, min_temp, precipitation) VALUES
('86', '熊本', 1, 6.5, 10.9, 2.4, 77.0),
('86', '熊本', 2, 7.9, 12.5, 3.6, 99.1),
('86', '熊本', 3, 11.4, 16.2, 6.9, 142.8),
('86', '熊本', 4, 16.2, 21.4, 11.4, 163.7),
('86', '熊本', 5, 20.7, 25.9, 16.1, 193.8),
('86', '熊本', 6, 24.3, 28.8, 20.5, 449.9),
('86', '熊本', 7, 28.1, 32.6, 24.4, 404.3),
('86', '熊本', 8, 28.7, 33.4, 24.8, 232.4),
('86', '熊本', 9, 24.9, 29.5, 20.9, 212.0),
('86', '熊本', 10, 19.0, 24.0, 14.5, 109.5),
('86', '熊本', 11, 13.1, 18.1, 8.5, 90.7),
('86', '熊本', 12, 8.3, 12.9, 4.1, 66.2);

-- ====================
-- 気象観測所マスターテーブル
-- ====================

CREATE TABLE IF NOT EXISTS weather_stations (
    id INT PRIMARY KEY AUTO_INCREMENT,
    station_id VARCHAR(10) UNIQUE NOT NULL COMMENT '観測所ID（気象庁コード）',
    station_name VARCHAR(100) NOT NULL COMMENT '観測所名',
    latitude DECIMAL(10, 7) NOT NULL COMMENT '緯度',
    longitude DECIMAL(11, 7) NOT NULL COMMENT '経度',
    prefecture VARCHAR(50) COMMENT '都道府県',
    elevation INT COMMENT '標高（m）',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_station_id (station_id),
    INDEX idx_coordinates (latitude, longitude)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='気象観測所マスター';

-- 九州地方の主要観測所
INSERT INTO weather_stations (station_id, station_name, latitude, longitude, prefecture, elevation) VALUES
('82', '福岡', 33.5819, 130.3778, '福岡県', 3),
('84', '佐賀', 33.2497, 130.3008, '佐賀県', 6),
('85', '長崎', 32.7333, 129.8667, '長崎県', 27),
('86', '熊本', 32.8136, 130.7056, '熊本県', 38),
('87', '大分', 33.2381, 131.6125, '大分県', 5),
('88', '宮崎', 31.9405, 131.4193, '宮崎県', 9),
('89', '鹿児島', 31.5572, 130.5578, '鹿児島県', 4);

-- 本州・四国の主要観測所
INSERT INTO weather_stations (station_id, station_name, latitude, longitude, prefecture, elevation) VALUES
('44', '東京', 35.6895, 139.6917, '東京都', 25),
('47', '横浜', 35.4397, 139.6519, '神奈川県', 39),
('50', '名古屋', 35.1667, 136.9333, '愛知県', 51),
('62', '大阪', 34.6867, 135.5200, '大阪府', 23),
('67', '神戸', 34.6906, 135.1961, '兵庫県', 36),
('73', '広島', 34.3947, 132.4597, '広島県', 3),
('74', '岡山', 34.6614, 133.9181, '岡山県', 2),
('71', '松山', 33.8394, 132.7656, '愛媛県', 32);

-- 北海道・東北の主要観測所
INSERT INTO weather_stations (station_id, station_name, latitude, longitude, prefecture, elevation) VALUES
('14', '札幌', 43.0642, 141.3469, '北海道', 17),
('17', '旭川', 43.7708, 142.3653, '北海道', 112),
('31', '青森', 40.8244, 140.7400, '青森県', 3),
('32', '秋田', 39.7181, 140.1028, '秋田県', 6),
('34', '仙台', 38.2686, 140.8719, '宮城県', 39),
('35', '山形', 38.2544, 140.3397, '山形県', 152);

-- ====================
-- データ確認用クエリ
-- ====================

-- テーブル一覧確認
SHOW TABLES;

-- 各テーブルのレコード数確認
SELECT 'locations' AS table_name, COUNT(*) AS record_count FROM locations
UNION ALL
SELECT 'observations', COUNT(*) FROM observations
UNION ALL
SELECT 'climate_normals', COUNT(*) FROM climate_normals
UNION ALL
SELECT 'weather_stations', COUNT(*) FROM weather_stations;

-- サンプルデータ確認
SELECT
    l.name AS location_name,
    o.observation_date,
    o.lst,
    o.ndvi,
    l.nearest_station_name
FROM observations o
JOIN locations l ON o.location_id = l.id
ORDER BY o.observation_date;

-- 平年値データ確認（1月のみ）
SELECT
    station_name,
    month,
    avg_temp,
    max_temp,
    min_temp,
    precipitation
FROM climate_normals
WHERE month = 1;
