/**
 * Satellite Data Viewer - Alloy形式的仕様（拡張版）
 *
 * Geminiレビューに基づく改善:
 * 1. 動的な振る舞い（State Transition）の追加
 * 2. アサーション（Assertion）の強化
 * 3. 反例（Counterexample）探索の実装
 *
 * @author Koga Hiroaki
 * @date 2026-01-25
 * @version 2.0
 */

module SatelliteDataViewerEnhanced

open util/ordering[State]

/**
 * ============================================================
 * 1. システム状態の定義（State Transition Modelingの追加）
 * ============================================================
 */

// システムの状態
sig State {
  selected_location: lone Location,        // 現在選択されている地点
  displayed_data: set Observation,         // 画面に表示されているデータ
  map_view: one MapView,                   // 地図の表示状態
  active_filters: set Filter               // 適用中のフィルタ
}

// 地図ビュー
sig MapView {
  center_lat: one Int,
  center_lon: one Int,
  zoom_level: one Int,
  visible_locations: set Location
} {
  // ズームレベルの範囲制約
  zoom_level >= 1 and zoom_level <= 18
}

// データフィルタ
abstract sig Filter {}
sig DateRangeFilter extends Filter {
  start_date: one Date,
  end_date: one Date
} {
  // 日付範囲の整合性
  start_date.order <= end_date.order
}

sig TemperatureRangeFilter extends Filter {
  min_temp: one Int,
  max_temp: one Int
} {
  min_temp <= max_temp
}

// 観測地点
sig Location {
  id: one Int,
  name: one String,
  latitude: one Int,
  longitude: one Int,
  nearest_station: lone WeatherStation
} {
  latitude >= -90000000 and latitude <= 90000000
  longitude >= -180000000 and longitude <= 180000000
}

// 衛星観測データ
sig Observation {
  location: one Location,
  date: one Date,
  lst: one Int,
  ndvi: one Int
} {
  ndvi >= 0 and ndvi <= 1000
}

// 気象観測所
sig WeatherStation {
  station_id: one String,
  station_name: one String,
  latitude: one Int,
  longitude: one Int,
  normals: set ClimateNormal
} {
  latitude >= -90000000 and latitude <= 90000000
  longitude >= -180000000 and longitude <= 180000000
}

// 気象平年値
sig ClimateNormal {
  station: one WeatherStation,
  month: one Int,
  avg_temp: one Int,
  max_temp: one Int,
  min_temp: one Int
} {
  min_temp <= avg_temp and avg_temp <= max_temp
  month >= 1 and month <= 12
}

// 基本型
sig String {}
sig Date {
  order: one Int  // 日付の順序関係
}

/**
 * ============================================================
 * 2. 動的な振る舞い（State Transitions）
 * ============================================================
 */

// 操作: 地点の選択
pred selectLocation[s, s': State, loc: Location] {
  // 事前条件: 地点が地図の可視範囲内にある
  loc in s.map_view.visible_locations

  // 事後条件
  s'.selected_location = loc
  s'.map_view = s.map_view  // 地図ビューは不変
  s'.active_filters = s.active_filters  // フィルタは不変

  // 表示データの更新: 選択地点の観測データを表示
  s'.displayed_data = {o: Observation | o.location = loc and
                       (no s.active_filters or
                        all f: s.active_filters | filterMatches[o, f])}
}

// 操作: 地図の移動
pred moveMap[s, s': State, new_center_lat, new_center_lon: Int] {
  // 事前条件: 座標が有効範囲内
  new_center_lat >= -90000000 and new_center_lat <= 90000000
  new_center_lon >= -180000000 and new_center_lon <= 180000000

  // 事後条件: 地図ビューの更新
  s'.map_view.center_lat = new_center_lat
  s'.map_view.center_lon = new_center_lon
  s'.map_view.zoom_level = s.map_view.zoom_level  // ズームは不変

  // 可視地点の再計算
  s'.map_view.visible_locations = {loc: Location |
    withinBounds[loc, new_center_lat, new_center_lon, s.map_view.zoom_level]}

  // 選択がリセットされる可能性
  s'.selected_location in s'.map_view.visible_locations implies
    s'.selected_location = s.selected_location
  else
    no s'.selected_location

  // 表示データの更新
  some s'.selected_location implies
    s'.displayed_data = {o: Observation | o.location = s'.selected_location}
  else
    no s'.displayed_data
}

// 操作: フィルタの適用
pred applyFilter[s, s': State, f: Filter] {
  // 事前条件: フィルタが未適用
  f not in s.active_filters

  // 事後条件
  s'.active_filters = s.active_filters + f
  s'.map_view = s.map_view
  s'.selected_location = s.selected_location

  // 表示データをフィルタリング
  some s'.selected_location implies
    s'.displayed_data = {o: s.displayed_data | filterMatches[o, f]}
  else
    no s'.displayed_data
}

