/**
 * Map Module
 * Leaflet.jsを使った地図表示と観測地点マーカー管理
 */

// グローバル変数
let map = null;
let markers = [];
// API_BASE_URL は app.js で定義されています

/**
 * 地図を初期化
 */
function initMap() {
    // Leaflet地図の初期化
    map = L.map('map').setView([35.6762, 139.6503], 5);

    // OpenStreetMapタイルレイヤーを追加
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        maxZoom: 18,
        minZoom: 3
    }).addTo(map);

    console.log('✓ 地図を初期化しました');
}

/**
 * LST値に基づいてマーカーの色を決定
 * @param {number|string} lst - 地表面温度（℃）
 * @returns {string} カラーコード
 */
function getMarkerColor(lst) {
    // 数値に変換
    const lstNum = parseFloat(lst);

    // 数値でない場合はグレー
    if (isNaN(lstNum) || lst === null || lst === undefined) {
        return '#9E9E9E'; // グレー（データなし）
    }

    if (lstNum < 10) return '#2196F3';  // 青
    if (lstNum < 20) return '#4CAF50';  // 緑
    if (lstNum < 30) return '#FFEB3B';  // 黄
    if (lstNum < 40) return '#FF9800';  // オレンジ
    return '#F44336';  // 赤
}

/**
 * カスタムマーカーアイコンを作成
 * @param {number|string} lst - 地表面温度（℃）
 * @returns {L.DivIcon} Leafletアイコン
 */
function createCustomMarker(lst) {
    // 数値に変換
    const lstNum = parseFloat(lst);

    // 数値として有効かチェック
    const isValidNumber = !isNaN(lstNum) && lst !== null && lst !== undefined;

    const color = getMarkerColor(lst);
    const label = isValidNumber ? lstNum.toFixed(1) + '°C' : 'N/A';

    const html = `
        <div class="custom-marker" style="background-color: ${color};">
            <span class="marker-label">${label}</span>
        </div>
    `;

    return L.divIcon({
        html: html,
        className: 'custom-marker-wrapper',
        iconSize: [50, 50],
        iconAnchor: [25, 50],
        popupAnchor: [0, -50]
    });
}

/**
 * マーカーのポップアップコンテンツを生成
 * @param {Object} location - 地点情報
 * @param {Object} latestData - 最新観測データ
 * @returns {string} HTMLコンテンツ
 */
function createPopupContent(location, latestData) {
    let content = `
        <div class="popup-content">
            <h3>${location.name}</h3>
            <p class="popup-location">
                📍 ${location.prefecture || ''} ${location.city || ''}<br>
                緯度: ${parseFloat(location.latitude).toFixed(4)}, 経度: ${parseFloat(location.longitude).toFixed(4)}
            </p>
    `;

    if (latestData && latestData.observations && latestData.observations.length > 0) {
        const latest = latestData.observations[0];

        // LST値を数値に変換
        const lstNum = parseFloat(latest.lst);
        const lstDisplay = !isNaN(lstNum) && latest.lst !== null
            ? lstNum.toFixed(1) + '°C'
            : 'データなし';

        // NDVI値を数値に変換
        const ndviNum = parseFloat(latest.ndvi);
        const ndviDisplay = !isNaN(ndviNum) && latest.ndvi !== null
            ? ndviNum.toFixed(3)
            : 'データなし';

        content += `
            <div class="popup-data">
                <p><strong>最新観測日:</strong> ${latest.observation_date}</p>
                <p><strong>LST:</strong> ${lstDisplay}</p>
                <p><strong>NDVI:</strong> ${ndviDisplay}</p>
            </div>
        `;
    } else {
        content += `<p class="popup-no-data">観測データがありません</p>`;
    }

    content += `
            <button class="popup-btn" onclick="showLocationDetail(${location.id})">詳細を表示</button>
        </div>
    `;

    return content;
}

/**
 * 観測地点一覧をAPIから取得してマーカーを配置
 */
async function loadLocations() {
    try {
        console.log('📡 観測地点データを取得中...');

        // 既存のマーカーをクリア
        markers.forEach(marker => map.removeLayer(marker));
        markers = [];

        // API呼び出し
        const response = await fetch(`${API_BASE_URL}?action=get_locations`);
        const result = await response.json();

        if (!result.success) {
            throw new Error(result.error || 'データ取得に失敗しました');
        }

        const locations = result.data;
        console.log(`✓ ${locations.length}件の観測地点を取得しました`);

        if (locations.length === 0) {
            showModal('通知', '観測地点が登録されていません。サイドバーから地点を追加してください。');
            return;
        }

        // 各地点にマーカーを配置
        for (const location of locations) {
            await addMarkerForLocation(location);
        }

        // 地図の表示範囲を全マーカーが見えるように調整
        if (markers.length > 0) {
            const group = new L.featureGroup(markers);
            map.fitBounds(group.getBounds().pad(0.1));
        }

    } catch (error) {
        console.error('✗ 観測地点の取得エラー:', error);
        showModal('エラー', `観測地点の取得に失敗しました: ${error.message}`);
    }
}

/**
 * 特定の地点にマーカーを追加
 * @param {Object} location - 地点情報
 */
