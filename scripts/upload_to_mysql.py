#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MySQL Upload Script
collect_data.py が出力したJSONファイルをMySQLにアップロード

機能:
1. collect_data.py が出力したJSONファイルを読み込む
2. MySQL（リモート or ローカル）に接続
3. observations テーブルにINSERT
4. 重複チェック（ON DUPLICATE KEY UPDATE）
5. エラー時はローカルCSVにバックアップ

使用方法:
    python scripts/upload_to_mysql.py --input data.json --location-id 1
"""

import argparse
import csv
import json
import sys
from datetime import datetime
from pathlib import Path
from dotenv import load_dotenv
import os

# .envファイルから環境変数を読み込み
load_dotenv()

# Windows環境でのUTF-8出力設定
if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.buffer, 'strict')

# MySQL接続ライブラリのインポート試行
try:
    import pymysql
    pymysql.install_as_MySQLdb()
    PYMYSQL_AVAILABLE = True
except ImportError:
    PYMYSQL_AVAILABLE = False
    print("⚠️  pymysqlがインストールされていません", file=sys.stderr)
    print("   pip install pymysql でインストールしてください", file=sys.stderr)

# バックアップディレクトリ
BACKUP_DIR = Path(__file__).parent.parent / "data" / "backup"


def ensure_backup_directory():
    """バックアップディレクトリを作成"""
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)


def get_mysql_config():
    """
    .envファイルからMySQL接続情報を取得

    Returns:
        dict: MySQL接続設定
    """
    config = {
        'host': os.environ.get('MYSQL_HOST', 'localhost'),
        'user': os.environ.get('MYSQL_USER', 'root'),
        'password': os.environ.get('MYSQL_PASSWORD', ''),
        'database': os.environ.get('MYSQL_DATABASE', 'satellite_viewer'),
        'port': int(os.environ.get('MYSQL_PORT', 3306)),
        'charset': 'utf8mb4',
    }

    # 必須項目チェック
    if not config['password']:
        print("\n⚠️  MySQL接続情報が不完全です", file=sys.stderr)
        print("   .envファイルに以下を設定してください:", file=sys.stderr)
        print("   - MYSQL_HOST", file=sys.stderr)
        print("   - MYSQL_USER", file=sys.stderr)
        print("   - MYSQL_PASSWORD", file=sys.stderr)
        print("   - MYSQL_DATABASE", file=sys.stderr)

    return config


def connect_to_mysql(config):
    """
    MySQLに接続

    Args:
        config: MySQL接続設定

    Returns:
        connection: MySQL接続オブジェクト
    """
    if not PYMYSQL_AVAILABLE:
        raise ImportError("pymysqlがインストールされていません")

    try:
        connection = pymysql.connect(
            host=config['host'],
            user=config['user'],
            password=config['password'],
            database=config['database'],
            port=config['port'],
            charset=config['charset'],
            cursorclass=pymysql.cursors.DictCursor
        )

        print(f"✓ MySQL接続成功: {config['user']}@{config['host']}:{config['port']}/{config['database']}")
        return connection

    except pymysql.Error as e:
        print(f"✗ MySQL接続エラー: {e}", file=sys.stderr)
        raise


def load_json_data(json_path):
    """
    JSONファイルを読み込む

    Args:
        json_path: JSONファイルパス

    Returns:
        dict: JSONデータ
    """
    json_path = Path(json_path)

    if not json_path.exists():
        raise FileNotFoundError(f"JSONファイルが見つかりません: {json_path}")

    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    print(f"✓ JSONファイル読み込み成功: {json_path}")
    return data


def extract_observation_data(json_data):
    """
    JSONデータから観測データを抽出

    Args:
        json_data: collect_data.py が出力したJSONデータ

    Returns:
        dict: 観測データ（observation_date, lst, ndvi）
    """
    observation = {
        'observation_date': json_data.get('observation_date'),
        'lst': None,
        'ndvi': None
    }

    # LSTデータ抽出
    if 'observations' in json_data and 'lst' in json_data['observations']:
        lst_data = json_data['observations']['lst']
        if 'error' not in lst_data and 'pixel_value_celsius' in lst_data:
            observation['lst'] = round(lst_data['pixel_value_celsius'], 2)

    # NDVIデータ抽出
    if 'observations' in json_data and 'ndvi' in json_data['observations']:
        ndvi_data = json_data['observations']['ndvi']
        if 'error' not in ndvi_data and 'pixel_value' in ndvi_data:
            observation['ndvi'] = round(ndvi_data['pixel_value'], 3)

    return observation


def insert_observation(connection, location_id, observation):
    """
    observations テーブルにデータを挿入

    Args:
        connection: MySQL接続
        location_id: 観測地点ID
        observation: 観測データ

    Returns:
        bool: 成功したかどうか
    """
    try:
        with connection.cursor() as cursor:
            sql = """
                INSERT INTO observations (
                    location_id,
                    observation_date,
                    lst,
                    ndvi
                ) VALUES (
                    %s, %s, %s, %s
                )
                ON DUPLICATE KEY UPDATE
                    lst = VALUES(lst),
                    ndvi = VALUES(ndvi)
            """

            cursor.execute(sql, (
                location_id,
                observation['observation_date'],
                observation['lst'],
                observation['ndvi']
            ))

            connection.commit()

            # INSERT か UPDATE かを判定
            if cursor.rowcount == 1:
                print(f"✓ 新規データ挿入: {observation['observation_date']}")
            elif cursor.rowcount == 2:
                print(f"✓ データ更新: {observation['observation_date']}")
            else:
                print(f"⚠️  データに変更なし: {observation['observation_date']}")

            return True

    except pymysql.Error as e:
        print(f"✗ データ挿入エラー: {e}", file=sys.stderr)
        connection.rollback()
        return False


def save_to_csv_backup(observation, location_id, error_message=None):
    """
    エラー時にCSVバックアップを保存

    Args:
        observation: 観測データ
        location_id: 観測地点ID
        error_message: エラーメッセージ
    """
    ensure_backup_directory()

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_file = BACKUP_DIR / f"backup_{timestamp}.csv"

    fieldnames = ['location_id', 'observation_date', 'lst', 'ndvi', 'error']

    # CSVに書き込み
    file_exists = backup_file.exists()

    with open(backup_file, 'a', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)

        if not file_exists:
            writer.writeheader()

        writer.writerow({
            'location_id': location_id,
            'observation_date': observation['observation_date'],
            'lst': observation['lst'],
            'ndvi': observation['ndvi'],
            'error': error_message or ''
        })

    print(f"✓ CSVバックアップ保存: {backup_file}")


def verify_location_exists(connection, location_id):
    """
    location_id が locations テーブルに存在するか確認

    Args:
        connection: MySQL接続
        location_id: 観測地点ID

    Returns:
        bool: 存在するかどうか
    """
    try:
        with connection.cursor() as cursor:
            sql = "SELECT id, name FROM locations WHERE id = %s"
            cursor.execute(sql, (location_id,))
            result = cursor.fetchone()

            if result:
                print(f"✓ 観測地点確認: ID={result['id']}, 名前={result['name']}")
                return True
            else:
                print(f"⚠️  観測地点が見つかりません: ID={location_id}", file=sys.stderr)
                return False

    except pymysql.Error as e:
        print(f"✗ 観測地点確認エラー: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="collect_data.py のJSON出力をMySQLにアップロード"
    )
    parser.add_argument("--input", type=str, required=True,
                       help="入力JSONファイル（collect_data.pyの出力）")
    parser.add_argument("--location-id", type=int, required=True,
                       help="観測地点ID（locationsテーブルのid）")
    parser.add_argument("--backup-only", action="store_true",
                       help="MySQLへのアップロードをスキップし、CSVバックアップのみ保存")

    args = parser.parse_args()

    print("\n" + "=" * 70)
    print("MySQL Upload Script")
    print("=" * 70)
    print(f"入力ファイル: {args.input}")
    print(f"観測地点ID: {args.location_id}")
    print(f"バックアップのみ: {args.backup_only}")
    print("=" * 70)

    try:
        # JSONデータ読み込み
        json_data = load_json_data(args.input)

        # 観測データ抽出
        observation = extract_observation_data(json_data)

        print(f"\n📊 抽出データ:")
        print(f"   観測日: {observation['observation_date']}")
        print(f"   LST: {observation['lst']}°C" if observation['lst'] else "   LST: 取得失敗")
        print(f"   NDVI: {observation['ndvi']}" if observation['ndvi'] else "   NDVI: 取得失敗")

        # バックアップのみモード
        if args.backup_only:
            print("\n📁 CSVバックアップモード")
            save_to_csv_backup(observation, args.location_id)
            print("\n✓ バックアップ完了")
            return

        # MySQL接続設定取得
        mysql_config = get_mysql_config()

        # pymysqlチェック
        if not PYMYSQL_AVAILABLE:
            print("\n❌ エラー: pymysqlが必要です", file=sys.stderr)
            print("   pip install pymysql でインストールしてください", file=sys.stderr)

            # CSVバックアップに保存
            print("\n📁 CSVバックアップに保存します")
            save_to_csv_backup(observation, args.location_id, error_message="pymysql未インストール")
            sys.exit(1)

        # MySQL接続
        connection = None
        try:
            connection = connect_to_mysql(mysql_config)

            # 観測地点存在確認
            if not verify_location_exists(connection, args.location_id):
                raise ValueError(f"観測地点ID={args.location_id} が存在しません")

            # データ挿入
            print(f"\n📤 MySQLにアップロード中...")
            success = insert_observation(connection, args.location_id, observation)

            if success:
                print("\n✓ アップロード成功")
            else:
                raise RuntimeError("データ挿入に失敗しました")

        except Exception as e:
            print(f"\n✗ MySQL処理エラー: {e}", file=sys.stderr)
            print("\n📁 CSVバックアップに保存します")
            save_to_csv_backup(observation, args.location_id, error_message=str(e))
            sys.exit(1)

        finally:
            if connection:
                connection.close()
                print("✓ MySQL接続クローズ")

    except Exception as e:
        print(f"\n✗ 致命的なエラー: {e}", file=sys.stderr)
        sys.exit(1)

    print("\n" + "=" * 70)
    print("✓ 処理完了")
    print("=" * 70)


if __name__ == "__main__":
    main()