// 操作: データのエクスポート
pred exportData[s, s': State] {
  // 事前条件: 表示データが存在
  some s.displayed_data

  // 事後条件: 状態は不変（副作用なし）
  s' = s

  // 実際のエクスポート処理は外部効果（Alloyでモデル化不要）
}

/**
 * ============================================================
 * 3. ヘルパー述語
 * ============================================================
 */

// フィルタマッチング判定
pred filterMatches[o: Observation, f: Filter] {
  (f in DateRangeFilter) implies
    (let dr = f :> DateRangeFilter |
      o.date.order >= dr.start_date.order and
      o.date.order <= dr.end_date.order)

  (f in TemperatureRangeFilter) implies
    (let tr = f :> TemperatureRangeFilter |
      o.lst >= tr.min_temp and o.lst <= tr.max_temp)
}

// 地点が地図範囲内にあるか判定
pred withinBounds[loc: Location, center_lat, center_lon, zoom: Int] {
  // 簡略化: ズームレベルに応じた範囲計算
  let range = div[180000000, zoom] |
    (loc.latitude >= center_lat - range and
     loc.latitude <= center_lat + range and
     loc.longitude >= center_lon - range and
     loc.longitude <= center_lon + range)
}

/**
 * ============================================================
 * 4. 不変条件（System Invariants）
 * ============================================================
 */

// INV_STATE1: 選択地点は常に可視範囲内
fact SelectedLocationIsVisible {
  all s: State |
    some s.selected_location implies
      s.selected_location in s.map_view.visible_locations
}

// INV_STATE2: 表示データは選択地点のデータのみ
fact DisplayedDataBelongsToSelectedLocation {
  all s: State |
    all o: s.displayed_data |
      some s.selected_location implies
        o.location = s.selected_location
}

// INV_STATE3: フィルタが適用されている場合、表示データはフィルタ条件を満たす
fact DisplayedDataMatchesFilters {
  all s: State |
    all o: s.displayed_data |
      all f: s.active_filters |
        filterMatches[o, f]
}

// INV_DATA1: 観測データの一意性
fact UniqueObservation {
  no disj o1, o2: Observation |
    o1.location = o2.location and o1.date = o2.date
}

// INV_DATA2: 平年値の完全性（各観測所に12ヶ月分）
fact ClimateNormalCompleteness {
  all ws: WeatherStation |
    #ws.normals = 12 and
    (all m: Int | m >= 1 and m <= 12 implies
      one cn: ws.normals | cn.month = m)
}

/**
 * ============================================================
 * 5. アサーション（Assertions） - Geminiレビュー対応
 * ============================================================
 */

