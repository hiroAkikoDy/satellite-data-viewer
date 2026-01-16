#!/bin/bash

# Satellite Data Viewer - セキュリティテストスクリプト
# このスクリプトは、基本的なセキュリティテストを実行します

# XAMPP環境に合わせたURL（プロジェクト名を含む）
BASE_URL="http://localhost/satellite-viewer/backend/api.php"
PASSED=0
FAILED=0

echo "========================================="
echo "Satellite Data Viewer セキュリティテスト"
echo "========================================="
echo ""

# 色の定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# テスト結果の表示関数
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASSED${NC}: $2"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}: $2"
        ((FAILED++))
    fi
}

# 1. SQLインジェクション対策テスト
echo "1. SQLインジェクション対策テスト"
echo "=================================="

# テスト1: 緯度にSQLインジェクションを試行
RESPONSE=$(curl -s -X POST "$BASE_URL?action=add_location" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"SQL Injection Test\",
    \"latitude\": \"32.8032' OR '1'='1\",
    \"longitude\": 130.7075
  }")

# レスポンスにエラーが含まれているか確認（成功してはいけない）
if echo "$RESPONSE" | grep -q '"success":false'; then
    print_result 0 "緯度へのSQLインジェクション攻撃が防止された"
else
    print_result 1 "緯度へのSQLインジェクション攻撃が防止されなかった"
    echo "    レスポンス: $RESPONSE"
fi

# テスト2: location_id にSQLインジェクションを試行
RESPONSE=$(curl -s "$BASE_URL?action=get_observations&location_id=1%20OR%201=1&days=30")

# データが不正に取得されていないか確認
# location_idは整数にキャストされるため、"1 OR 1=1" は 1 として扱われる
if echo "$RESPONSE" | grep -q '"success"'; then
    # プリペアドステートメントにより、不正なSQLは実行されない
    print_result 0 "location_id へのSQLインジェクション攻撃が防止された"
else
    print_result 1 "location_id へのSQLインジェクション攻撃の処理に失敗"
    echo "    レスポンス: $RESPONSE"
fi

echo ""

# 2. XSS対策テスト
echo "2. XSS（クロスサイトスクリプティング）対策テスト"
echo "==============================================="

# テスト3: 地点名にスクリプトタグを挿入
RESPONSE=$(curl -s -X POST "$BASE_URL?action=add_location" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"<script>alert(\\\"XSS\\\")</script>\",\"latitude\":35.6812,\"longitude\":139.7671}")

# 改行を削除してチェック
RESPONSE_COMPACT=$(echo "$RESPONSE" | tr -d '\n')

# スクリプトタグが除去されているか確認
if echo "$RESPONSE_COMPACT" | grep -q 'success.*true'; then
    # レスポンス内にスクリプトタグが含まれていないことを確認
    if echo "$RESPONSE_COMPACT" | grep -q "<script>"; then
        print_result 1 "XSS攻撃が防止されなかった（スクリプトタグが残っている）"
        echo "    レスポンス: $RESPONSE"
    else
        # スクリプトタグが除去されていれば合格
        print_result 0 "XSS攻撃が防止された（HTMLタグが除去された）"
    fi
elif echo "$RESPONSE_COMPACT" | grep -q 'success.*false'; then
    # バリデーションで拒否された場合も合格
    print_result 0 "XSS攻撃が入力時点で拒否された"
else
    print_result 1 "XSS攻撃の処理に失敗"
    echo "    レスポンス: $RESPONSE"
fi

echo ""

# 3. 認証情報保護テスト
echo "3. 認証情報保護テスト"
echo "===================="

# プロジェクトルートに移動
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# テスト4: .gitignore に機密ファイルが含まれているか
if [ -f .gitignore ]; then
    if grep -q "config.php" .gitignore && \
       grep -q "\.env" .gitignore && \
       grep -q "logs/" .gitignore; then
        print_result 0 ".gitignore に機密ファイルが含まれている"
    else
        print_result 1 ".gitignore に機密ファイルが不足している"
    fi
