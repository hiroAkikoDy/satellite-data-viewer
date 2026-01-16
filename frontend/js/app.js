/**
 * Application Module
 * 共通機能とユーティリティ関数
 */

const API_BASE_URL = '../backend/api.php';

// エラーメッセージ定義
const errorMessages = {
    latitudeRange: '緯度は-90〜90の範囲で入力してください。日本国内は24〜46です。',
    longitudeRange: '経度は-180〜180の範囲で入力してください。日本国内は122〜154です。',
    latitudeFormat: '緯度は数値で入力してください（例: 32.8032）',
    longitudeFormat: '経度は数値で入力してください（例: 130.7075）',
    nameRequired: '地点名を入力してください。',
    networkError: 'サーバーとの通信に失敗しました。しばらくしてから再度お試しください。',
    duplicateLocation: 'この緯度経度は既に登録されています。'
};

/**
 * モーダルを表示
 * @param {string} title - タイトル
 * @param {string} message - メッセージ
 */
function showModal(title, message) {
    const modal = document.getElementById('modal');
    const modalTitle = document.getElementById('modalTitle');
    const modalMessage = document.getElementById('modalMessage');

    modalTitle.textContent = title;
    modalMessage.textContent = message;
    modal.classList.add('show');
}

/**
 * モーダルを閉じる
 */
function closeModal() {
    const modal = document.getElementById('modal');
    modal.classList.remove('show');
}

/**
 * バリデーションエラーを表示
 * @param {Array} errors - エラーメッセージの配列
 */
function showErrors(errors) {
    const errorDiv = document.getElementById('validation-errors');
    errorDiv.innerHTML = '';

    if (errors.length > 0) {
        errorDiv.style.display = 'block';
        errorDiv.innerHTML = '<ul>' +
            errors.map(e => `<li>${e}</li>`).join('') +
            '</ul>';
    } else {
        errorDiv.style.display = 'none';
    }
}

/**
 * 地点情報をバリデーション
 * @param {string} name - 地点名
 * @param {number|string} lat - 緯度
 * @param {number|string} lon - 経度
 * @returns {Array} エラーメッセージの配列
 */
function validateLocation(name, lat, lon) {
    const errors = [];

    // 地点名チェック
    if (!name || name.trim() === '') {
        errors.push(errorMessages.nameRequired);
    }

    // 緯度チェック
    const latNum = parseFloat(lat);
    if (isNaN(latNum)) {
        errors.push(errorMessages.latitudeFormat);
    } else if (latNum < -90 || latNum > 90) {
        errors.push(errorMessages.latitudeRange);
    }

    // 経度チェック
    const lonNum = parseFloat(lon);
    if (isNaN(lonNum)) {
        errors.push(errorMessages.longitudeFormat);
    } else if (lonNum < -180 || lonNum > 180) {
        errors.push(errorMessages.longitudeRange);
    }

    return errors;
}

/**
 * 日本国外チェック（警告）
 * @param {number} lat - 緯度
 * @param {number} lon - 経度
 * @returns {boolean} 日本国内の場合true
 */
function isJapanRegion(lat, lon) {
    const latNum = parseFloat(lat);
    const lonNum = parseFloat(lon);

    return (latNum >= 24 && latNum <= 46) && (lonNum >= 122 && lonNum <= 154);
}

/**
 * 最寄りの気象観測所を検索
 * @param {number} lat - 緯度
 * @param {number} lon - 経度
 */
async function findNearestStation(lat, lon) {
    try {
        const response = await fetch(`${API_BASE_URL}?action=find_nearest_station&lat=${lat}&lon=${lon}`);
        const result = await response.json();

        if (result.success && result.data) {
            const stationInput = document.getElementById('nearestStation');
            if (stationInput) {
                stationInput.value = `${result.data.station_name} (${result.data.distance_km}km)`;
            }

            // 隠しフィールドに観測所IDを設定
            let hiddenInput = document.getElementById('nearestStationId');
            if (!hiddenInput) {
                hiddenInput = document.createElement('input');
                hiddenInput.type = 'hidden';
                hiddenInput.id = 'nearestStationId';
                hiddenInput.name = 'nearest_station_id';
                document.getElementById('addLocationForm').appendChild(hiddenInput);
            }
            hiddenInput.value = result.data.station_id;
        }
    } catch (error) {
        console.warn('最寄り観測所の検索に失敗しました:', error);
    }
}

/**
 * 観測地点追加フォームのハンドラー
 */
async function handleAddLocation(event) {
    event.preventDefault();

    // エラー表示をクリア
    showErrors([]);

    const formData = new FormData(event.target);
    const name = formData.get('name');
    const latitude = formData.get('latitude');
    const longitude = formData.get('longitude');

    // バリデーション
    const errors = validateLocation(name, latitude, longitude);
    if (errors.length > 0) {
        showErrors(errors);
        return;
    }

    // 日本国外警告
    if (!isJapanRegion(latitude, longitude)) {
        if (!confirm('入力された緯度経度は日本国外です。続けますか？')) {
            return;
        }
    }

    const data = {
        name: name,
        latitude: parseFloat(latitude),
        longitude: parseFloat(longitude),
        prefecture: formData.get('prefecture') || null,
        city: formData.get('city') || null,
        nearest_station_id: formData.get('nearest_station_id') || null
    };

    try {
        const response = await fetch(`${API_BASE_URL}?action=add_location`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });

        const result = await response.json();

        if (!result.success) {
            throw new Error(result.error || '地点の追加に失敗しました');
        }

        showModal('成功', '観測地点を追加しました');
        event.target.reset();

        // 最寄り観測所フィールドもクリア
        const stationInput = document.getElementById('nearestStation');
        if (stationInput) {
            stationInput.value = '';
        }

        // 地図を更新
        if (typeof refreshMap === 'function') {
            refreshMap();
        }

    } catch (error) {
        console.error('✗ 地点追加エラー:', error);
        if (error.message.includes('Duplicate')) {
            showErrors([errorMessages.duplicateLocation]);
        } else {
            showModal('エラー', `地点の追加に失敗しました: ${error.message}`);
        }
    }
}

