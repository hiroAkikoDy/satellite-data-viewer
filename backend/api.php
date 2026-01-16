<?php
/**
 * Satellite Data Viewer API
 *
 * RESTful APIエンドポイント
 *
 * エンドポイント:
 * - GET  /api.php?action=get_locations
 * - GET  /api.php?action=get_observations&location_id=1&days=30
 * - GET  /api.php?action=get_comparison&location_id=1&date=2026-01-08
 * - POST /api.php?action=add_location
 * - GET  /api.php?action=export_csv&location_id=1
 */

// 設定ファイル読み込み
require_once __DIR__ . '/config.php';

// CORS設定適用
applyCorsHeaders();

// Content-Type設定
header('Content-Type: ' . API_RESPONSE_TYPE);

// ===========================
// ログ機能
// ===========================

/**
 * ログをファイルに書き込む
 *
 * @param string $level ログレベル（INFO, WARNING, ERROR）
 * @param string $message ログメッセージ
 * @param array $context コンテキスト情報
 */
function writeLog($level, $message, $context = []) {
    $logDir = __DIR__ . '/logs';

    // ログディレクトリが存在しない場合は作成
    if (!is_dir($logDir)) {
        mkdir($logDir, 0755, true);
    }

    // 日付ごとのログファイル
    $logFile = $logDir . '/' . date('Y-m-d') . '.log';
    $timestamp = date('Y-m-d H:i:s');

    // コンテキスト情報をJSON形式に変換
    $contextStr = !empty($context) ? json_encode($context, JSON_UNESCAPED_UNICODE) : '';

    // ログ行を作成
    $logLine = "[{$timestamp}] [{$level}] {$message} {$contextStr}\n";

    // ファイルに追記
    file_put_contents($logFile, $logLine, FILE_APPEND);
}

/**
 * 古いログファイルを削除（30日以上前）
 */
function cleanOldLogs() {
    $logDir = __DIR__ . '/logs';

    if (!is_dir($logDir)) {
        return;
    }

    $files = glob($logDir . '/*.log');
    $cutoffTime = strtotime('-30 days');

    foreach ($files as $file) {
        if (filemtime($file) < $cutoffTime) {
            unlink($file);
            writeLog('INFO', 'ログファイル削除', ['file' => basename($file)]);
        }
    }
}

// 古いログのクリーンアップ（1%の確率で実行）
if (rand(1, 100) === 1) {
    cleanOldLogs();
}

// ===========================
// リクエスト処理
// ===========================

try {
    // アクション取得
    $action = $_GET['action'] ?? '';

    if (empty($action)) {
        writeLog('WARNING', 'アクションが指定されていません', [
            'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
            'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? 'unknown'
        ]);
        sendErrorResponse('アクションが指定されていません', 400);
    }

    // リクエスト情報をログ記録
    writeLog('INFO', 'API呼び出し開始', [
        'action' => $action,
        'method' => $_SERVER['REQUEST_METHOD'],
        'params' => $_GET,
        'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
        'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? 'unknown'
    ]);

    // データベース接続
    $pdo = getDbConnection();

    // アクションに応じた処理
    switch ($action) {
        case 'get_locations':
            handleGetLocations($pdo);
            break;

        case 'get_observations':
            handleGetObservations($pdo);
            break;

        case 'get_comparison':
            handleGetComparison($pdo);
            break;

        case 'add_location':
            handleAddLocation($pdo);
            break;

        case 'export_csv':
            handleExportCsv($pdo);
            break;

        case 'find_nearest_station':
            handleFindNearestStation($pdo);
            break;

        default:
            writeLog('WARNING', '無効なアクション', [
                'action' => $action,
                'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown'
            ]);
            sendErrorResponse('無効なアクション: ' . $action, 400);
    }

} catch (PDOException $e) {
    writeLog('ERROR', 'データベースエラー', [
        'action' => $_GET['action'] ?? 'unknown',
        'error' => $e->getMessage(),
        'file' => $e->getFile(),
        'line' => $e->getLine(),
        'trace' => $e->getTraceAsString()
    ]);

    error_log("Database error: " . $e->getMessage());
    sendErrorResponse('データベースエラーが発生しました', 500);

} catch (Exception $e) {
    writeLog('ERROR', 'API実行エラー', [
        'action' => $_GET['action'] ?? 'unknown',
        'message' => $e->getMessage(),
        'file' => $e->getFile(),
        'line' => $e->getLine(),
        'trace' => $e->getTraceAsString()
    ]);

    error_log("General error: " . $e->getMessage());
    sendErrorResponse('処理中にエラーが発生しました。管理者にお問い合わせください。', 500);
}

