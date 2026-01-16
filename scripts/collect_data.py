#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Satellite Data Collection Script
JAXA G-Portalから衛星データ（LST/NDVI）を取得し、JSON形式で出力

機能:
1. JAXA G-Portal APIにログイン
2. 指定された緯度経度のLST・NDVIデータをダウンロード
3. HDF5ファイルを解析してピクセル値を抽出
4. 結果をJSON形式で返す

使用方法:
    python scripts/collect_data.py --lat 32.8032 --lon 130.7075 --date 2026-01-08 --output data.json
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from dotenv import load_dotenv

# .envファイルから環境変数を読み込み
load_dotenv()

# Windows環境でのUTF-8出力設定
if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.buffer, 'strict')

# 必須ライブラリのインポート試行
try:
    import numpy as np
    NUMPY_AVAILABLE = True
except ImportError:
    NUMPY_AVAILABLE = False
    print("⚠️  numpyがインストールされていません", file=sys.stderr)

try:
    import h5py
    H5PY_AVAILABLE = True
except ImportError:
    H5PY_AVAILABLE = False
    print("⚠️  h5pyがインストールされていません", file=sys.stderr)

# gportal-python のインポート試行
try:
    import gportal
    GPORTAL_AVAILABLE = True
except ImportError:
    GPORTAL_AVAILABLE = False
    print("⚠️  gportal-pythonがインストールされていません（モックモードで実行可能）", file=sys.stderr)

# データ保存先ディレクトリ
DATA_DIR = Path(__file__).parent.parent / "data" / "jaxa_downloads"
TEMP_DIR = Path(__file__).parent.parent / "data" / "temp"


def ensure_directories():
    """必要なディレクトリを作成"""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    TEMP_DIR.mkdir(parents=True, exist_ok=True)


def get_gportal_credentials():
    """
    G-Portal認証情報を取得

    Returns:
        tuple: (username, password)
    """
    username = os.environ.get("GPORTAL_USERNAME", "")
    password = os.environ.get("GPORTAL_PASSWORD", "")

    if not username or not password:
        print("\n⚠️  G-Portal認証情報が設定されていません", file=sys.stderr)
        print("   環境変数 GPORTAL_USERNAME と GPORTAL_PASSWORD を設定してください", file=sys.stderr)
        return None, None

    return username, password


def search_and_download_real(lat, lon, target_date, product_type):
    """
    実際のG-Portal APIでデータ検索・ダウンロード

    Args:
        lat: 緯度
        lon: 経度
        target_date: 対象日 (YYYY-MM-DD)
        product_type: プロダクトタイプ ("LST" or "NDVI")

    Returns:
        ダウンロードしたファイルパス or None
    """
    if not GPORTAL_AVAILABLE:
        return None

    try:
        # 認証情報取得
        username, password = get_gportal_credentials()
        if not username or not password:
            return None

        # データセット辞書を取得
        datasets = gportal.datasets()

        # プロダクトタイプに応じたデータセットID取得
        dataset_mapping = {
            "LST": datasets["GCOM-C/SGLI"]["LEVEL2"]["Land area"]["L2-LST"],
            "NDVI": datasets["GCOM-C/SGLI"]["LEVEL2"]["Land area"]["L2-VGI"],
        }

        dataset_id = dataset_mapping.get(product_type)
        if not dataset_id:
            print(f"⚠️  未対応のプロダクトタイプ: {product_type}", file=sys.stderr)
            return None

        # バウンディングボックス設定（座標周辺 ±0.5度）
        bbox = [lon - 0.5, lat - 0.5, lon + 0.5, lat + 0.5]

        print(f"\n🔍 G-Portal検索: {product_type} ({target_date})")

        # データ検索（±1日の範囲）
        start_date = (datetime.fromisoformat(target_date) - timedelta(days=1)).date()
        end_date = (datetime.fromisoformat(target_date) + timedelta(days=1)).date()

        res = gportal.search(
            dataset_ids=dataset_id,
            start_time=f"{start_date}T00:00:00",
            end_time=f"{end_date}T23:59:59",
            bbox=bbox,
            params={}
        )

        products = list(res.products())

        if not products:
            print(f"⚠️  該当するプロダクトが見つかりませんでした", file=sys.stderr)
            return None

        print(f"✓ {len(products)} 件のプロダクトが見つかりました")

        # 認証情報設定
        gportal.username = username
        gportal.password = password

        # 最初のプロダクトをダウンロード
        product = products[0]
        print(f"\n📥 ダウンロード中: {product.id}")

        downloaded_files = gportal.download([product], local_dir=str(TEMP_DIR))

        if downloaded_files:
            print(f"✓ ダウンロード完了: {downloaded_files[0]}")
            return Path(downloaded_files[0])

        return None

    except Exception as e:
        print(f"✗ G-Portal APIエラー: {e}", file=sys.stderr)
        return None


