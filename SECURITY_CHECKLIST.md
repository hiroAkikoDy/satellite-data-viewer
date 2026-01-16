# セキュリティチェックリスト

このドキュメントは、Satellite Data Viewerのセキュリティ対策と検証項目をまとめたものです。

## ✅ 実装済みのセキュリティ対策

### 1. SQLインジェクション対策

#### 実装内容
- すべてのSQLクエリでプリペアドステートメントを使用
- ユーザー入力を直接SQLに埋め込まない
- PDOのバインドパラメータを使用

#### 検証コード
```php
// backend/api.php の例
$sql = "SELECT * FROM locations WHERE id = :id";
$stmt = $pdo->prepare($sql);
$stmt->bindParam(':id', $locationId, PDO::PARAM_INT);
$stmt->execute();
```

#### テスト方法
```bash
# 悪意のある入力をテスト
curl -X POST http://localhost/backend/api.php?action=add_location \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test",
    "latitude": "32.8032'\'' OR '\''1'\''='\''1",
    "longitude": 130.7075
  }'
```

**✅ 期待結果**: エラーメッセージが返され、SQLが実行されない

---

### 2. XSS（クロスサイトスクリプティング）対策

#### 実装内容
- ユーザー入力を表示する際、適切にエスケープ
- JavaScriptでは`textContent`を使用（`innerHTML`は検証済みデータのみ）
- PHPでは`htmlspecialchars()`を使用（必要に応じて）

#### 検証コード
```javascript
// frontend/js/map.js の例
element.textContent = location.name;  // 安全
// element.innerHTML = location.name;  // 危険
```

#### テスト方法
```bash
# スクリプトタグを含む地点名を登録
curl -X POST http://localhost/backend/api.php?action=add_location \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<script>alert(\"XSS\")</script>",
    "latitude": 35.6812,
    "longitude": 139.7671
  }'
```

**✅ 期待結果**: アラートが表示されず、タグがエスケープされて表示される

---

### 3. 認証情報保護

#### 実装内容
- `.gitignore`で機密ファイルを除外
  - `backend/config.php`
  - `.env`
  - `backend/logs/`
  - `data/`
- 設定ファイルの外部公開防止

#### 検証
```bash
# .gitignore に含まれているか確認
grep -E "config.php|\.env|logs/|data/" .gitignore

# Git管理されていないか確認
git ls-files | grep -E "config.php|\.env"
```

**✅ 期待結果**: 機密ファイルがGit管理外になっている

---

### 4. CSRF対策（今後実装予定）

#### 現在の状態
❌ **未実装** - v1.1で実装予定

#### 実装方針
```php
// セッション開始時にトークン生成
session_start();
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

// POSTリクエスト時にトークン検証
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $token = $_POST['csrf_token'] ?? '';
    if (!hash_equals($_SESSION['csrf_token'], $token)) {
        sendErrorResponse('CSRF token validation failed', 403);
    }
}
```

---

### 5. エラーメッセージの適切な処理

#### 実装内容
- データベースエラーの詳細を外部に漏らさない
- ログファイルに詳細を記録
- ユーザーには一般的なエラーメッセージのみ表示

#### 検証コード
```php
// backend/api.php の例
try {
    // データベース処理
} catch (PDOException $e) {
    writeLog('ERROR', 'データベースエラー', [
        'error' => $e->getMessage(),  // ログには詳細を記録
        'trace' => $e->getTraceAsString()
    ]);
    sendErrorResponse('データベースエラーが発生しました', 500);  // ユーザーには簡潔に
}
```

**✅ 実装済み**: すべてのAPI関数で実装

---

### 6. ファイルアップロード対策（今後実装予定）

#### 現在の状態
❌ **未実装** - ファイルアップロード機能なし

#### 実装時の方針
- アップロード可能なファイル形式を制限（CSV, JSON のみ）
- ファイルサイズ制限（最大10MB）
- MIME typeの検証
- ファイル名のサニタイズ
- 実行可能ファイルのアップロード禁止

```php
$allowed_types = ['text/csv', 'application/json'];
$max_size = 10 * 1024 * 1024;  // 10MB

if (!in_array($_FILES['file']['type'], $allowed_types)) {
    sendErrorResponse('Invalid file type', 400);
}

if ($_FILES['file']['size'] > $max_size) {
    sendErrorResponse('File too large', 400);
}
```