/**
 * CSVエクスポート処理
 */
async function handleExportCSV() {
    try {
        // 現在選択されている地点IDを取得
        const locationId = window.currentLocationId;

        if (!locationId) {
            showModal('エラー', '地点を選択してください。地図上のマーカーをクリックして「詳細を表示」を選択してください。');
            return;
        }

        // 期間の取得
        const days = document.getElementById('periodSelect').value;
        const endDate = new Date();
        const startDate = new Date();
        startDate.setDate(startDate.getDate() - parseInt(days));

        // 日付をYYYY-MM-DD形式に変換
        const formatDate = (date) => {
            const year = date.getFullYear();
            const month = String(date.getMonth() + 1).padStart(2, '0');
            const day = String(date.getDate()).padStart(2, '0');
            return `${year}-${month}-${day}`;
        };

        // CSVエクスポートURLを構築
        const url = `${API_BASE_URL}?action=export_csv&location_id=${locationId}&start_date=${formatDate(startDate)}&end_date=${formatDate(endDate)}`;

        // ダウンロード実行
        window.location.href = url;

        console.log('✓ CSVエクスポートを開始しました:', {
            locationId,
            startDate: formatDate(startDate),
            endDate: formatDate(endDate)
        });

    } catch (error) {
        console.error('✗ CSVエクスポートエラー:', error);
        showModal('エラー', `CSVエクスポートに失敗しました: ${error.message}`);
    }
}

/**
 * 初期化処理
 */
document.addEventListener('DOMContentLoaded', function() {
    console.log('✓ アプリケーションを初期化しました');

    // フォーム送信イベント
    const addLocationForm = document.getElementById('addLocationForm');
    if (addLocationForm) {
        addLocationForm.addEventListener('submit', handleAddLocation);
    }

    // リアルタイムバリデーション
    const latInput = document.getElementById('latitude');
    const lonInput = document.getElementById('longitude');
    const nameInput = document.getElementById('locationName');

    // 緯度のリアルタイムバリデーション
    if (latInput) {
        latInput.addEventListener('blur', function() {
            const latNum = parseFloat(this.value);
            if (!isNaN(latNum)) {
                if (latNum < -90 || latNum > 90) {
                    this.classList.add('error');
                    showErrors([errorMessages.latitudeRange]);
                } else {
                    this.classList.remove('error');
                    // 経度も入力済みなら最寄り観測所を検索
                    const lonNum = parseFloat(lonInput.value);
                    if (!isNaN(lonNum)) {
                        findNearestStation(latNum, lonNum);
                    }
                }
            }
        });

        latInput.addEventListener('input', function() {
            this.classList.remove('error');
        });
    }

    // 経度のリアルタイムバリデーション
    if (lonInput) {
        lonInput.addEventListener('blur', function() {
            const lonNum = parseFloat(this.value);
            if (!isNaN(lonNum)) {
                if (lonNum < -180 || lonNum > 180) {
                    this.classList.add('error');
                    showErrors([errorMessages.longitudeRange]);
                } else {
                    this.classList.remove('error');
                    // 緯度も入力済みなら最寄り観測所を検索
                    const latNum = parseFloat(latInput.value);
                    if (!isNaN(latNum)) {
                        findNearestStation(latNum, lonNum);
                    }
                }
            }
        });

        lonInput.addEventListener('input', function() {
            this.classList.remove('error');
        });
    }

    // 地点名のバリデーション
    if (nameInput) {
        nameInput.addEventListener('blur', function() {
            if (!this.value || this.value.trim() === '') {
                this.classList.add('error');
            } else {
                this.classList.remove('error');
            }
        });

        nameInput.addEventListener('input', function() {
            this.classList.remove('error');
        });
    }

    // CSVエクスポートボタン
    const exportBtn = document.getElementById('exportBtn');
    if (exportBtn) {
        exportBtn.addEventListener('click', handleExportCSV);
    }

    // モーダル閉じるボタン
    const modalClose = document.querySelector('.modal-close');
    if (modalClose) {
        modalClose.addEventListener('click', closeModal);
    }

    // モーダル外クリックで閉じる
    const modal = document.getElementById('modal');
    if (modal) {
        modal.addEventListener('click', function(event) {
            if (event.target === modal) {
                closeModal();
            }
        });
    }

    // グラフ閉じるボタン
    const closeChartBtn = document.getElementById('closeChartBtn');
    if (closeChartBtn) {
        closeChartBtn.addEventListener('click', function() {
            document.getElementById('chartSection').style.display = 'none';
        });
    }

    // 比較グラフ閉じるボタン
    const closeComparisonBtn = document.getElementById('closeComparisonBtn');
    if (closeComparisonBtn) {
        closeComparisonBtn.addEventListener('click', function() {
            document.getElementById('comparisonSection').style.display = 'none';
        });
    }

    // 比較期間変更イベント
    const periodRadios = document.querySelectorAll('input[name="comparisonPeriod"]');
    periodRadios.forEach(radio => {
        radio.addEventListener('change', function() {
            const locationId = parseInt(this.dataset.locationId);
            const days = parseInt(this.value);
            if (locationId && days) {
                if (typeof showComparisonChart === 'function') {
                    showComparisonChart(locationId, days);
                }
            }
        });
    });
});
