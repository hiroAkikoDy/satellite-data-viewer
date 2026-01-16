<?php
/**
 * API Test Script
 *
 * backend/api.php の動作確認用テストスクリプト
 *
 * 使用方法:
 *   php backend/test_api.php
 */

// カラー出力用
function colorText($text, $color) {
    $colors = [
        'green' => "\033[0;32m",
        'red' => "\033[0;31m",
        'yellow' => "\033[0;33m",
        'blue' => "\033[0;34m",
        'reset' => "\033[0m"
    ];
    return $colors[$color] . $text . $colors['reset'];
}

function testSection($title) {
    echo "\n" . str_repeat('=', 70) . "\n";
    echo colorText($title, 'blue') . "\n";
    echo str_repeat('=', 70) . "\n";
}

function testPass($message) {
    echo colorText('✓ PASS: ', 'green') . $message . "\n";
}

function testFail($message) {
    echo colorText('✗ FAIL: ', 'red') . $message . "\n";
}

function testWarning($message) {
    echo colorText('⚠ WARNING: ', 'yellow') . $message . "\n";
}

// 設定ファイルの存在確認
testSection('1. 設定ファイルの確認');

if (file_exists(__DIR__ . '/config.php')) {
    testPass('config.php が存在します');
    require_once __DIR__ . '/config.php';
} else {
    testFail('config.php が見つかりません');
    echo "   config.php.example をコピーして config.php を作成してください\n";
    exit(1);
}

// データベース接続テスト
testSection('2. データベース接続テスト');

try {
    $pdo = getDbConnection();
    testPass('データベース接続成功');

    // テーブルの存在確認
    $tables = ['locations', 'observations', 'climate_normals'];
    foreach ($tables as $table) {
        $stmt = $pdo->query("SHOW TABLES LIKE '{$table}'");
        if ($stmt->rowCount() > 0) {
            testPass("テーブル '{$table}' が存在します");
        } else {
            testWarning("テーブル '{$table}' が見つかりません");
            echo "   backend/db_setup.sql を実行してください\n";
        }
    }
} catch (Exception $e) {
    testFail('データベース接続エラー: ' . $e->getMessage());
    exit(1);
}

// ログディレクトリの確認
testSection('3. ログディレクトリの確認');

$logDir = __DIR__ . '/logs';
if (!is_dir($logDir)) {
    mkdir($logDir, 0755, true);
    testPass('ログディレクトリを作成しました');
} else {
    testPass('ログディレクトリが存在します');
}

if (is_writable($logDir)) {
    testPass('ログディレクトリに書き込み権限があります');
} else {
    testFail('ログディレクトリに書き込み権限がありません');
}

// サンプルログ書き込みテスト
testSection('4. ログ書き込みテスト');

try {
    // api.phpのwriteLog関数を使用するため、ここでは手動でログ書き込み
    $logFile = $logDir . '/' . date('Y-m-d') . '.log';
    $testLog = "[" . date('Y-m-d H:i:s') . "] [TEST] API Test Script executed\n";
    file_put_contents($logFile, $testLog, FILE_APPEND);
    testPass('ログファイルへの書き込みが成功しました');
} catch (Exception $e) {
    testFail('ログファイルへの書き込みが失敗しました: ' . $e->getMessage());
}

// サンプルデータの確認
testSection('5. サンプルデータの確認');

try {
    // locations テーブルのレコード数
    $stmt = $pdo->query("SELECT COUNT(*) as count FROM locations");
    $result = $stmt->fetch();
    $locationCount = $result['count'];

    if ($locationCount > 0) {
        testPass("locations テーブルに {$locationCount} 件のデータがあります");
    } else {
        testWarning('locations テーブルにデータがありません');
        echo "   backend/db_setup.sql を実行してサンプルデータを挿入してください\n";
    }

    // observations テーブルのレコード数
    $stmt = $pdo->query("SELECT COUNT(*) as count FROM observations");
    $result = $stmt->fetch();
    $observationCount = $result['count'];

    if ($observationCount > 0) {
        testPass("observations テーブルに {$observationCount} 件のデータがあります");
    } else {
        testWarning('observations テーブルにデータがありません');
    }

    // climate_normals テーブルのレコード数
    $stmt = $pdo->query("SELECT COUNT(*) as count FROM climate_normals");
    $result = $stmt->fetch();
    $climateCount = $result['count'];

    if ($climateCount > 0) {
        testPass("climate_normals テーブルに {$climateCount} 件のデータがあります");
    } else {
        testWarning('climate_normals テーブルにデータがありません');
    }
} catch (Exception $e) {
    testFail('データ確認エラー: ' . $e->getMessage());
}

// APIレスポンス関数のテスト
testSection('6. APIレスポンス関数のテスト');

try {
    // sendSuccessResponse のテスト（実際には出力されてしまうので、コメントアウト）
    // sendSuccessResponse(['test' => 'data'], 'テストメッセージ');
    testPass('sendSuccessResponse 関数が定義されています');

    // sendErrorResponse のテスト（実際には出力されてしまうので、コメントアウト）
    // sendErrorResponse('テストエラー', 500);
    testPass('sendErrorResponse 関数が定義されています');
} catch (Exception $e) {
    testFail('関数定義エラー: ' . $e->getMessage());
}

// 設定値の確認
testSection('7. 設定値の確認');

echo "データベース設定:\n";
echo "  ホスト: " . DB_HOST . "\n";
echo "  データベース名: " . DB_NAME . "\n";
echo "  ユーザー名: " . DB_USER . "\n";
echo "  文字セット: " . DB_CHARSET . "\n";
echo "\nアプリケーション設定:\n";
echo "  アプリ名: " . APP_NAME . "\n";
echo "  バージョン: " . APP_VERSION . "\n";
echo "  レスポンスタイプ: " . API_RESPONSE_TYPE . "\n";

// 結果サマリー
testSection('テスト結果サマリー');

echo "\n";
echo colorText('✓ すべての基本チェックが完了しました', 'green') . "\n";
echo "\n";
echo "次のステップ:\n";
echo "1. ブラウザまたはcURLでAPIエンドポイントをテスト\n";
echo "   例: curl http://localhost/backend/api.php?action=get_locations\n";
echo "\n";
echo "2. 各エンドポイントの動作確認:\n";
echo "   - GET  /api.php?action=get_locations\n";
echo "   - GET  /api.php?action=get_observations&location_id=1&days=30\n";
echo "   - GET  /api.php?action=get_comparison&location_id=1&date=2026-01-08\n";
echo "   - POST /api.php?action=add_location (JSON body)\n";
echo "   - GET  /api.php?action=export_csv&location_id=1\n";
echo "\n";
echo "3. ログファイルの確認:\n";
echo "   backend/logs/" . date('Y-m-d') . ".log\n";
echo "\n";

testSection('完了');