---

## 🔍 パフォーマンス最適化

### 1. データベースインデックス

#### 実装内容
```sql
-- locations テーブル
CREATE INDEX idx_location_coords ON locations(latitude, longitude);

-- observations テーブル
CREATE INDEX idx_observation_location_date ON observations(location_id, observation_date);

-- climate_normals テーブル
CREATE INDEX idx_climate_station_month ON climate_normals(station_id, month);

-- weather_stations テーブル
CREATE INDEX idx_station_id ON weather_stations(station_id);
CREATE INDEX idx_coordinates ON weather_stations(latitude, longitude);
```

#### 検証
```sql
-- INDEX が設定されているか確認
SHOW INDEX FROM locations;
SHOW INDEX FROM observations;
SHOW INDEX FROM climate_normals;
SHOW INDEX FROM weather_stations;

-- 実行計画を確認
EXPLAIN SELECT * FROM observations WHERE location_id = 1 ORDER BY observation_date DESC;
```

**✅ 期待結果**: `type` が `ref` または `range`（`ALL` でない）

---

### 2. N+1問題の回避

#### 実装内容
- 比較グラフ取得時、各観測日ごとにAPIを呼び出す（現状）
- 今後の改善: バッチ取得APIの実装

#### 現在の実装
```javascript
// frontend/js/chart.js
for (const obs of sortedObs) {
    const compResponse = await fetch(`${API_BASE_URL}?action=get_comparison&location_id=${locationId}&date=${obs.observation_date}`);
    // ... 処理
}
```

#### 改善案（v1.1）
```php
// GET /api.php?action=get_batch_comparison&location_id=1&start_date=2026-01-01&end_date=2026-01-31
// 一度のクエリで全期間の比較データを取得
```

---

### 3. キャッシュ戦略（今後実装予定）

#### 現在の状態
❌ **未実装** - v1.1で実装予定

#### 実装方針
```php
// 静的ファイルのキャッシュヘッダー（.htaccess）
<FilesMatch "\.(css|js|jpg|png|gif|ico)$">
    Header set Cache-Control "max-age=31536000, public"
</FilesMatch>

// APIレスポンスのキャッシュ（短期間）
header('Cache-Control: max-age=300, public');  // 5分間キャッシュ
```

---

## ♿ アクセシビリティ対策

### 1. キーボード操作対応

#### 実装状況
- ✅ Tabキーでフォーカス移動可能
- ✅ Enterキーでフォーム送信可能
- ⚠️ Escキーでモーダル閉じる機能（未実装）

#### テスト方法
1. Tabキーで全要素にフォーカス移動できるか
2. Enterキーでボタンが押せるか
3. Escキーでモーダルが閉じられるか

---

### 2. スクリーンリーダー対応

#### 実装状況
- ⚠️ 一部の要素に `aria-label` 未設定
- ⚠️ フォームラベルは設定済み
- ❌ 画像の `alt` 属性（画像なし）

#### 改善案
```html
<!-- ボタンに aria-label 追加 -->
<button id="exportBtn" class="btn btn-secondary" aria-label="CSVファイルをエクスポート">
    📥 CSVエクスポート
</button>

<!-- フォーム要素のラベル関連付け -->
<label for="latitude">緯度</label>
<input type="number" id="latitude" name="latitude" aria-describedby="latitude-hint">
<small id="latitude-hint">日本国内: 24〜46</small>
```

---

### 3. 色覚異常対応

#### 実装状況
- ✅ 温度による色分けマーカー（青→緑→黄→橙→赤）
- ⚠️ 色だけでなくアイコンや数値も併用すべき

#### 改善案
```javascript
// マーカーに温度表示を追加（色だけに依存しない）
const html = `
    <div class="custom-marker" style="background-color: ${color};">
        <span class="marker-label">${lstValue.toFixed(1)}°C</span>
    </div>
`;
```

**✅ 実装済み**: マーカーに温度が表示される

---

## 📋 セキュリティチェックリスト

デプロイ前に以下の項目を確認してください。

### データベースセキュリティ
- [ ] すべてのSQLクエリでプリペアドステートメント使用
- [ ] ユーザー入力を直接SQLに埋め込んでいない
- [ ] データベースユーザーの権限が最小限（SELECT, INSERT, UPDATE, DELETEのみ）
- [ ] root ユーザーでの接続を避けている