// ===========================
// ハンドラー関数
// ===========================

/**
 * GET /api.php?action=get_locations
 *
 * 登録されている観測地点一覧を返す
 */
function handleGetLocations($pdo) {
    try {
        $sql = "
            SELECT
                id,
                name,
                latitude,
                longitude,
                prefecture,
                city,
                nearest_station_id,
                nearest_station_name,
                created_at
            FROM locations
            ORDER BY created_at DESC
        ";

        $stmt = $pdo->query($sql);
        $locations = $stmt->fetchAll();

        writeLog('INFO', '観測地点一覧取得成功', [
            'count' => count($locations)
        ]);

        sendSuccessResponse($locations, count($locations) . '件の観測地点が見つかりました');

    } catch (Exception $e) {
        writeLog('ERROR', '観測地点一覧取得エラー', [
            'error' => $e->getMessage()
        ]);
        throw $e;
    }
}

/**
 * GET /api.php?action=get_observations&location_id=1&days=30
 *
 * 指定地点の過去N日分の観測データを返す
 */
function handleGetObservations($pdo) {
    try {
        // パラメータ取得
        $locationId = $_GET['location_id'] ?? null;
        $days = isset($_GET['days']) ? (int)$_GET['days'] : 30;

        // バリデーション
        if ($locationId === null) {
            writeLog('WARNING', '観測データ取得: location_id未指定', [
                'params' => $_GET
            ]);
            sendErrorResponse('location_id が指定されていません', 400);
        }

        // 観測地点の存在確認
        $location = getLocationById($pdo, $locationId);
        if (!$location) {
            writeLog('WARNING', '観測データ取得: 地点が見つからない', [
                'location_id' => $locationId
            ]);
            sendErrorResponse('指定された観測地点が見つかりません', 404);
        }

        // 観測データ取得
        $sql = "
            SELECT
                id,
                location_id,
                observation_date,
                lst,
                ndvi,
                created_at
            FROM observations
            WHERE location_id = :location_id
              AND observation_date >= DATE_SUB(CURDATE(), INTERVAL :days DAY)
            ORDER BY observation_date DESC
        ";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            'location_id' => $locationId,
            'days' => $days
        ]);

        $observations = $stmt->fetchAll();

        writeLog('INFO', '観測データ取得成功', [
            'location_id' => $locationId,
            'days' => $days,
            'count' => count($observations)
        ]);

        sendSuccessResponse([
            'location' => $location,
            'observations' => $observations,
            'count' => count($observations)
        ]);

    } catch (Exception $e) {
        writeLog('ERROR', '観測データ取得エラー', [
            'location_id' => $locationId ?? null,
            'error' => $e->getMessage()
        ]);
        throw $e;
    }
}

/**
 * GET /api.php?action=get_comparison&location_id=1&date=2026-01-08
 *
 * 衛星観測値と気象庁平年値を比較
 */