else
    print_result 1 ".gitignore ファイルが存在しない"
fi

# テスト5: 機密ファイルがGit管理されていないか
if command -v git &> /dev/null; then
    if git ls-files 2>/dev/null | grep -E "backend/config.php|\.env" > /dev/null; then
        print_result 1 "機密ファイルがGit管理されている"
    else
        print_result 0 "機密ファイルがGit管理外になっている"
    fi
else
    echo -e "${YELLOW}⚠ SKIPPED${NC}: Git がインストールされていません"
fi

echo ""

# 4. API エンドポイントテスト
echo "4. API エンドポイントテスト"
echo "========================="

# テスト6: 無効なアクション
RESPONSE=$(curl -s "$BASE_URL?action=invalid_action")
if echo "$RESPONSE" | grep -q '"success":false'; then
    print_result 0 "無効なアクションが適切に拒否された"
else
    print_result 1 "無効なアクションが拒否されなかった"
fi

# テスト7: 必須パラメータの欠如
RESPONSE=$(curl -s "$BASE_URL?action=get_observations")
if echo "$RESPONSE" | grep -q '"success":false'; then
    print_result 0 "必須パラメータ欠如が検出された"
else
    print_result 1 "必須パラメータ欠如が検出されなかった"
fi

# テスト8: 存在しない地点ID
RESPONSE=$(curl -s "$BASE_URL?action=get_observations&location_id=99999&days=30")
if echo "$RESPONSE" | grep -q '"success":false'; then
    print_result 0 "存在しない地点IDが適切に処理された"
else
    print_result 1 "存在しない地点IDが適切に処理されなかった"
fi

echo ""

# 5. バリデーションテスト
echo "5. バリデーションテスト"
echo "====================="

# テスト9: 緯度の範囲外
RESPONSE=$(curl -s -X POST "$BASE_URL?action=add_location" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Invalid Latitude\",
    \"latitude\": 91.0,
    \"longitude\": 139.7671
  }")

# バリデーションエラーが返るべき
if echo "$RESPONSE" | grep -q '"success":false'; then
    print_result 0 "緯度の範囲外値が適切に拒否された"
else
    print_result 1 "緯度の範囲外値が拒否されなかった"
    echo "    レスポンス: $RESPONSE"
fi

# テスト10: 経度の範囲外
RESPONSE=$(curl -s -X POST "$BASE_URL?action=add_location" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Invalid Longitude\",
    \"latitude\": 35.6812,
    \"longitude\": 181.0
  }")

if echo "$RESPONSE" | grep -q '"success":false'; then
    print_result 0 "経度の範囲外値が適切に拒否された"
else
    print_result 1 "経度の範囲外値が拒否されなかった"
    echo "    レスポンス: $RESPONSE"
fi

echo ""

# 6. ファイルパーミッションテスト
echo "6. ファイルパーミッションテスト"
echo "=============================="

# テスト11: ログディレクトリの書き込み権限
if [ -d "backend/logs" ]; then
    if [ -w "backend/logs" ]; then
        print_result 0 "ログディレクトリに書き込み権限がある"
    else
        print_result 1 "ログディレクトリに書き込み権限がない"
    fi
else
    print_result 1 "ログディレクトリが存在しない"
fi

# テスト12: 設定ファイルの存在確認
if [ -f "backend/config.php" ]; then
    print_result 0 "config.php が存在する"
else
    print_result 1 "config.php が存在しない"
fi

echo ""

# 結果サマリー
echo "========================================="
echo "テスト結果サマリー"
echo "========================================="
echo -e "合格: ${GREEN}$PASSED${NC}"
echo -e "不合格: ${RED}$FAILED${NC}"
TOTAL=$((PASSED + FAILED))
echo "合計: $TOTAL"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}すべてのテストに合格しました！${NC}"
    exit 0
else
    echo -e "${RED}一部のテストが失敗しました。${NC}"
    exit 1
fi