### XSS対策
- [ ] ユーザー入力を表示する際、htmlspecialchars() または textContent 使用
- [ ] innerHTML は検証済みデータのみ
- [ ] JSON.parse() の結果を直接DOMに挿入していない

### 認証情報保護
- [ ] config.php が .gitignore に含まれている
- [ ] .env ファイルが .gitignore に含まれている
- [ ] ログファイルが .gitignore に含まれている
- [ ] データベースパスワードが強固（12文字以上、英数字記号混在）
- [ ] 本番環境でデフォルトパスワードを使用していない

### CORS設定
- [ ] 本番環境で `Access-Control-Allow-Origin: *` を使用していない
- [ ] 許可するオリジンを明示的に指定

### エラーメッセージ
- [ ] 本番環境で display_errors = Off
- [ ] データベースエラーの詳細が外部に漏れない
- [ ] スタックトレースが外部に表示されない

### ファイルパーミッション
- [ ] ログディレクトリの書き込み権限（755）
- [ ] 設定ファイルの読み取り専用（644）
- [ ] 実行ファイルの実行権限（755）

### HTTPSとセキュリティヘッダー
- [ ] 本番環境でHTTPS使用
- [ ] X-Frame-Options ヘッダー設定
- [ ] X-Content-Type-Options ヘッダー設定
- [ ] Content-Security-Policy ヘッダー設定（推奨）

### ログとモニタリング
- [ ] APIアクセスログが記録されている
- [ ] エラーログが記録されている
- [ ] ログファイルのローテーション設定

### 定期的なセキュリティ更新
- [ ] PHPバージョンが最新（または最新の安定版）
- [ ] MySQLバージョンが最新（または最新の安定版）
- [ ] 使用しているライブラリが最新（Leaflet.js, Chart.js）

---

## 🔐 本番環境デプロイ前チェックリスト

### 設定ファイル
- [ ] config.php.example をコピーして config.php を作成
- [ ] データベース接続情報を本番環境用に変更
- [ ] .env.example をコピーして .env を作成
- [ ] JAXA G-Portal 認証情報を設定

### データベース
- [ ] データベースが作成されている
- [ ] db_setup.sql を実行してテーブル作成
- [ ] 初期データ（weather_stations）が登録されている
- [ ] バックアップ体制が整っている

### Webサーバー
- [ ] ドキュメントルートが正しく設定されている
- [ ] .htaccess が有効化されている（Apache の場合）
- [ ] ログディレクトリの書き込み権限が設定されている
- [ ] PHPエラーログの出力先が設定されている

### セキュリティ
- [ ] HTTPS が有効化されている
- [ ] ファイアウォール設定が適切
- [ ] 不要なポートが閉じられている
- [ ] データベースが外部から直接アクセスできない

### パフォーマンス
- [ ] OPcache が有効化されている（PHP）
- [ ] データベースインデックスが設定されている
- [ ] 静的ファイルのキャッシュヘッダーが設定されている

### モニタリング
- [ ] ログ監視が設定されている
- [ ] エラー通知が設定されている
- [ ] ディスク使用量の監視

---

## 📞 セキュリティインシデント対応

### インシデント発生時の対応フロー

1. **検知**
   - ログファイルの異常な動き
   - 予期しないデータベースアクセス
   - ユーザーからの報告

2. **初動対応**
   - 影響範囲の特定
   - 問題のあるアクセスをブロック
   - データベースのバックアップ取得

3. **調査**
   - アクセスログの解析
   - データベースログの確認
   - 脆弱性の特定

4. **修正**
   - セキュリティパッチの適用
   - 脆弱なコードの修正
   - データベースの復旧（必要に応じて）

5. **事後対応**
   - 再発防止策の実施
   - ドキュメントの更新
   - 関係者への報告

### 緊急連絡先
- システム管理者: [連絡先を記入]
- データベース管理者: [連絡先を記入]
- セキュリティ責任者: [連絡先を記入]

---

## 📚 参考資料

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [PHP Security Best Practices](https://www.php.net/manual/en/security.php)
- [MySQL Security Guidelines](https://dev.mysql.com/doc/refman/8.0/en/security.html)
- [Web Content Accessibility Guidelines (WCAG) 2.1](https://www.w3.org/WAI/WCAG21/quickref/)

---

**最終更新日**: 2026-01-16
**バージョン**: 1.0