function handleGetComparison($pdo) {
    try {
        // パラメータ取得
        $locationId = $_GET['location_id'] ?? null;
        $date = $_GET['date'] ?? date('Y-m-d');

        // バリデーション
        if ($locationId === null) {
            writeLog('WARNING', '比較データ取得: location_id未指定', [
                'params' => $_GET
            ]);
            sendErrorResponse('location_id が指定されていません', 400);
        }

        // 日付形式チェック
        $dateObj = DateTime::createFromFormat('Y-m-d', $date);
        if (!$dateObj || $dateObj->format('Y-m-d') !== $date) {
            writeLog('WARNING', '比較データ取得: 日付形式不正', [
                'date' => $date
            ]);
            sendErrorResponse('日付形式が不正です（YYYY-MM-DD形式で指定してください）', 400);
        }

        // 観測地点取得
        $location = getLocationById($pdo, $locationId);
        if (!$location) {
            writeLog('WARNING', '比較データ取得: 地点が見つからない', [
                'location_id' => $locationId
            ]);
            sendErrorResponse('指定された観測地点が見つかりません', 404);
        }

        // 衛星観測データ取得
        $sql = "
            SELECT
                observation_date,
                lst,
                ndvi
            FROM observations
            WHERE location_id = :location_id
              AND observation_date = :date
        ";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            'location_id' => $locationId,
            'date' => $date
        ]);

        $observation = $stmt->fetch();

        // 気象庁平年値取得（最寄り観測所の該当月）
        $month = (int)$dateObj->format('m');
        $climateNormal = null;

        if (!empty($location['nearest_station_id'])) {
            $sql = "
                SELECT
                    station_id,
                    station_name,
                    month,
                    avg_temp,
                    max_temp,
                    min_temp,
                    precipitation
                FROM climate_normals
                WHERE station_id = :station_id
                  AND month = :month
            ";

            $stmt = $pdo->prepare($sql);
            $stmt->execute([
                'station_id' => $location['nearest_station_id'],
                'month' => $month
            ]);

            $climateNormal = $stmt->fetch();
        }

        // 比較分析
        $comparison = null;
        if ($observation && $climateNormal) {
            $lstValue = $observation['lst'];
            $avgTemp = $climateNormal['avg_temp'];

            $comparison = [
                'temperature_difference' => round($lstValue - $avgTemp, 2),
                'is_above_normal' => $lstValue > $avgTemp,
                'deviation_percentage' => $avgTemp != 0 ? round((($lstValue - $avgTemp) / $avgTemp) * 100, 2) : null
            ];
        }

        writeLog('INFO', '比較データ取得成功', [
            'location_id' => $locationId,
            'date' => $date,
            'has_observation' => $observation !== false,
            'has_climate_normal' => $climateNormal !== false,
            'has_comparison' => $comparison !== null
        ]);

        sendSuccessResponse([
            'location' => $location,
            'date' => $date,
            'satellite_observation' => $observation ?: null,
            'climate_normal' => $climateNormal ?: null,
            'comparison' => $comparison
        ]);

    } catch (Exception $e) {
        writeLog('ERROR', '比較データ取得エラー', [
            'location_id' => $locationId ?? null,
            'date' => $date ?? null,
            'error' => $e->getMessage()
        ]);
        throw $e;
    }
}

/**
 * POST /api.php?action=add_location
 *
 * 新しい観測地点を追加
 *
 * POSTパラメータ:
 * - name: 地点名
 * - latitude: 緯度
 * - longitude: 経度
 * - prefecture: 都道府県（オプション）
 * - city: 市区町村（オプション）
 * - nearest_station_id: 最寄り観測所ID（オプション）
 * - nearest_station_name: 最寄り観測所名（オプション）
 */