async function addMarkerForLocation(location) {
    try {
        // 最新観測データを取得
        const days = document.getElementById('periodSelect').value;
        const response = await fetch(`${API_BASE_URL}?action=get_observations&location_id=${location.id}&days=${days}`);
        const result = await response.json();

        let latestLST = null;

        if (result.success && result.data.observations && result.data.observations.length > 0) {
            const latest = result.data.observations[0];
            // 文字列から数値に変換（バックエンドから文字列で返される可能性があるため）
            latestLST = latest.lst !== null ? parseFloat(latest.lst) : null;
        }

        // カスタムマーカーを作成
        const icon = createCustomMarker(latestLST);
        const marker = L.marker([location.latitude, location.longitude], { icon: icon });

        // ポップアップを設定
        const popupContent = createPopupContent(location, result.data);
        marker.bindPopup(popupContent, {
            maxWidth: 300,
            className: 'custom-popup'
        });

        // マーカークリックイベント
        marker.on('click', function() {
            // グラフ表示などの追加処理はここで実装
            console.log(`マーカークリック: ${location.name}`);
        });

        // 地図に追加
        marker.addTo(map);
        markers.push(marker);

    } catch (error) {
        console.error(`✗ マーカー追加エラー (${location.name}):`, error);
    }
}

/**
 * 地点の詳細情報を表示
 * @param {number} locationId - 地点ID
 */
async function showLocationDetail(locationId) {
    try {
        // グローバル変数に地点IDを保存（CSVエクスポート用）
        window.currentLocationId = locationId;

        const days = document.getElementById('periodSelect').value;
        const response = await fetch(`${API_BASE_URL}?action=get_observations&location_id=${locationId}&days=${days}`);
        const result = await response.json();

        if (!result.success) {
            throw new Error(result.error);
        }

        // データテーブルを更新
        updateDataTable(result.data);

        // 基本グラフを表示（chart.js が実装されている場合）
        if (typeof showChart === 'function') {
            showChart(result.data);
        }

        // グラフセクションを表示
        const chartSection = document.getElementById('chartSection');
        if (chartSection) {
            chartSection.style.display = 'block';
            chartSection.scrollIntoView({ behavior: 'smooth' });
        }

        // 比較グラフを表示（最寄り観測所が設定されている場合）
        if (result.data.location.nearest_station_id) {
            if (typeof showComparisonChart === 'function') {
                showComparisonChart(locationId, parseInt(days));

                // 比較セクションを表示
                const comparisonSection = document.getElementById('comparisonSection');
                if (comparisonSection) {
                    comparisonSection.style.display = 'block';

                    // 期間選択ラジオボタンに地点IDを設定
                    const periodRadios = document.querySelectorAll('input[name="comparisonPeriod"]');
                    periodRadios.forEach(radio => {
                        radio.dataset.locationId = locationId;
                        radio.checked = (parseInt(radio.value) === parseInt(days));
                    });
                }
            }
        }

    } catch (error) {
        console.error('✗ 詳細表示エラー:', error);
        showModal('エラー', `詳細情報の取得に失敗しました: ${error.message}`);
    }
}

/**
 * データテーブルを更新
 * @param {Object} data - 観測データ
 */
function updateDataTable(data) {
    const tbody = document.getElementById('dataTableBody');
    tbody.innerHTML = '';

    if (!data.observations || data.observations.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="no-data-cell">データがありません</td></tr>';
        return;
    }

    data.observations.forEach(obs => {
        // LST値を数値に変換
        const lstNum = parseFloat(obs.lst);
        const lstDisplay = !isNaN(lstNum) && obs.lst !== null
            ? lstNum.toFixed(1) + '°C'
            : '-';

        // NDVI値を数値に変換
        const ndviNum = parseFloat(obs.ndvi);
        const ndviDisplay = !isNaN(ndviNum) && obs.ndvi !== null
            ? ndviNum.toFixed(3)
            : '-';

        const row = document.createElement('tr');
        row.innerHTML = `
            <td>${data.location.name}</td>
            <td>${obs.observation_date}</td>
            <td>${lstDisplay}</td>
            <td>${ndviDisplay}</td>
            <td>-</td>
            <td>
                <button class="btn-small" onclick="showLocationDetail(${data.location.id})">詳細</button>
            </td>
        `;
        tbody.appendChild(row);
    });
}

/**
 * 地図を更新
 */
function refreshMap() {
    console.log('🔄 地図を更新中...');
    loadLocations();
}

/**
 * 初期化処理
 */
document.addEventListener('DOMContentLoaded', function() {
    // 地図を初期化
    initMap();

    // 観測地点を読み込み
    loadLocations();

    // 更新ボタンのイベントリスナー
    const refreshBtn = document.getElementById('refreshBtn');
    if (refreshBtn) {
        refreshBtn.addEventListener('click', refreshMap);
    }

    // 表示期間変更のイベントリスナー
    const periodSelect = document.getElementById('periodSelect');
    if (periodSelect) {
        periodSelect.addEventListener('change', refreshMap);
    }

    console.log('✓ Map モジュールを初期化しました');
});
