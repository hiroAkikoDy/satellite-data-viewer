/**
 * Chart Module
 * Chart.jsを使った観測データのグラフ表示（平年値比較機能付き）
 */

let chartInstance = null;
let comparisonChartInstance = null;

/**
 * グラフを表示
 * @param {Object} data - 観測データ
 */
function showChart(data) {
    if (!data || !data.observations || data.observations.length === 0) {
        console.warn('グラフ表示: データがありません');
        return;
    }

    // データを日付順にソート
    const sortedData = data.observations.sort((a, b) => {
        return new Date(a.observation_date) - new Date(b.observation_date);
    });

    // データセット作成（文字列を数値に変換）
    const labels = sortedData.map(obs => obs.observation_date);
    const lstData = sortedData.map(obs => {
        const lstNum = parseFloat(obs.lst);
        return !isNaN(lstNum) && obs.lst !== null ? lstNum : null;
    });
    const ndviData = sortedData.map(obs => {
        const ndviNum = parseFloat(obs.ndvi);
        return !isNaN(ndviNum) && obs.ndvi !== null ? ndviNum * 50 : null;
    }); // NDVIをスケール調整

    // 既存のチャートを破棄
    if (chartInstance) {
        chartInstance.destroy();
    }

    // Chart.jsでグラフを作成
    const ctx = document.getElementById('dataChart');
    if (!ctx) {
        console.error('チャート要素が見つかりません');
        return;
    }

    chartInstance = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [
                {
                    label: 'LST (°C)',
                    data: lstData,
                    borderColor: '#1E88E5',
                    backgroundColor: 'rgba(30, 136, 229, 0.1)',
                    borderWidth: 2,
                    tension: 0.4,
                    yAxisID: 'y'
                },
                {
                    label: 'NDVI (×50)',
                    data: ndviData,
                    borderColor: '#4CAF50',
                    backgroundColor: 'rgba(76, 175, 80, 0.1)',
                    borderWidth: 2,
                    tension: 0.4,
                    yAxisID: 'y1'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                title: {
                    display: true,
                    text: `${data.location.name} - 観測データ時系列`,
                    font: {
                        size: 16,
                        weight: 'bold'
                    }
                },
                legend: {
                    display: true,
                    position: 'top'
                }
            },
            scales: {
                y: {
                    type: 'linear',
                    display: true,
                    position: 'left',
                    title: {
                        display: true,
                        text: '地表面温度 (°C)'
                    }
                },
                y1: {
                    type: 'linear',
                    display: true,
                    position: 'right',
                    title: {
                        display: true,
                        text: 'NDVI (×50)'
                    },
                    grid: {
                        drawOnChartArea: false
                    }
                }
            }
        }
    });

    console.log('✓ グラフを表示しました');
}

/**
 * グラフを閉じる
 */
function closeChart() {
    if (chartInstance) {
        chartInstance.destroy();
        chartInstance = null;
    }

    const chartSection = document.getElementById('chartSection');
    if (chartSection) {
        chartSection.style.display = 'none';
    }
}

/**
 * 平年値との比較グラフを表示
 * @param {number} locationId - 地点ID
 * @param {number} days - 表示日数
 */