function handleAddLocation($pdo) {
    try {
        // POSTデータ取得
        $input = file_get_contents('php://input');
        $data = json_decode($input, true);

        if ($data === null) {
            // JSON以外の場合は $_POST を使用
            $data = $_POST;
        }

        // 必須パラメータチェック
        $name = $data['name'] ?? null;
        $latitude = $data['latitude'] ?? null;
        $longitude = $data['longitude'] ?? null;

        if (empty($name) || $latitude === null || $longitude === null) {
            writeLog('WARNING', '観測地点追加: 必須パラメータ不足', [
                'data' => $data
            ]);
            sendErrorResponse('必須パラメータが不足しています（name, latitude, longitude）', 400);
        }

        // XSS対策: HTMLタグを除去（strip_tags）
        $name = strip_tags($name);

        // 数値型にキャスト（SQLインジェクション対策）
        $latitude = floatval($latitude);
        $longitude = floatval($longitude);

        // 数値として有効かチェック
        if (!is_numeric($data['latitude']) || !is_numeric($data['longitude'])) {
            writeLog('WARNING', '観測地点追加: 緯度経度が数値でない', [
                'latitude' => $data['latitude'],
                'longitude' => $data['longitude']
            ]);
            sendErrorResponse('緯度と経度は数値で指定してください', 400);
        }

        // 緯度経度の範囲チェック
        if ($latitude < -90 || $latitude > 90) {
            writeLog('WARNING', '観測地点追加: 緯度範囲不正', [
                'latitude' => $latitude
            ]);
            sendErrorResponse('緯度の値が不正です（-90 ～ 90の範囲で指定してください）', 400);
        }

        if ($longitude < -180 || $longitude > 180) {
            writeLog('WARNING', '観測地点追加: 経度範囲不正', [
                'longitude' => $longitude
            ]);
            sendErrorResponse('経度の値が不正です（-180 ～ 180の範囲で指定してください）', 400);
        }

        // オプションパラメータ（XSS対策: HTMLタグを除去）
        $prefecture = isset($data['prefecture']) ? strip_tags($data['prefecture']) : null;
        $city = isset($data['city']) ? strip_tags($data['city']) : null;
        $nearestStationId = $data['nearest_station_id'] ?? null;
        $nearestStationName = isset($data['nearest_station_name']) ? strip_tags($data['nearest_station_name']) : null;

        // データ挿入
        $sql = "
            INSERT INTO locations (
                name,
                latitude,
                longitude,
                prefecture,
                city,
                nearest_station_id,
                nearest_station_name
            ) VALUES (
                :name,
                :latitude,
                :longitude,
                :prefecture,
                :city,
                :nearest_station_id,
                :nearest_station_name
            )
        ";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            'name' => $name,
            'latitude' => $latitude,
            'longitude' => $longitude,
            'prefecture' => $prefecture,
            'city' => $city,
            'nearest_station_id' => $nearestStationId,
            'nearest_station_name' => $nearestStationName
        ]);

        $newLocationId = $pdo->lastInsertId();

        // 作成した地点を取得
        $newLocation = getLocationById($pdo, $newLocationId);

        writeLog('INFO', '観測地点追加成功', [
            'location_id' => $newLocationId,
            'name' => $name,
            'latitude' => $latitude,
            'longitude' => $longitude
        ]);

        sendSuccessResponse($newLocation, '観測地点を追加しました');

    } catch (Exception $e) {
        writeLog('ERROR', '観測地点追加エラー', [
            'data' => $data ?? null,
            'error' => $e->getMessage()
        ]);
        throw $e;
    }
}

/**
 * GET /api.php?action=export_csv&location_id=1&start_date=2026-01-01&end_date=2026-01-31
 *
 * 観測データをCSV形式でエクスポート（平年値比較付き）
 */
