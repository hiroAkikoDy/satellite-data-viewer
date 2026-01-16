#!/bin/bash
# API Endpoint Test Script
#
# backend/api.php の各エンドポイントをcURLでテスト
#
# 使用方法:
#   chmod +x backend/test_api.sh
#   ./backend/test_api.sh

# 設定
API_URL="http://localhost/backend/api.php"

# カラー出力
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}API Endpoint Test${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# テスト1: get_locations
echo -e "${BLUE}Test 1: GET /api.php?action=get_locations${NC}"
echo "----------------------------------------------------------------------"
curl -s "${API_URL}?action=get_locations" | python -m json.tool || echo -e "${RED}JSON parse error${NC}"
echo ""
echo ""

# テスト2: get_observations
echo -e "${BLUE}Test 2: GET /api.php?action=get_observations&location_id=1&days=7${NC}"
echo "----------------------------------------------------------------------"
curl -s "${API_URL}?action=get_observations&location_id=1&days=7" | python -m json.tool || echo -e "${RED}JSON parse error${NC}"
echo ""
echo ""

# テスト3: get_comparison
echo -e "${BLUE}Test 3: GET /api.php?action=get_comparison&location_id=1&date=2026-01-08${NC}"
echo "----------------------------------------------------------------------"
curl -s "${API_URL}?action=get_comparison&location_id=1&date=2026-01-08" | python -m json.tool || echo -e "${RED}JSON parse error${NC}"
echo ""
echo ""

# テスト4: add_location (POST)
echo -e "${BLUE}Test 4: POST /api.php?action=add_location${NC}"
echo "----------------------------------------------------------------------"
curl -s -X POST "${API_URL}?action=add_location" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Farm",
    "latitude": 35.6812,
    "longitude": 139.7671,
    "prefecture": "東京都",
    "city": "千代田区",
    "nearest_station_id": "44",
    "nearest_station_name": "東京"
  }' | python -m json.tool || echo -e "${RED}JSON parse error${NC}"
echo ""
echo ""

# テスト5: export_csv
echo -e "${BLUE}Test 5: GET /api.php?action=export_csv&location_id=1${NC}"
echo "----------------------------------------------------------------------"
echo "CSVファイルダウンロード（最初の5行のみ表示）:"
curl -s "${API_URL}?action=export_csv&location_id=1" | head -5
echo ""
echo ""

# テスト6: エラーケース - アクションなし
echo -e "${BLUE}Test 6: Error Case - No action${NC}"
echo "----------------------------------------------------------------------"
curl -s "${API_URL}" | python -m json.tool || echo -e "${RED}JSON parse error${NC}"
echo ""
echo ""

# テスト7: エラーケース - 無効なアクション
echo -e "${BLUE}Test 7: Error Case - Invalid action${NC}"
echo "----------------------------------------------------------------------"
curl -s "${API_URL}?action=invalid_action" | python -m json.tool || echo -e "${RED}JSON parse error${NC}"
echo ""
echo ""

# テスト8: エラーケース - location_id なし
echo -e "${BLUE}Test 8: Error Case - Missing location_id${NC}"
echo "----------------------------------------------------------------------"
curl -s "${API_URL}?action=get_observations" | python -m json.tool || echo -e "${RED}JSON parse error${NC}"
echo ""
echo ""

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}All tests completed${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "ログファイルを確認:"
echo "  backend/logs/$(date +%Y-%m-%d).log"
echo ""
