# デプロイメント & 動作確認ガイド

## 📋 確認項目チェックリスト

### ✅ 1. 地図が表示される

**確認手順:**
```bash
# 1. ローカルサーバーを起動
cd satellite-viewer
php -S localhost:8000

# 2. ブラウザでアクセス
# http://localhost:8000/frontend/index.html
```

**期待される動作:**
- ✅ Leaflet.js地図が表示される
- ✅ OpenStreetMapタイルが読み込まれる
- ✅ 初期表示: 日本全体が見える（ズームレベル5）
- ✅ 地図上でドラッグ・ズーム操作ができる

**トラブルシューティング:**
```javascript
// ブラウザのコンソールで確認
console.log('Leaflet version:', L.version);
console.log('Map object:', map);
```

---

### ✅ 2. マーカーが配置される

**前提条件:**
- データベースにサンプルデータが挿入されている
- backend/config.php が正しく設定されている

**確認手順:**
```sql
-- MySQLでデータ確認
mysql -u root -p satellite_viewer

SELECT COUNT(*) FROM locations;
SELECT COUNT(*) FROM observations;
```

**期待される動作:**
- ✅ API `/api.php?action=get_locations` が成功する
- ✅ 地点数に応じたマーカーが地図上に表示される
- ✅ マーカーの色がLST値に応じて変化する:
  - 青（< 10°C）
  - 緑（10-20°C）
  - 黄（20-30°C）
  - オレンジ（30-40°C）
  - 赤（> 40°C）
- ✅ マーカーに温度ラベルが表示される

**デバッグ:**
```javascript
// ブラウザコンソールで確認
console.log('Markers:', markers.length);
console.log('API URL:', API_BASE_URL);

// ネットワークタブで確認
// - Status: 200 OK
// - Response: JSON形式
// - Content-Type: application/json
```

---

### ✅ 3. ポップアップが動作する

**確認手順:**
1. 地図上のマーカーをクリック
2. ポップアップが表示される
3. 「詳細を表示」ボタンをクリック
4. データテーブルとグラフが表示される

**期待される動作:**
- ✅ マーカークリックでポップアップが開く
- ✅ ポップアップに以下が表示される:
  - 地点名
  - 都道府県・市区町村
  - 緯度・経度
  - 最新観測日
  - LST値（°C）
  - NDVI値
- ✅ 「詳細を表示」ボタンが機能する
- ✅ ポップアップを閉じることができる

**確認コード:**
```javascript
// コンソールで確認
console.log('Popup element:', document.querySelector('.leaflet-popup'));
```

---

### ✅ 4. スマホでも見やすい

**確認手順:**

#### デスクトップブラウザでレスポンシブ確認
1. Chrome DevToolsを開く（F12）
2. デバイスツールバーを表示（Ctrl+Shift+M）
3. 以下のデバイスで確認:
   - iPhone 12/13 Pro (390x844)
   - iPad (768x1024)
   - Galaxy S20 (360x800)

**期待される動作:**

#### スマートフォン (≤480px)
- ✅ サイドバーが上部に配置される
- ✅ フォームが縦並びになる
- ✅ 地図の高さが300pxに調整される
- ✅ ボタンが全幅になる
- ✅ テーブルが横スクロール可能
- ✅ フォントサイズが適切に調整される

#### タブレット (768px-1024px)
- ✅ サイドバーとメインが縦並び
- ✅ 地図の高さが400px
- ✅ カードレイアウトが維持される

#### デスクトップ (>1024px)
- ✅ サイドバー（300px固定）+ メイン（フレックス）
- ✅ 地図の高さが600px
- ✅ 2カラムレイアウト

**CSS確認:**
```css
/* Chrome DevToolsのElementsタブで確認 */
.main-container {
  /* デスクトップ */
  display: flex;
  flex-direction: row;

  /* モバイル */
  flex-direction: column;
}
```

---

## 🔧 完全な動作確認手順

### Step 1: データベースセットアップ

```bash
# データベース作成
mysql -u root -p < backend/db_setup.sql

# データ確認
mysql -u root -p satellite_viewer -e "
SELECT 'locations' AS table_name, COUNT(*) AS count FROM locations
UNION ALL
SELECT 'observations', COUNT(*) FROM observations
UNION ALL
SELECT 'climate_normals', COUNT(*) FROM climate_normals;
"
```

**期待される出力:**
```
+-----------------+-------+
| table_name      | count |
+-----------------+-------+
| locations       |     1 |
| observations    |     7 |
| climate_normals |    12 |
+-----------------+-------+
```

---

### Step 2: バックエンド設定確認

```bash
# config.phpが存在するか確認
ls -la backend/config.php

# config.phpの内容確認（パスワードは隠す）
grep -E "^define\('DB_" backend/config.php
```

**期待される出力:**
```php
define('DB_HOST', 'localhost');
define('DB_USER', 'root');
define('DB_PASS', 'your_password_here');
define('DB_NAME', 'satellite_viewer');
```

---

### Step 3: APIテスト

```bash
# PHPテストスクリプト実行
php backend/test_api.php
```

**期待される出力:**
```
======================================================================
1. 設定ファイルの確認
======================================================================
✓ PASS: config.php が存在します
✓ PASS: データベース接続成功
✓ PASS: テーブル 'locations' が存在します
✓ PASS: テーブル 'observations' が存在します
✓ PASS: テーブル 'climate_normals' が存在します
...
```

**curlテスト:**
```bash
# 観測地点一覧取得
curl -s "http://localhost:8000/backend/api.php?action=get_locations" | python -m json.tool
```