async function showComparisonChart(locationId, days = 30) {
    try {
        // 観測データと平年値を並行取得
        const observationsPromise = fetch(`${API_BASE_URL}?action=get_observations&location_id=${locationId}&days=${days}`);

        const observationsResponse = await observationsPromise;
        const observationsResult = await observationsResponse.json();

        if (!observationsResult.success || !observationsResult.data.observations || observationsResult.data.observations.length === 0) {
            console.warn('比較グラフ表示: 観測データがありません');
            return;
        }

        const observations = observationsResult.data.observations;
        const location = observationsResult.data.location;

        // データを日付順にソート
        const sortedObs = observations.sort((a, b) => {
            return new Date(a.observation_date) - new Date(b.observation_date);
        });

        // 各観測日の平年値を取得
        const comparisonData = [];
        for (const obs of sortedObs) {
            try {
                const compResponse = await fetch(`${API_BASE_URL}?action=get_comparison&location_id=${locationId}&date=${obs.observation_date}`);
                const compResult = await compResponse.json();

                if (compResult.success && compResult.data) {
                    const lstValue = parseFloat(obs.lst);
                    const climateMaxTemp = compResult.data.climate_normal
                        ? parseFloat(compResult.data.climate_normal.max_temp)
                        : null;
                    const climateMinTemp = compResult.data.climate_normal
                        ? parseFloat(compResult.data.climate_normal.min_temp)
                        : null;
                    const tempDiff = compResult.data.comparison
                        ? parseFloat(compResult.data.comparison.temperature_difference)
                        : null;

                    // 値が有効な場合のみ追加
                    if (!isNaN(lstValue) && !isNaN(climateMaxTemp) && !isNaN(climateMinTemp) &&
                        climateMaxTemp !== null && climateMinTemp !== null) {
                        comparisonData.push({
                            date: obs.observation_date,
                            lst: lstValue,
                            climate_max_temp: climateMaxTemp,
                            climate_min_temp: climateMinTemp,
                            difference: tempDiff
                        });
                    } else {
                        console.warn(`データ不足 (${obs.observation_date}): LST=${lstValue}, 最高=${climateMaxTemp}, 最低=${climateMinTemp}`);
                    }
                }
            } catch (error) {
                console.warn(`平年値取得エラー (${obs.observation_date}):`, error);
            }
        }

        if (comparisonData.length === 0) {
            console.warn('比較グラフ表示: 平年値データがありません');
            showBasicChart(observationsResult.data); // 基本グラフにフォールバック
            return;
        }

        console.log('✓ 比較データ取得完了:', comparisonData.length + '件');
        console.log('サンプルデータ:', comparisonData[0]);

        // グラフデータ作成
        const labels = comparisonData.map(d => d.date);
        const lstData = comparisonData.map(d => !isNaN(d.lst) ? d.lst : null);
        const climateMaxData = comparisonData.map(d => !isNaN(d.climate_max_temp) ? d.climate_max_temp : null);
        const climateMinData = comparisonData.map(d => !isNaN(d.climate_min_temp) ? d.climate_min_temp : null);

        console.log('グラフデータ準備完了:', {
            labels: labels.length,
            lstData: lstData.filter(v => v !== null).length,
            climateMaxData: climateMaxData.filter(v => v !== null).length,
            climateMinData: climateMinData.filter(v => v !== null).length
        });

        // 既存のチャートを破棄
        if (comparisonChartInstance) {
            comparisonChartInstance.destroy();
        }

        // Chart.jsで比較グラフを作成
        const ctx = document.getElementById('comparisonChart');
        if (!ctx) {
            console.error('比較チャート要素が見つかりません');
            return;
        }

        comparisonChartInstance = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: '衛星観測値（LST）',
                        data: lstData,
                        borderColor: '#1E88E5',
                        backgroundColor: 'rgba(30, 136, 229, 0.1)',
                        borderWidth: 3,
                        tension: 0.3,
                        pointRadius: 4,
                        pointHoverRadius: 6
                    },
                    {
                        label: '平年値（最高気温）',
                        data: climateMaxData,
                        borderColor: '#F44336',
                        backgroundColor: 'rgba(244, 67, 54, 0.1)',
                        borderWidth: 2,
                        borderDash: [5, 5],
                        tension: 0.3,
                        pointRadius: 3,
                        pointHoverRadius: 5
                    },
                    {
                        label: '平年値（最低気温）',
                        data: climateMinData,
                        borderColor: '#2196F3',
                        backgroundColor: 'rgba(33, 150, 243, 0.1)',
                        borderWidth: 2,
                        borderDash: [5, 5],
                        tension: 0.3,
                        pointRadius: 3,
                        pointHoverRadius: 5
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: {
                    mode: 'index',
                    intersect: false
                },
                plugins: {
                    title: {
                        display: true,
                        text: `${location.name} - 観測値と平年値の比較`,
                        font: {
                            size: 16,
                            weight: 'bold'
                        }
                    },
                    legend: {
                        display: true,
                        position: 'top'
                    },
                    tooltip: {
                        callbacks: {
                            afterLabel: function(context) {
                                if (context.datasetIndex === 0) {
                                    const index = context.dataIndex;
                                    const diff = comparisonData[index].difference;
                                    if (diff !== null && diff !== undefined) {
                                        const sign = diff > 0 ? '+' : '';
                                        return `平年差: ${sign}${diff.toFixed(1)}°C`;
                                    }
                                }
                                return '';
                            }
                        }
                    }
                },
                scales: {
                    y: {
                        type: 'linear',
                        display: true,
                        title: {
                            display: true,
                            text: '気温 (°C)',
                            font: {
                                size: 14,
                                weight: 'bold'
                            }
                        },
                        ticks: {
                            callback: function(value) {
                                return value + '°C';
                            }
                        }
                    },
                    x: {
                        display: true,
                        title: {
                            display: true,
                            text: '観測日',
                            font: {
                                size: 14,
                                weight: 'bold'
                            }
                        }
                    }
                }
            }
        });

        // 最新データの比較情報を更新
        updateComparisonSummary(comparisonData[comparisonData.length - 1]);

        console.log('✓ 比較グラフを表示しました');

    } catch (error) {
        console.error('✗ 比較グラフ表示エラー:', error);
    }
}