function handleExportCsv($pdo) {
    try {
        // パラメータ取得
        $locationId = $_GET['location_id'] ?? null;
        $startDate = $_GET['start_date'] ?? null;
        $endDate = $_GET['end_date'] ?? null;

        // バリデーション
        if ($locationId === null) {
            writeLog('WARNING', 'CSVエクスポート: location_id未指定', [
                'params' => $_GET
            ]);
            sendErrorResponse('location_id が指定されていません', 400);
        }

        // 観測地点取得
        $location = getLocationById($pdo, $locationId);
        if (!$location) {
            writeLog('WARNING', 'CSVエクスポート: 地点が見つからない', [
                'location_id' => $locationId
            ]);
            sendErrorResponse('指定された観測地点が見つかりません', 404);
        }

        // 観測データ取得（期間指定対応）
        $sql = "
            SELECT
                observation_date,
                lst,
                ndvi
            FROM observations
            WHERE location_id = :location_id
        ";

        $params = ['location_id' => $locationId];

        if ($startDate !== null) {
            $sql .= " AND observation_date >= :start_date";
            $params['start_date'] = $startDate;
        }

        if ($endDate !== null) {
            $sql .= " AND observation_date <= :end_date";
            $params['end_date'] = $endDate;
        }

        $sql .= " ORDER BY observation_date ASC";

        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        $observations = $stmt->fetchAll();

        if (empty($observations)) {
            writeLog('WARNING', 'CSVエクスポート: データがない', [
                'location_id' => $locationId,
                'start_date' => $startDate,
                'end_date' => $endDate
            ]);
            sendErrorResponse('エクスポートするデータがありません', 404);
        }

        // 平年値データを取得（最寄り観測所が設定されている場合）
        $climateNormals = [];
        if (!empty($location['nearest_station_id'])) {
            $sql = "
                SELECT
                    month,
                    avg_temp,
                    max_temp,
                    min_temp,
                    precipitation
                FROM climate_normals
                WHERE station_id = :station_id
            ";

            $stmt = $pdo->prepare($sql);
            $stmt->execute(['station_id' => $location['nearest_station_id']]);

            while ($row = $stmt->fetch()) {
                $climateNormals[$row['month']] = $row;
            }
        }

        writeLog('INFO', 'CSVエクスポート成功', [
            'location_id' => $locationId,
            'location_name' => $location['name'],
            'count' => count($observations),
            'start_date' => $startDate,
            'end_date' => $endDate,
            'has_climate_data' => !empty($climateNormals)
        ]);

        // CSVヘッダー設定
        $filename = 'satellite_data_' . preg_replace('/[^a-zA-Z0-9_-]/', '_', $location['name']) . '_' . date('Ymd') . '.csv';
        header('Content-Type: text/csv; charset=UTF-8');
        header('Content-Disposition: attachment; filename="' . $filename . '"');

        // BOM出力（Excel対応）
        echo "\xEF\xBB\xBF";

        // CSV出力
        $output = fopen('php://output', 'w');

        // ヘッダー行
        fputcsv($output, [
            '日付',
            '地点名',
            '緯度',
            '経度',
            'LST(℃)',
            'NDVI',
            '平年値_最高(℃)',
            '平年値_最低(℃)'
        ]);

        // データ行
        foreach ($observations as $row) {
            $date = $row['observation_date'];
            $month = (int)date('m', strtotime($date));

            // 平年値（最高・最低）を取得
            $climateMaxTemp = null;
            $climateMinTemp = null;

            if (isset($climateNormals[$month])) {
                $climateMaxTemp = $climateNormals[$month]['max_temp'];
                $climateMinTemp = $climateNormals[$month]['min_temp'];
            }

            fputcsv($output, [
                $date,
                $location['name'],
                $location['latitude'],
                $location['longitude'],
                $row['lst'],
                $row['ndvi'],
                $climateMaxTemp,
                $climateMinTemp
            ]);
        }

        fclose($output);
        exit;

    } catch (Exception $e) {
        writeLog('ERROR', 'CSVエクスポートエラー', [
            'location_id' => $locationId ?? null,
            'start_date' => $startDate ?? null,
            'end_date' => $endDate ?? null,
            'error' => $e->getMessage()
        ]);
        throw $e;
    }
}

/**
 * GET /api.php?action=find_nearest_station&lat=32.8032&lon=130.7075
 *
 * 指定緯度経度から最寄りの気象観測所を検索（Haversine公式使用）
 */