**期待されるJSON:**
```json
{
  "success": true,
  "data": [
    {
      "id": "1",
      "name": "Nanaka Farm",
      "latitude": "32.8032000",
      "longitude": "130.7075000",
      ...
    }
  ],
  "message": "1件の観測地点が見つかりました",
  "timestamp": "2026-01-15T10:30:00+09:00"
}
```

---

### Step 4: フロントエンド起動

```bash
# PHPビルトインサーバー起動
cd satellite-viewer
php -S localhost:8000
```

**ブラウザでアクセス:**
```
http://localhost:8000/frontend/index.html
```

**確認項目:**
1. ヘッダーが表示される
2. サイドバーが左に表示される
3. 地図が中央に表示される
4. フッターが下部に表示される

---

### Step 5: ブラウザコンソール確認

**期待されるログ:**
```javascript
✓ アプリケーションを初期化しました
✓ 地図を初期化しました
✓ Map モジュールを初期化しました
📡 観測地点データを取得中...
✓ 1件の観測地点を取得しました
```

**エラーがある場合:**
```javascript
// CORS エラー
// → backend/config.php で CORS を有効化

// 404 エラー
// → API URLが正しいか確認
// → Webサーバーのドキュメントルートを確認

// データベース接続エラー
// → backend/config.php の設定を確認
```

---

### Step 6: 機能テスト

#### 6.1 地点追加
1. サイドバーのフォームに入力:
   - 地点名: "Test Farm"
   - 緯度: 35.6812
   - 経度: 139.7671
   - 都道府県: "東京都"
2. 「地点を追加」をクリック
3. 成功モーダルが表示される
4. 地図が更新され、新しいマーカーが表示される

#### 6.2 マーカークリック
1. 地図上のマーカーをクリック
2. ポップアップが表示される
3. 「詳細を表示」をクリック
4. データテーブルが更新される
5. グラフが表示される

#### 6.3 CSVエクスポート
1. 「CSVエクスポート」ボタンをクリック
2. CSVファイルがダウンロードされる
3. Excelで開いて確認

---

### Step 7: レスポンシブテスト

**Chrome DevTools:**
1. F12でDevToolsを開く
2. Ctrl+Shift+M でデバイスツールバー表示
3. 以下のデバイスで確認:

```
iPhone SE (375x667)
→ サイドバーが上部、地図が小さく表示

iPad (768x1024)
→ サイドバーとメインが縦並び

Desktop (1920x1080)
→ サイドバー300px + メイン
```

---

## 🐛 トラブルシューティング

### 地図が表示されない

**原因1: Leaflet.jsが読み込まれていない**
```javascript
// コンソールで確認
typeof L
// → "undefined" の場合、CDNが読み込まれていない
```

**解決策:**
- インターネット接続を確認
- CDN URLが正しいか確認

**原因2: 地図コンテナの高さが0**
```css
/* style.css で確認 */
.map-container {
  height: 600px; /* この値があるか確認 */
}
```

---

### マーカーが表示されない

**原因1: APIエラー**
```bash
# ログファイル確認
cat backend/logs/$(date +%Y-%m-%d).log | grep ERROR
```

**原因2: データなし**
```sql
-- データベース確認
SELECT * FROM locations;
SELECT * FROM observations;
```

**原因3: JavaScript エラー**
```javascript
// コンソールで確認
markers.length
// → 0 の場合、マーカーが作成されていない
```

---

### ポップアップが表示されない

**確認:**
```javascript
// マーカーにポップアップがバインドされているか
markers[0]._popup
// → Popup オブジェクトが返されればOK
```

---

### スマホで崩れる

**確認:**
```html
<!-- index.html に viewport タグがあるか -->
<meta name="viewport" content="width=device-width, initial-scale=1.0">
```

**CSS メディアクエリ確認:**
```css
@media (max-width: 768px) {
  .main-container {
    flex-direction: column;
  }
}
```

---

## 📊 パフォーマンスチェック

### ページ読み込み速度

**Chrome DevTools > Network:**
- 地図タイル: < 500ms
- API呼び出し: < 200ms
- 合計: < 2秒

### メモリ使用量

**Chrome DevTools > Memory:**
- ページ読み込み後: < 50MB
- マーカー100個: < 100MB

---

## ✅ 最終チェックリスト

```
□ データベースが作成されている
□ サンプルデータが挿入されている
□ config.php が設定されている
□ APIテストが成功する
□ 地図が表示される
□ マーカーが配置される
□ マーカーの色が正しい
□ ポップアップが動作する
□ 詳細表示ボタンが機能する
□ データテーブルが更新される
□ グラフが表示される
□ 地点追加フォームが動作する
□ CSVエクスポートが動作する
□ スマホで見やすい（375px）
□ タブレットで見やすい（768px）
□ デスクトップで見やすい（1920px）
□ ログファイルにエラーがない
□ ブラウザコンソールにエラーがない
```

---

## 🚀 本番環境デプロイ前チェック

```bash
# 1. エラー表示をOFFにする
# backend/config.php
error_reporting(0);
ini_set('display_errors', 0);

# 2. CORS設定を本番ドメインに限定
# backend/config.php
define('ALLOW_CORS', true);
define('CORS_ORIGIN', 'https://your-domain.com');

# 3. パスを本番環境に変更
# frontend/js/app.js, map.js
const API_BASE_URL = 'https://your-domain.com/backend/api.php';

# 4. HTTPSを有効化
# Webサーバー設定でSSL証明書を設定
```

---

すべての確認項目がパスすれば、デプロイ準備完了です! 🎉