/**
 * 基本グラフを表示（平年値なし）
 * @param {Object} data - 観測データ
 */
function showBasicChart(data) {
    showChart(data);
}

/**
 * 比較サマリー情報を更新
 * @param {Object} data - 比較データ
 */
function updateComparisonSummary(data) {
    const summaryDiv = document.getElementById('comparisonSummary');
    if (!summaryDiv) {
        console.error('比較サマリー要素が見つかりません');
        return;
    }

    // データの検証
    if (!data) {
        console.error('比較データが空です');
        summaryDiv.innerHTML = '<p class="error-message">データが取得できませんでした</p>';
        return;
    }

    // 数値変換と検証
    const lstValue = parseFloat(data.lst);
    const climateMaxTemp = parseFloat(data.climate_max_temp);
    const climateMinTemp = parseFloat(data.climate_min_temp);
    const diff = parseFloat(data.difference);

    // NaNチェック
    if (isNaN(lstValue) || isNaN(climateMaxTemp) || isNaN(climateMinTemp)) {
        console.error('数値変換エラー:', {
            lst: data.lst,
            climate_max_temp: data.climate_max_temp,
            climate_min_temp: data.climate_min_temp,
            diff: data.difference
        });
        summaryDiv.innerHTML = '<p class="error-message">データの形式が不正です</p>';
        return;
    }

    const diffAbs = Math.abs(diff);

    let statusClass = '';
    let statusIcon = '';
    let statusText = '';

    if (!isNaN(diff)) {
        if (diff > 0) {
            statusClass = 'status-warm';
            statusIcon = '🔥';
            statusText = `平年より${diffAbs.toFixed(1)}°C暖かい`;
        } else if (diff < 0) {
            statusClass = 'status-cool';
            statusIcon = '❄️';
            statusText = `平年より${diffAbs.toFixed(1)}°C涼しい`;
        } else {
            statusClass = 'status-normal';
            statusIcon = '✓';
            statusText = '平年並み';
        }
    } else {
        statusClass = 'status-normal';
        statusIcon = '📊';
        statusText = '差分データなし';
    }

    summaryDiv.innerHTML = `
        <div class="comparison-summary ${statusClass}">
            <div class="summary-row">
                <div class="summary-item">
                    <span class="summary-label">衛星観測値（LST）</span>
                    <span class="summary-value">${lstValue.toFixed(1)}°C</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">平年値（最高気温）</span>
                    <span class="summary-value">${climateMaxTemp.toFixed(1)}°C</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">平年値（最低気温）</span>
                    <span class="summary-value">${climateMinTemp.toFixed(1)}°C</span>
                </div>
            </div>
            <div class="summary-status">
                ${statusIcon} <strong>${statusText}</strong>
            </div>
        </div>
    `;

    console.log('✓ 比較サマリーを更新しました:', {
        lst: lstValue,
        climate_max_temp: climateMaxTemp,
        climate_min_temp: climateMinTemp,
        difference: diff
    });
}