function handleFindNearestStation($pdo) {
    try {
        // パラメータ取得と数値チェック
        $lat = $_GET['lat'] ?? null;
        $lon = $_GET['lon'] ?? null;

        // パラメータ存在チェック
        if ($lat === null || $lon === null) {
            writeLog('WARNING', '最寄り観測所検索: 緯度経度未指定', [
                'params' => $_GET
            ]);
            sendErrorResponse('緯度（lat）と経度（lon）を指定してください', 400);
        }

        // 数値型チェック
        if (!is_numeric($lat) || !is_numeric($lon)) {
            writeLog('WARNING', '最寄り観測所検索: 緯度経度が数値でない', [
                'lat' => $lat,
                'lon' => $lon
            ]);
            sendErrorResponse('緯度と経度は数値で指定してください', 400);
        }

        // floatにキャスト
        $lat = floatval($lat);
        $lon = floatval($lon);

        // 範囲チェック
        if ($lat < -90 || $lat > 90) {
            writeLog('WARNING', '最寄り観測所検索: 緯度範囲不正', [
                'lat' => $lat
            ]);
            sendErrorResponse('緯度は-90〜90の範囲で指定してください', 400);
        }

        if ($lon < -180 || $lon > 180) {
            writeLog('WARNING', '最寄り観測所検索: 経度範囲不正', [
                'lon' => $lon
            ]);
            sendErrorResponse('経度は-180〜180の範囲で指定してください', 400);
        }

        // Haversine公式で距離計算（MySQL）
        // 6371: 地球の半径（km）
        $sql = "
            SELECT
                station_id,
                station_name,
                latitude,
                longitude,
                prefecture,
                elevation,
                (
                    6371 * acos(
                        cos(radians(:lat)) * cos(radians(latitude)) *
                        cos(radians(longitude) - radians(:lon)) +
                        sin(radians(:lat)) * sin(radians(latitude))
                    )
                ) AS distance_km
            FROM weather_stations
            ORDER BY distance_km ASC
            LIMIT 1
        ";

        $stmt = $pdo->prepare($sql);
        $stmt->bindParam(':lat', $lat, PDO::PARAM_STR);
        $stmt->bindParam(':lon', $lon, PDO::PARAM_STR);
        $stmt->execute();

        $station = $stmt->fetch();

        if (!$station) {
            writeLog('WARNING', '最寄り観測所が見つかりません', [
                'lat' => $lat,
                'lon' => $lon
            ]);
            sendErrorResponse('最寄りの観測所が見つかりませんでした', 404);
        }

        // 距離を小数点2桁に丸める
        $station['distance_km'] = round(floatval($station['distance_km']), 2);

        writeLog('INFO', '最寄り観測所検索成功', [
            'input_lat' => $lat,
            'input_lon' => $lon,
            'nearest_station' => $station['station_name'],
            'distance_km' => $station['distance_km']
        ]);

        sendSuccessResponse($station, '最寄りの観測所を検索しました');

    } catch (Exception $e) {
        writeLog('ERROR', '最寄り観測所検索エラー', [
            'lat' => $lat ?? null,
            'lon' => $lon ?? null,
            'error' => $e->getMessage()
        ]);
        throw $e;
    }
}

// ===========================
// ユーティリティ関数
// ===========================

/**
 * IDから観測地点を取得
 *
 * @param PDO $pdo データベース接続
 * @param int $locationId 観測地点ID
 * @return array|false 観測地点データ
 */
function getLocationById($pdo, $locationId) {
    $sql = "
        SELECT
            id,
            name,
            latitude,
            longitude,
            prefecture,
            city,
            nearest_station_id,
            nearest_station_name,
            created_at
        FROM locations
        WHERE id = :id
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute(['id' => $locationId]);

    return $stmt->fetch();
}
