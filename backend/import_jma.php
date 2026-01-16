<?php
/**
 * JMA Climate Normals Data Import Script
 *
 * 気象庁平年値データをCSVファイルから読み込み、MySQLデータベースに挿入します。
 *
 * 機能:
 * - data/jma_normals/ ディレクトリ内の全CSVファイルを処理
 * - climate_normals テーブルへのINSERT
 * - 重複データの自動更新（ON DUPLICATE KEY UPDATE）
 * - 詳細なログ出力とエラーハンドリング
 *
 * 使用方法:
 *   php backend/import_jma.php
 */

// エラー表示設定（開発環境用）
error_reporting(E_ALL);
ini_set('display_errors', 1);

// タイムゾーン設定
date_default_timezone_set('Asia/Tokyo');

// 設定ファイルの読み込み
require_once __DIR__ . '/config.php';

// ===========================
// 定数定義
// ===========================

// CSVファイルのディレクトリパス
define('JMA_DATA_DIR', __DIR__ . '/../data/jma_normals/');

// ログファイルパス
define('LOG_FILE', __DIR__ . '/../logs/import_jma_' . date('Ymd_His') . '.log');

// CSVフォーマット定義
define('CSV_COLUMNS', [
    'station_id',
    'station_name',
    'month',
    'avg_temp',
    'max_temp',
    'min_temp',
    'precipitation'
]);

// ===========================
// ユーティリティ関数
// ===========================

/**
 * ログメッセージを出力
 *
 * @param string $message ログメッセージ
 * @param string $level ログレベル（INFO, WARNING, ERROR）
 */
function writeLog($message, $level = 'INFO') {
    $timestamp = date('Y-m-d H:i:s');
    $logMessage = "[{$timestamp}] [{$level}] {$message}" . PHP_EOL;

    // コンソール出力
    echo $logMessage;

    // ログディレクトリが存在しない場合は作成
    $logDir = dirname(LOG_FILE);
    if (!is_dir($logDir)) {
        mkdir($logDir, 0755, true);
    }

    // ファイルに追記
    file_put_contents(LOG_FILE, $logMessage, FILE_APPEND);
}

/**
 * データベース接続を取得
 *
 * @return PDO データベース接続オブジェクト
 * @throws Exception 接続失敗時
 */
function getDbConnection() {
    try {
        $dsn = "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4";
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false
        ]);

        writeLog("データベース接続成功: " . DB_NAME);
        return $pdo;

    } catch (PDOException $e) {
        writeLog("データベース接続エラー: " . $e->getMessage(), 'ERROR');
        throw $e;
    }
}

/**
 * CSVファイルを読み込んでデータベースに挿入
 *
 * @param PDO $pdo データベース接続
 * @param string $filePath CSVファイルパス
 * @return array 処理結果（inserted, updated, errors）
 */
function importCsvFile($pdo, $filePath) {
    $stats = [
        'inserted' => 0,
        'updated' => 0,
        'errors' => 0,
        'skipped' => 0
    ];

    writeLog("CSVファイル処理開始: " . basename($filePath));

    // ファイルの存在確認
    if (!file_exists($filePath)) {
        writeLog("ファイルが見つかりません: {$filePath}", 'ERROR');
        $stats['errors']++;
        return $stats;
    }

    // ファイルを開く
    $handle = fopen($filePath, 'r');
    if ($handle === false) {
        writeLog("ファイルを開けません: {$filePath}", 'ERROR');
        $stats['errors']++;
        return $stats;
    }

    // BOM削除（UTF-8 BOM対応）
    $bom = fread($handle, 3);
    if ($bom !== "\xEF\xBB\xBF") {
        rewind($handle);
    }

    // ヘッダー行をスキップ
    $header = fgetcsv($handle);
    if ($header === false) {
        writeLog("ヘッダー行の読み込みに失敗: {$filePath}", 'ERROR');
        fclose($handle);
        $stats['errors']++;
        return $stats;
    }

    // プリペアドステートメント準備
    $sql = "
        INSERT INTO climate_normals (
            station_id,
            station_name,
            month,
            avg_temp,
            max_temp,
            min_temp,
            precipitation
        ) VALUES (
            :station_id,
            :station_name,
            :month,
            :avg_temp,
            :max_temp,
            :min_temp,
            :precipitation
        )
        ON DUPLICATE KEY UPDATE
            station_name = VALUES(station_name),
            avg_temp = VALUES(avg_temp),
            max_temp = VALUES(max_temp),
            min_temp = VALUES(min_temp),
            precipitation = VALUES(precipitation)
    ";

    try {
        $stmt = $pdo->prepare($sql);
    } catch (PDOException $e) {
        writeLog("SQL準備エラー: " . $e->getMessage(), 'ERROR');
        fclose($handle);
        $stats['errors']++;
        return $stats;
    }

    // 行番号カウンタ（エラーメッセージ用）
    $lineNumber = 1;

    // データ行を1行ずつ処理
    while (($row = fgetcsv($handle)) !== false) {
        $lineNumber++;

        // 空行スキップ
        if (empty(array_filter($row))) {
            $stats['skipped']++;
            continue;
        }

        // カラム数チェック
        if (count($row) < 7) {
            writeLog("行 {$lineNumber}: カラム数が不足しています（期待: 7, 実際: " . count($row) . "）", 'WARNING');
            $stats['errors']++;
            continue;
        }

        // データバインド用の配列作成
        $data = [
            'station_id' => trim($row[0]),
            'station_name' => trim($row[1]),
            'month' => (int)trim($row[2]),
            'avg_temp' => is_numeric(trim($row[3])) ? (float)trim($row[3]) : null,
            'max_temp' => is_numeric(trim($row[4])) ? (float)trim($row[4]) : null,
            'min_temp' => is_numeric(trim($row[5])) ? (float)trim($row[5]) : null,
            'precipitation' => is_numeric(trim($row[6])) ? (float)trim($row[6]) : null
        ];

        // バリデーション
        if (empty($data['station_id']) || empty($data['station_name'])) {
            writeLog("行 {$lineNumber}: station_id または station_name が空です", 'WARNING');
            $stats['errors']++;
            continue;
        }

        if ($data['month'] < 1 || $data['month'] > 12) {
            writeLog("行 {$lineNumber}: 月の値が不正です（{$data['month']}）", 'WARNING');
            $stats['errors']++;
            continue;
        }

        // データベースに挿入/更新
        try {
            $stmt->execute($data);

            // INSERT か UPDATE かを判定
            if ($stmt->rowCount() === 1) {
                $stats['inserted']++;
            } elseif ($stmt->rowCount() === 2) {
                // ON DUPLICATE KEY UPDATE が実行された場合は rowCount() = 2
                $stats['updated']++;
            } else {
                // データに変更がない場合
                $stats['skipped']++;
            }

        } catch (PDOException $e) {
            writeLog("行 {$lineNumber}: DB挿入エラー - " . $e->getMessage(), 'ERROR');
            $stats['errors']++;
        }
    }

    fclose($handle);

    writeLog("CSVファイル処理完了: " . basename($filePath) .
             " (挿入: {$stats['inserted']}, 更新: {$stats['updated']}, エラー: {$stats['errors']}, スキップ: {$stats['skipped']})");

    return $stats;
}