def create_mock_hdf5(lat, lon, target_date, product_type):
    """
    モックHDF5ファイルを作成

    Args:
        lat: 緯度
        lon: 経度
        target_date: 対象日
        product_type: プロダクトタイプ ("LST" or "NDVI")

    Returns:
        モックファイルパス
    """
    if not H5PY_AVAILABLE or not NUMPY_AVAILABLE:
        print("⚠️  h5pyまたはnumpyが必要です", file=sys.stderr)
        return None

    print(f"\n📥 モックデータ生成: {product_type} ({target_date})")

    date_str = target_date.replace('-', '')
    filename = f"GC1SG1_{date_str}01D01D_{product_type}_MOCK.h5"
    output_path = TEMP_DIR / filename

    try:
        with h5py.File(output_path, 'w') as f:
            # Geometry_dataグループ
            geo_group = f.create_group('Geometry_data')

            # 緯度・経度グリッド（100x100）
            lat_range = np.linspace(lat - 0.5, lat + 0.5, 100)
            lon_range = np.linspace(lon - 0.5, lon + 0.5, 100)
            lon_grid, lat_grid = np.meshgrid(lon_range, lat_range)

            geo_group.create_dataset('Latitude', data=lat_grid)
            geo_group.create_dataset('Longitude', data=lon_grid)

            # Image_dataグループ
            img_group = f.create_group('Image_data')

            # データ生成
            if product_type == 'LST':
                # 地表面温度（Kelvin）
                mean_value = 291.5  # 約18.35°C
                std_value = 3.0
                data = np.random.normal(mean_value, std_value, (100, 100))
                data = np.clip(data, 273.0, 320.0)  # 0℃～47℃
                units = 'Kelvin'
                description = 'Land Surface Temperature'
            else:  # NDVI
                mean_value = 0.75
                std_value = 0.08
                data = np.random.normal(mean_value, std_value, (100, 100))
                data = np.clip(data, 0.0, 1.0)
                units = 'dimensionless'
                description = 'Normalized Difference Vegetation Index'

            # データセット作成
            ds = img_group.create_dataset(product_type, data=data)
            ds.attrs['description'] = description
            ds.attrs['units'] = units

        print(f"✓ モックファイル作成完了: {output_path}")
        return output_path

    except Exception as e:
        print(f"✗ モックファイル作成エラー: {e}", file=sys.stderr)
        return None


