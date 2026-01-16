# 🛰️ Satellite Data Viewer

[![GitHub](https://img.shields.io/badge/GitHub-satellite--data--viewer-blue?logo=github)](https://github.com/hiroAkikoDy/satellite-data-viewer)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PHP](https://img.shields.io/badge/PHP-8.x-777BB4?logo=php)](https://www.php.net/)
[![MySQL](https://img.shields.io/badge/MySQL-8.x-4479A1?logo=mysql&logoColor=white)](https://www.mysql.com/)

JAXA衛星データ（GCOM-C/SGLI）と気象庁平年値を統合し、農地の観測データを可視化するWebアプリケーション

## 📋 目次

- [機能概要](#機能概要)
- [システム構成](#システム構成)
- [セットアップ](#セットアップ)
- [使用方法](#使用方法)
- [API仕様](#api仕様)
- [開発](#開発)

## 🌟 機能概要

### 1. 衛星データ収集
- JAXA G-Portal APIから地表面温度（LST）と植生指標（NDVI）を取得
- HDF5形式のデータを解析してピクセル値を抽出
- 自動的にKelvinから摂氏に変換

### 2. 気象庁平年値との比較
- 最寄りの観測所の月別平年値を取得
- 衛星観測値と平年値の偏差を計算
- 温度異常の検出

### 3. データ可視化
- 観測地点の管理
- 時系列データの表示
- CSVエクスポート機能

## 🏗️ システム構成

```
satellite-viewer/
├── backend/              # PHPバックエンド
│   ├── config.php       # データベース接続設定（Gitにコミットされない）
│   ├── config.php.example  # 設定ファイルのサンプル
│   ├── api.php          # RESTful APIエンドポイント
│   ├── db_setup.sql     # データベース初期化SQL
│   ├── import_jma.php   # 気象庁平年値インポート
│   ├── logs/            # APIログ（自動生成）
│   └── test_api.php     # APIテストスクリプト
├── frontend/            # フロントエンド
│   ├── index.html
│   ├── css/
│   └── js/
├── scripts/             # Pythonスクリプト
│   ├── collect_data.py  # 衛星データ収集
│   └── upload_to_mysql.py  # MySQLアップロード
├── data/               # データ保存ディレクトリ
│   ├── jma_normals/    # 気象庁平年値CSV
│   ├── jaxa_downloads/ # JAXA衛星データ
│   └── backup/         # バックアップCSV
└── .env                # 環境変数（Gitにコミットされない）
```

## 🚀 セットアップ

### 1. 前提条件

- **PHP**: 7.4以上（PDO、MySQLサポート必須）
- **MySQL**: 5.7以上 または MariaDB 10.2以上
- **Python**: 3.8以上
- **Webサーバー**: Apache または Nginx

### 2. データベースセットアップ

```bash
# MySQLにログイン
mysql -u root -p

# データベースとテーブルを作成
mysql -u root -p < backend/db_setup.sql
```

### 3. バックエンド設定

```bash
# 設定ファイルをコピー
cp backend/config.php.example backend/config.php

# config.php を編集してMySQL接続情報を設定
# - DB_HOST: データベースホスト
# - DB_USER: データベースユーザー名
# - DB_PASS: データベースパスワード
# - DB_NAME: データベース名
```

### 4. Python環境セットアップ

```bash
# 必須ライブラリのインストール
pip install python-dotenv pymysql numpy h5py

# JAXA G-Portal API使用時（オプション）
pip install gportal
```

### 5. 環境変数設定

```bash
# .env ファイルを作成
cp .env.example .env

# .env を編集して以下を設定:
# - MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE
# - GPORTAL_USERNAME, GPORTAL_PASSWORD（G-Portal API使用時）
```

### 6. 動作確認

```bash
# PHPテストスクリプト実行
php backend/test_api.php

# curlテスト実行（オプション）
chmod +x backend/test_api.sh
./backend/test_api.sh
```

## 📖 使用方法

### データ収集ワークフロー

#### 1. 衛星データ収集

```bash
# モックモードでテスト
python scripts/collect_data.py \
  --lat 32.8032 \
  --lon 130.7075 \
  --date 2026-01-08 \
  --output data/output.json \
  --mock

# 実APIで取得（G-Portal認証必要）
python scripts/collect_data.py \
  --lat 32.8032 \
  --lon 130.7075 \
  --date 2026-01-08 \
  --output data/output.json
```

#### 2. MySQLにアップロード

```bash
# データベースにアップロード
python scripts/upload_to_mysql.py \
  --input data/output.json \
  --location-id 1

# CSVバックアップのみ保存
python scripts/upload_to_mysql.py \
  --input data/output.json \
  --location-id 1 \
  --backup-only
```

#### 3. 気象庁平年値インポート

```bash
# CSVファイルを data/jma_normals/ に配置
# インポート実行
php backend/import_jma.php
```

### APIエンドポイント使用例

#### 観測地点一覧取得

```bash
curl http://localhost/backend/api.php?action=get_locations
```

#### 観測データ取得（過去30日分）

```bash
curl "http://localhost/backend/api.php?action=get_observations&location_id=1&days=30"
```

#### 平年値との比較

```bash
curl "http://localhost/backend/api.php?action=get_comparison&location_id=1&date=2026-01-08"
```

#### 新規観測地点追加

```bash
curl -X POST http://localhost/backend/api.php?action=add_location \
  -H "Content-Type: application/json" \
  -d '{
    "name": "新しい農場",
    "latitude": 35.6812,
    "longitude": 139.7671,
    "prefecture": "東京都",
    "city": "千代田区"
  }'
```

#### CSVエクスポート

```bash
curl "http://localhost/backend/api.php?action=export_csv&location_id=1" > observations.csv
```

## 📚 API仕様

### エンドポイント一覧

| メソッド | エンドポイント | 説明 |
|---------|---------------|------|
| GET | `/api.php?action=get_locations` | 観測地点一覧取得 |
| GET | `/api.php?action=get_observations&location_id={id}&days={n}` | 観測データ取得 |
| GET | `/api.php?action=get_comparison&location_id={id}&date={YYYY-MM-DD}` | 平年値比較 |
| POST | `/api.php?action=add_location` | 観測地点追加 |
| GET | `/api.php?action=export_csv&location_id={id}` | CSVエクスポート |

### レスポンス形式

#### 成功時

```json
{
  "success": true,
  "data": { ... },
  "message": "処理成功メッセージ",
  "timestamp": "2026-01-15T10:30:00+09:00"
}
```

#### エラー時

```json
{
  "success": false,
  "error": "エラーメッセージ",
  "timestamp": "2026-01-15T10:30:00+09:00"
}
```

## 🔧 開発

### ログ確認

```bash
# 今日のログを表示
tail -f backend/logs/$(date +%Y-%m-%d).log

# エラーログのみ抽出
grep "ERROR" backend/logs/$(date +%Y-%m-%d).log
```

### データベーステーブル構造

#### locations（観測地点）
- `id`: 地点ID（主キー）
- `name`: 地点名
- `latitude`: 緯度
- `longitude`: 経度
- `prefecture`: 都道府県
- `city`: 市区町村
- `nearest_station_id`: 最寄り観測所ID
- `nearest_station_name`: 最寄り観測所名

#### observations（衛星観測データ）
- `id`: 観測ID（主キー）
- `location_id`: 地点ID（外部キー）
- `observation_date`: 観測日
- `lst`: 地表面温度（℃）
- `ndvi`: 植生指標（0-1）

#### climate_normals（気象庁平年値）
- `id`: ID（主キー）
- `station_id`: 観測所ID
- `station_name`: 観測所名
- `month`: 月（1-12）
- `avg_temp`: 平均気温（℃）
- `max_temp`: 最高気温（℃）
- `min_temp`: 最低気温（℃）
- `precipitation`: 降水量（mm）

### セキュリティ

- **config.php**: データベース認証情報を含む（.gitignoreで除外）
- **.env**: API認証情報を含む（.gitignoreで除外）
- **logs/**: APIアクセスログ（.gitignoreで除外）
- **data/**: ダウンロードデータ（.gitignoreで除外）

## 🧪 テスト

### セキュリティテスト

#### SQLインジェクション対策テスト

```bash
# テスト: 緯度に SQL インジェクションを試行
# 期待結果: エラーメッセージが返され、SQLが実行されない
curl -X POST http://localhost/backend/api.php?action=add_location \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test",
    "latitude": "32.8032'\'' OR '\''1'\''='\''1",
    "longitude": 130.7075
  }'
```

**✅ 合格条件**: プリペアドステートメント使用により、SQLインジェクションが防止される

#### XSS（クロスサイトスクリプティング）対策テスト

```bash
# テスト: 地点名にスクリプトタグを挿入
# 期待結果: スクリプトがエスケープされ、実行されない
curl -X POST http://localhost/backend/api.php?action=add_location \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<script>alert('\''XSS'\'')</script>",
    "latitude": 35.6812,
    "longitude": 139.7671
  }'
```

**✅ 合格条件**: ブラウザでアラートが表示されず、タグがエスケープされて表示される

#### 認証情報保護確認

```bash
# .gitignore に含まれているか確認
grep -E "config.php|\.env|logs/|data/" .gitignore

# 機密ファイルがGit管理されていないか確認
git ls-files | grep -E "config.php|\.env"
```

**✅ 合格条件**: 機密ファイルが `.gitignore` に含まれ、Git管理外になっている

### パフォーマンステスト

#### データベースクエリ最適化確認

```sql
-- INDEX が設定されているか確認
SHOW INDEX FROM locations;
SHOW INDEX FROM observations;
SHOW INDEX FROM climate_normals;

-- 実行計画を確認（N+1問題の検出）
EXPLAIN SELECT * FROM observations WHERE location_id = 1 ORDER BY observation_date DESC;
```

**✅ 合格条件**:
- `location_id`, `observation_date` にINDEXが設定されている
- EXPLAIN結果で `type` が `ALL` (フルスキャン) になっていない

#### APIレスポンス速度測定

```bash
# 観測データ取得の速度測定
time curl -s "http://localhost/backend/api.php?action=get_observations&location_id=1&days=30" > /dev/null

# 比較データ取得の速度測定
time curl -s "http://localhost/backend/api.php?action=get_comparison&location_id=1&date=2026-01-08" > /dev/null
```

**✅ 合格条件**: 各APIリクエストが1秒以内に完了する

#### ページ読み込み速度確認

ブラウザの開発者ツール → Network タブで確認:
- 初回ページ読み込み: 3秒以内
- 地図表示: 2秒以内
- グラフ描画: 1秒以内

### アクセシビリティテスト

#### キーボード操作テスト

```
1. Tab キーでフォーカス移動できるか
2. Enter キーでボタンが押せるか
3. Esc キーでモーダルが閉じられるか
```

**✅ 合格条件**: キーボードのみで全機能が操作可能

#### スクリーンリーダー対応確認

```html
<!-- 画像に alt 属性があるか -->
<img src="..." alt="説明文">

<!-- ボタンに aria-label があるか -->
<button aria-label="地点を追加">+</button>
```

**✅ 合格条件**: 主要な要素に適切な `alt` / `aria-label` が設定されている

## 🔧 トラブルシューティング

### よくあるエラーと解決方法

#### 1. データベース接続エラー

**エラーメッセージ:**
```
SQLSTATE[HY000] [2002] Connection refused
```

**原因:**
- MySQLサービスが起動していない
- `config.php` の設定が間違っている

**解決方法:**
```bash
# MySQLサービスの状態確認
sudo systemctl status mysql

# MySQLサービスを起動
sudo systemctl start mysql

# config.php の設定を確認
cat backend/config.php

# データベース接続をテスト
mysql -u root -p satellite_viewer
```

#### 2. JavaScript エラー: API_BASE_URL が定義されていない

**エラーメッセージ:**
```
Uncaught ReferenceError: API_BASE_URL is not defined
```

**原因:**
- `app.js` より先に `map.js` や `chart.js` が読み込まれている
- スクリプトの読み込み順序が間違っている

**解決方法:**
```html
<!-- index.html のスクリプト読み込み順序を確認 -->
<script src="js/app.js"></script>    <!-- 1番目: 共通定数 -->
<script src="js/map.js"></script>    <!-- 2番目 -->
<script src="js/chart.js"></script>  <!-- 3番目 -->
```

#### 3. 平年値が NaN で表示される

**エラーメッセージ:**
```
数値変換エラー: { lst: "9.8", climate_avg: undefined, diff: undefined }
```

**原因:**
- APIレスポンスのデータ構造が間違っている
- `data.climate_avg_temp` ではなく `data.climate_normal.avg_temp` が正しい

**解決方法:**
```javascript
// chart.js で正しいパスを使用
const climateAvg = compResult.data.climate_normal
    ? parseFloat(compResult.data.climate_normal.avg_temp)
    : null;
```

**APIレスポンス確認:**
```bash
curl "http://localhost/backend/api.php?action=get_comparison&location_id=1&date=2026-01-08" | jq
```

#### 4. CSVエクスポートで文字化け

**原因:**
- BOMが付いていない
- エンコーディングが UTF-8 ではない

**解決方法:**
```php
// backend/api.php で BOM を出力
echo "\xEF\xBB\xBF";  // UTF-8 BOM
```

**確認:**
```bash
# BOM が含まれているか確認
hexdump -C observations.csv | head -n 1
# 出力: 00000000  ef bb bf ... (先頭に EF BB BF があればOK)
```

#### 5. 地図が表示されない

**エラーメッセージ:**
```
Uncaught TypeError: map.addLayer is not a function
```

**原因:**
- Leaflet.js が読み込まれていない
- CDNがブロックされている

**解決方法:**
```html
<!-- index.html で Leaflet.js のCDN を確認 -->
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
```

**ネットワーク確認:**
```bash
# CDNにアクセスできるか確認
curl -I https://unpkg.com/leaflet@1.9.4/dist/leaflet.js
```

#### 6. グラフが描画されない

**エラーメッセージ:**
```
Uncaught ReferenceError: Chart is not defined
```

**原因:**
- Chart.js が読み込まれていない
- Canvas要素が見つからない

**解決方法:**
```html
<!-- Chart.js のCDN を確認 -->
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

<!-- Canvas要素が存在するか確認 -->
<canvas id="dataChart" width="800" height="400"></canvas>
<canvas id="comparisonChart"></canvas>
```

**コンソールで確認:**
```javascript
console.log(typeof Chart);  // "function" と表示されればOK
console.log(document.getElementById('dataChart'));  // null でなければOK
```

#### 7. 観測所が自動検出されない

**原因:**
- `weather_stations` テーブルにデータがない
- Haversine公式のSQL構文エラー

**解決方法:**
```sql
-- weather_stations テーブルにデータがあるか確認
SELECT COUNT(*) FROM weather_stations;

-- 最寄り観測所を手動検索してテスト
SELECT
    station_id,
    station_name,
    (
        6371 * acos(
            cos(radians(32.8032)) * cos(radians(latitude)) *
            cos(radians(longitude) - radians(130.7075)) +
            sin(radians(32.8032)) * sin(radians(latitude))
        )
    ) AS distance_km
FROM weather_stations
ORDER BY distance_km ASC
LIMIT 1;
```

#### 8. バリデーションエラーが表示されない

**原因:**
- エラー表示要素が存在しない
- `showErrors()` 関数が呼ばれていない

**解決方法:**
```html
<!-- index.html にエラー表示領域があるか確認 -->
<div id="validation-errors" class="validation-errors" style="display: none;"></div>
```

```javascript
// app.js でバリデーションが実行されているか確認
const errors = validateLocation(name, latitude, longitude);
if (errors.length > 0) {
    showErrors(errors);  // この行が実行されているか確認
    return;
}
```

#### 9. ログファイルに書き込めない

**エラーメッセージ:**
```
Warning: fopen(/path/to/logs/2026-01-16.log): failed to open stream: Permission denied
```

**原因:**
- ログディレクトリの書き込み権限がない

**解決方法:**
```bash
# ログディレクトリの権限を確認
ls -ld backend/logs/

# 書き込み権限を付与
chmod 755 backend/logs/

# Webサーバーユーザーに所有権を変更
sudo chown -R www-data:www-data backend/logs/
```

#### 10. CORS エラー

**エラーメッセージ:**
```
Access to XMLHttpRequest at 'http://localhost/backend/api.php' from origin 'http://localhost:3000' has been blocked by CORS policy
```

**原因:**
- 異なるポートからAPIにアクセスしている
- CORS ヘッダーが設定されていない

**解決方法:**
```php
// backend/config.php で CORS ヘッダーを追加（開発環境のみ）
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
```

**注意:** 本番環境では `*` ではなく、特定のオリジンを指定してください。

### データベース接続エラー（詳細）

```bash
# config.php の設定を確認
cat backend/config.php

# MySQLサービスの状態確認
sudo systemctl status mysql
```

#### ログファイルが作成されない
```bash
# ログディレクトリの権限確認
ls -la backend/logs/

# 権限変更
chmod 755 backend/logs/
```

#### Python依存ライブラリエラー
```bash
# 仮想環境を使用
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## 📄 ライセンス

このプロジェクトはMITライセンスの下で公開されています。

## 🙏 謝辞

- **JAXA G-Portal**: 衛星データ提供
- **気象庁**: 平年値データ提供

## 📧 お問い合わせ

問題や質問がある場合は、[GitHubのIssuesページ](https://github.com/hiroAkikoDy/satellite-data-viewer/issues)でお知らせください。

## 🔗 リンク

- **GitHubリポジトリ**: https://github.com/hiroAkikoDy/satellite-data-viewer
- **セキュリティチェックリスト**: [SECURITY_CHECKLIST.md](SECURITY_CHECKLIST.md)
- **デプロイメントガイド**: [DEPLOYMENT.md](DEPLOYMENT.md)

---

**開発**: Koga Hiroaki with Claude Sonnet 4.5
**バージョン**: 1.0.0
**最終更新**: 2026-01-16