/**
 * ディレクトリ内の全CSVファイルを処理
 *
 * @param PDO $pdo データベース接続
 * @return array 全体の統計情報
 */
function importAllCsvFiles($pdo) {
    $totalStats = [
        'files_processed' => 0,
        'inserted' => 0,
        'updated' => 0,
        'errors' => 0,
        'skipped' => 0
    ];

    // ディレクトリの存在確認
    if (!is_dir(JMA_DATA_DIR)) {
        writeLog("データディレクトリが存在しません: " . JMA_DATA_DIR, 'ERROR');
        return $totalStats;
    }

    // CSVファイル一覧取得
    $csvFiles = glob(JMA_DATA_DIR . '*.csv');

    if (empty($csvFiles)) {
        writeLog("CSVファイルが見つかりません: " . JMA_DATA_DIR, 'WARNING');
        return $totalStats;
    }

    writeLog("CSVファイル数: " . count($csvFiles) . "個");

    // トランザクション開始
    $pdo->beginTransaction();

    try {
        foreach ($csvFiles as $csvFile) {
            $stats = importCsvFile($pdo, $csvFile);

            $totalStats['files_processed']++;
            $totalStats['inserted'] += $stats['inserted'];
            $totalStats['updated'] += $stats['updated'];
            $totalStats['errors'] += $stats['errors'];
            $totalStats['skipped'] += $stats['skipped'];
        }

        // コミット
        $pdo->commit();
        writeLog("トランザクションコミット成功");

    } catch (Exception $e) {
        // ロールバック
        $pdo->rollBack();
        writeLog("トランザクションロールバック: " . $e->getMessage(), 'ERROR');
        throw $e;
    }

    return $totalStats;
}

// ===========================
// メイン処理
// ===========================

try {
    writeLog("========================================");
    writeLog("JMA Climate Normals Import 開始");
    writeLog("========================================");

    $startTime = microtime(true);

    // データベース接続
    $pdo = getDbConnection();

    // CSV一括インポート
    $stats = importAllCsvFiles($pdo);

    // 処理時間計算
    $endTime = microtime(true);
    $elapsedTime = round($endTime - $startTime, 2);

    // 最終結果出力
    writeLog("========================================");
    writeLog("処理完了");
    writeLog("========================================");
    writeLog("処理ファイル数: {$stats['files_processed']}");
    writeLog("新規挿入: {$stats['inserted']} 件");
    writeLog("更新: {$stats['updated']} 件");
    writeLog("スキップ: {$stats['skipped']} 件");
    writeLog("エラー: {$stats['errors']} 件");
    writeLog("処理時間: {$elapsedTime} 秒");
    writeLog("========================================");

    // エラーがあった場合は終了コード1
    exit($stats['errors'] > 0 ? 1 : 0);

} catch (Exception $e) {
    writeLog("致命的なエラー: " . $e->getMessage(), 'ERROR');
    writeLog("スタックトレース: " . $e->getTraceAsString(), 'ERROR');
    exit(1);
}