def extract_pixel_value(hdf5_path, lat, lon, dataset_name):
    """
    HDF5ファイルから指定座標のピクセル値を抽出

    Args:
        hdf5_path: HDF5ファイルパス
        lat: 緯度
        lon: 経度
        dataset_name: データセット名 ("LST" or "NDVI")

    Returns:
        抽出結果辞書
    """
    if not H5PY_AVAILABLE or not NUMPY_AVAILABLE:
        return {"error": "h5pyまたはnumpyが必要です"}

    try:
        with h5py.File(hdf5_path, 'r') as f:
            # データセットパス
            data_path = f'Image_data/{dataset_name}'

            if data_path not in f:
                return {"error": f"データセット {data_path} が見つかりません"}

            # データ読み込み
            dataset = f[data_path]
            data = dataset[:]

            # 緯度経度グリッド取得
            lat_grid = f['Geometry_data/Latitude'][:]
            lon_grid = f['Geometry_data/Longitude'][:]

            # 最も近いピクセルのインデックスを取得
            distances = np.sqrt((lat_grid - lat)**2 + (lon_grid - lon)**2)
            min_idx = np.unravel_index(np.argmin(distances), distances.shape)

            # ピクセル値取得
            pixel_value = float(data[min_idx])

            # 温度の場合はKelvinから摂氏に変換
            if dataset_name == 'LST':
                pixel_value_celsius = pixel_value - 273.15
            else:
                pixel_value_celsius = None

            # 周辺ピクセルの統計（5x5ウィンドウ）
            i, j = min_idx
            window_size = 5
            i_start = max(0, i - window_size // 2)
            i_end = min(data.shape[0], i + window_size // 2 + 1)
            j_start = max(0, j - window_size // 2)
            j_end = min(data.shape[1], j + window_size // 2 + 1)

            window_data = data[i_start:i_end, j_start:j_end]
            window_data_clean = window_data[~np.isnan(window_data)]

            if len(window_data_clean) > 0:
                window_stats = {
                    "mean": float(np.mean(window_data_clean)),
                    "std": float(np.std(window_data_clean)),
                    "min": float(np.min(window_data_clean)),
                    "max": float(np.max(window_data_clean))
                }

                # LSTの場合は摂氏も追加
                if dataset_name == 'LST':
                    window_stats["mean_celsius"] = window_stats["mean"] - 273.15
            else:
                window_stats = None

            result = {
                "dataset": dataset_name,
                "pixel_value": pixel_value,
                "pixel_location": {
                    "row": int(i),
                    "col": int(j),
                    "latitude": float(lat_grid[min_idx]),
                    "longitude": float(lon_grid[min_idx])
                },
                "window_statistics": window_stats
            }

            if pixel_value_celsius is not None:
                result["pixel_value_celsius"] = pixel_value_celsius

            return result

    except Exception as e:
        return {"error": f"データ抽出エラー: {e}"}


def collect_satellite_data(lat, lon, target_date, use_mock=False):
    """
    衛星データを収集

    Args:
        lat: 緯度
        lon: 経度
        target_date: 対象日 (YYYY-MM-DD)
        use_mock: モックモードを使用するか

    Returns:
        収集結果辞書
    """
    result = {
        "location": {
            "latitude": lat,
            "longitude": lon,
            "name": "Observation Point"
        },
        "observation_date": target_date,
        "processing_time": datetime.now().isoformat(),
        "data_source": "mock" if use_mock else "gportal",
        "observations": {}
    }

    # LST（地表面温度）とNDVI（植生指標）を取得
    for product_type in ["LST", "NDVI"]:
        print(f"\n{'='*70}")
        print(f"データ取得: {product_type}")
        print(f"{'='*70}")

        # ファイル取得（実APIまたはモック）
        if use_mock or not GPORTAL_AVAILABLE:
            hdf5_path = create_mock_hdf5(lat, lon, target_date, product_type)
        else:
            hdf5_path = search_and_download_real(lat, lon, target_date, product_type)

        if hdf5_path and hdf5_path.exists():
            # ピクセル値抽出
            print(f"\n📊 データ抽出中...")
            extraction = extract_pixel_value(hdf5_path, lat, lon, product_type)

            if "error" not in extraction:
                result["observations"][product_type.lower()] = extraction
                print(f"✓ {product_type} 取得成功")

                # LSTの場合は摂氏表示
                if product_type == "LST" and "pixel_value_celsius" in extraction:
                    print(f"   値: {extraction['pixel_value_celsius']:.2f}°C")
                else:
                    print(f"   値: {extraction['pixel_value']:.3f}")
            else:
                result["observations"][product_type.lower()] = {"error": extraction["error"]}
                print(f"⚠️  {product_type} 抽出失敗: {extraction['error']}", file=sys.stderr)
        else:
            result["observations"][product_type.lower()] = {"error": "ファイル取得失敗"}
            print(f"⚠️  {product_type} ファイル取得失敗", file=sys.stderr)

    return result


def main():
    parser = argparse.ArgumentParser(
        description="JAXA G-Portalから衛星データを取得してJSON出力"
    )
    parser.add_argument("--lat", type=float, required=True, help="緯度")
    parser.add_argument("--lon", type=float, required=True, help="経度")
    parser.add_argument("--date", type=str, required=True, help="観測日（YYYY-MM-DD）")
    parser.add_argument("--output", type=str, required=True, help="出力先JSONファイル")
    parser.add_argument("--mock", action="store_true",
                       help="モックモードで実行（API未登録時のテスト用）")

    args = parser.parse_args()

    print("\n" + "=" * 70)
    print("Satellite Data Collection Script")
    print("=" * 70)
    print(f"座標: ({args.lat}, {args.lon})")
    print(f"観測日: {args.date}")
    print(f"出力先: {args.output}")
    print(f"モード: {'モック' if args.mock else '実API'}")
    print("=" * 70)

    # ディレクトリ作成
    ensure_directories()

    # 依存ライブラリチェック
    if not NUMPY_AVAILABLE or not H5PY_AVAILABLE:
        print("\n❌ エラー: 必須ライブラリが不足しています", file=sys.stderr)
        print("   pip install numpy h5py でインストールしてください", file=sys.stderr)
        sys.exit(1)

    # データ収集
    result = collect_satellite_data(args.lat, args.lon, args.date, args.mock)

    # JSON出力
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"\n✓ 結果をJSON形式で保存しました: {output_path}")
    print("\n📄 収集データ概要:")
    print(json.dumps(result, indent=2, ensure_ascii=False))

    print("\n" + "=" * 70)
    print("✓ 処理完了")
    print("=" * 70)


if __name__ == "__main__":
    main()