// AS1: 地点選択後、必ずそのデータが表示される
assert LocationSelectionShowsData {
  all s, s': State, loc: Location |
    selectLocation[s, s', loc] implies
      (some s'.displayed_data and
       all o: s'.displayed_data | o.location = loc)
}

// AS2: 地図移動で選択が失われる場合、表示データもクリアされる
assert MapMoveConsistency {
  all s, s': State, lat, lon: Int |
    moveMap[s, s', lat, lon] implies
      (no s'.selected_location implies no s'.displayed_data)
}

// AS3: フィルタ適用後、すべての表示データがフィルタ条件を満たす
assert FilterConsistency {
  all s, s': State, f: Filter |
    applyFilter[s, s', f] implies
      all o: s'.displayed_data | filterMatches[o, f]
}

// AS4: エクスポート操作は状態を変更しない
assert ExportDoesNotModifyState {
  all s, s': State |
    exportData[s, s'] implies s' = s
}

// AS5: 座標範囲外の地点は絶対に選択できない
assert InvalidLocationCannotBeSelected {
  all s, s': State, loc: Location |
    (loc.latitude < -90000000 or loc.latitude > 90000000 or
     loc.longitude < -180000000 or loc.longitude > 180000000)
    implies
      not selectLocation[s, s', loc]
}

// AS6: 日付範囲フィルタの逆転は発生しない
assert DateRangeFilterValidity {
  all f: DateRangeFilter |
    f.start_date.order <= f.end_date.order
}

// AS7: 温度範囲フィルタの逆転は発生しない
assert TemperatureRangeFilterValidity {
  all f: TemperatureRangeFilter |
    f.min_temp <= f.max_temp
}

// AS8: 平年値の論理的整合性（最低 ≤ 平均 ≤ 最高）
assert ClimateNormalLogicalConsistency {
  all cn: ClimateNormal |
    cn.min_temp <= cn.avg_temp and cn.avg_temp <= cn.max_temp
}

/**
 * ============================================================
 * 6. 検証コマンド（Checks） - 反例探索
 * ============================================================
 */

// 検証1: 地点選択のデータ表示保証
check LocationSelectionShowsData for 5 but 3 State

// 検証2: 地図移動の整合性
check MapMoveConsistency for 5 but 3 State

// 検証3: フィルタの整合性
check FilterConsistency for 5 but 3 State, 2 Filter

// 検証4: エクスポートの副作用なし
check ExportDoesNotModifyState for 5 but 3 State

// 検証5: 無効な地点の選択不可
check InvalidLocationCannotBeSelected for 5

// 検証6-8: データ構造の妥当性
check DateRangeFilterValidity for 5
check TemperatureRangeFilterValidity for 5
check ClimateNormalLogicalConsistency for 5

/**
 * ============================================================
 * 7. シナリオ実行（Run Commands） - 動的振る舞いの検証
 * ============================================================
 */

// シナリオ1: 地点選択からデータ表示までの正常フロー
run NormalFlowScenario {
  some s, s': State, loc: Location |
    selectLocation[s, s', loc] and
    some s'.displayed_data
} for 5 but 3 State

// シナリオ2: 地図移動による選択解除
run MapMoveClearsSelection {
  some s, s', s'': State, lat, lon: Int |
    some s.selected_location and
    moveMap[s, s', lat, lon] and
    no s'.selected_location
} for 5 but 3 State

// シナリオ3: フィルタ適用によるデータ絞り込み
run FilterReducesData {
  some s, s': State, f: Filter |
    #s.displayed_data > 1 and
    applyFilter[s, s', f] and
    #s'.displayed_data < #s.displayed_data
} for 5 but 3 State, 2 Filter

// シナリオ4: 複数フィルタの連続適用
run MultipleFiltersApplied {
  some s, s', s'': State, f1, f2: Filter |
    applyFilter[s, s', f1] and
    applyFilter[s', s'', f2] and
    #s''.active_filters = 2
} for 5 but 4 State, 3 Filter

// シナリオ5: データエクスポートの実行
run ExportAfterSelection {
  some s, s': State |
    some s.selected_location and
    some s.displayed_data and
    exportData[s, s']
} for 5 but 3 State

/**
 * ============================================================
 * 8. 障害シナリオ（Obstacle Scenarios） - KAOS連携
 * ============================================================
 */

// 障害1: 衛星データが取得できない
pred ObstacleNoSatelliteData[s: State, loc: Location] {
  loc in s.map_view.visible_locations and
  no o: Observation | o.location = loc
}

// 障害2: 座標がずれている
pred ObstacleCoordinateMismatch[o: Observation, ws: WeatherStation] {
  o.location.nearest_station = ws and
  (abs[o.location.latitude - ws.latitude] > 1000000 or  // 1度以上のズレ
   abs[o.location.longitude - ws.longitude] > 1000000)
}

// 障害3: フィルタ適用後にデータが空
pred ObstacleFilterResultsEmpty[s, s': State, f: Filter] {
  some s.displayed_data and
  applyFilter[s, s', f] and
  no s'.displayed_data
}

// 障害シナリオの検証
run ObstacleNoDataScenario {
  some s: State, loc: Location |
    ObstacleNoSatelliteData[s, loc]
} for 5

run ObstacleCoordinateMismatchScenario {
  some o: Observation, ws: WeatherStation |
    ObstacleCoordinateMismatch[o, ws]
} for 5

run ObstacleEmptyFilterResultScenario {
  some s, s': State, f: Filter |
    ObstacleFilterResultsEmpty[s, s', f]
} for 5 but 3 State

/**
 * ============================================================
 * 9. パフォーマンス制約の検証
 * ============================================================
 */

// PERF1: 可視地点数の上限（パフォーマンス対策）
fact MaxVisibleLocations {
  all s: State |
    #s.map_view.visible_locations <= 100
}

// PERF2: 表示データの上限
fact MaxDisplayedData {
  all s: State |
    #s.displayed_data <= 1000
}

// PERF3: 同時適用フィルタ数の上限
fact MaxActiveFilters {
  all s: State |
    #s.active_filters <= 5
}

/**
 * ============================================================
 * 期待される検証結果
 * ============================================================
 *
 * すべてのcheckコマンド: No counterexample found
 * → システムの動的振る舞いが論理的に整合している
 *
 * runコマンド: インスタンス生成成功
 * → 各シナリオが実現可能であることを確認
 *
 * 障害シナリオ: インスタンス生成成功
 * → 障害が発生しうることを確認し、回避策の必要性を示す
 */

// ヘルパー関数
fun abs[n: Int]: Int {
  n >= 0 implies n else -n
}

fun div[a, b: Int]: Int {
  // 簡略化: 実際の除算は実装レベル
  a
}
