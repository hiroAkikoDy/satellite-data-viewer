/**
 * Satellite Data Viewer - Alloy形式的仕様
 *
 * このモデルは、衛星データビューワーの要求仕様を形式的に記述し、
 * 論理的な整合性を検証するためのものです。
 *
 * @author Koga Hiroaki
 * @date 2026-01-16
 * @version 1.0
 */

module SatelliteDataViewer

/**
 * ============================================================
 * 1. ドメインモデルの定義
 * ============================================================
 */

// 観測地点
sig Location {
  id: one Int,
  name: one String,
  latitude: one Int,   // 整数で表現（実数の代用: 度 * 10^6）
  longitude: one Int,
  nearest_station: lone WeatherStation
} {
  // 不変条件 INV2, INV3: 座標範囲
  latitude >= -90000000 and latitude <= 90000000     // -90度 ～ 90度
  longitude >= -180000000 and longitude <= 180000000 // -180度 ～ 180度

  // 日本国内推奨範囲
  // latitude >= 24000000 and latitude <= 46000000   // 24度 ～ 46度
  // longitude >= 122000000 and longitude <= 154000000 // 122度 ～ 154度
}

// 衛星観測データ
sig Observation {
  location: one Location,
  date: one Date,
  lst: one Int,   // Land Surface Temperature (℃ * 10)
  ndvi: one Int   // NDVI (0.0～1.0 を 0～1000 で表現)
} {
  // NDVI範囲制約: 0.0 ～ 1.0
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
  avg_temp: one Int,  // 平均気温 (℃ * 10)
  max_temp: one Int,  // 最高気温 (℃ * 10)
  min_temp: one Int   // 最低気温 (℃ * 10)
} {
  // 不変条件 INV5: 最低 ≤ 最高
  min_temp <= max_temp

  // 不変条件 INV4: 月の範囲
  month >= 1 and month <= 12

  // 論理的整合性: 最低 ≤ 平均 ≤ 最高
  min_temp <= avg_temp and avg_temp <= max_temp
}

// 基本型（抽象型）
sig String {}
sig Date {}

/**
 * ============================================================
 * 2. 制約条件（Facts）
 * ============================================================
 */

// C1: 観測データの一意性（同一地点・同一日付の重複禁止）
fact UniqueObservation {
  no disj o1, o2: Observation |
    o1.location = o2.location and o1.date = o2.date
}

// C2: 参照整合性（外部キー制約）
fact ReferentialIntegrity {
  // すべての観測データは有効な地点に紐付く
  all o: Observation | o.location in Location

  // すべての平年値は有効な観測所に紐付く
  all cn: ClimateNormal | cn.station in WeatherStation

  // 逆参照の整合性
  all cn: ClimateNormal | cn in cn.station.normals
}

// C3: 平年値の完全性（各観測所に12ヶ月分のデータが存在）
fact ClimateNormalCompleteness {
  all ws: WeatherStation |
    #ws.normals = 12 and
    (all m: Int | m >= 1 and m <= 12 implies
      one cn: ws.normals | cn.month = m)
}

// C4: 最寄り観測所の存在性
fact NearestStationExists {
  all loc: Location | one loc.nearest_station
}

// C5: 地点IDの一意性
fact UniqueLocationID {
  no disj l1, l2: Location | l1.id = l2.id
}

// C6: 観測所IDの一意性
fact UniqueStationID {
  no disj s1, s2: WeatherStation | s1.station_id = s2.station_id
}

/**
 * ============================================================
 * 3. 操作の事前条件・事後条件（Predicates）
 * ============================================================
 */

// O1: 観測地点の追加
pred addLocation[
  loc, loc': Location,
  lat, lon: Int
] {
  // 事前条件
  lat >= -90000000 and lat <= 90000000
  lon >= -180000000 and lon <= 180000000

  // 事後条件
  loc'.latitude = lat
  loc'.longitude = lon
  loc' in Location'
}

// O2: 衛星観測データの追加
pred addObservation[
  obs, obs': Observation,
  loc: Location,
  d: Date,
  lst_val, ndvi_val: Int
] {
  // 事前条件
  loc in Location
  ndvi_val >= 0 and ndvi_val <= 1000

  // 一意性制約（同じ地点・日付のデータは存在しない）
  no o: Observation | o.location = loc and o.date = d

  // 事後条件
  obs'.location = loc
  obs'.date = d
  obs'.lst = lst_val
  obs'.ndvi = ndvi_val
  obs' in Observation'
}

// O3: 平年値との比較
pred compareWithNormal[
  obs: Observation,
  normal: ClimateNormal,
  difference: Int
] {
  // 事前条件: 観測地点の最寄り観測所と平年値の観測所が一致
  obs.location.nearest_station = normal.station

  // 観測日の月と平年値の月が一致
  extractMonth[obs.date] = normal.month

  // 事後条件: 差分 = 観測値 - 平年値（平均）
  difference = obs.lst - normal.avg_temp
}

// O4: 最寄り観測所の検索
pred findNearestStation[
  loc: Location,
  stations: set WeatherStation,
  result: WeatherStation
] {
  // 事前条件: 観測所が1つ以上存在
  #stations > 0

  // 事後条件: resultは最小距離の観測所
  result in stations
  all other: stations - result |
    haversineDistance[loc.latitude, loc.longitude,
                      result.latitude, result.longitude] <=
    haversineDistance[loc.latitude, loc.longitude,
                      other.latitude, other.longitude]
}

/**
 * ============================================================
 * 4. ヘルパー述語・関数
 * ============================================================
 */

// 日付から月を抽出（抽象化）
fun extractMonth[d: Date]: Int {
  // 実装レベルでは date('m', strtotime($date))
  // ここでは1～12の整数を返すと仮定
  let m = d.~date.month | m
}

// Haversine距離（抽象化）
pred haversineDistance[lat1, lon1, lat2, lon2: Int] {
  // 実際の計算式:
  // 6371 * acos(cos(radians(lat1)) * cos(radians(lat2)) *
  //             cos(radians(lon2) - radians(lon1)) +
  //             sin(radians(lat1)) * sin(radians(lat2)))
  // Alloyでは抽象化して「距離関係」のみを表現
}

/**
 * ============================================================
 * 5. セキュリティ制約
 * ============================================================
 */

// セキュリティ関連のシグネチャ
abstract sig Attacker {}
one sig SQLInjectionAttacker extends Attacker {}
one sig XSSAttacker extends Attacker {}

sig UserInput {
  value: one String,
  is_sanitized: one Bool
}

sig SQLQuery {
  uses_prepared_statement: one Bool,
  has_user_input: set UserInput
}

sig HTMLOutput {
  content: set String,
  is_escaped: one Bool
}

abstract sig Bool {}
one sig True, False extends Bool {}

// SC1: すべてのSQL文はプリペアドステートメントを使用
fact AllQueriesUsePreparedStatements {
  all q: SQLQuery | q.uses_prepared_statement = True
}

// SC2: ユーザー入力を含むSQL文は必ずサニタイズ
fact UserInputMustBeSanitized {
  all q: SQLQuery, input: q.has_user_input |
    input.is_sanitized = True
}

// SC3: HTML出力は必ずエスケープ
fact HTMLOutputMustBeEscaped {
  all output: HTMLOutput | output.is_escaped = True
}

/**
 * ============================================================
 * 6. 安全性プロパティの検証（Assertions）
 * ============================================================
 */

// P1: データ不整合の不在
assert NoDataInconsistency {
  // すべての観測データは有効な地点に紐付く
  all o: Observation | o.location in Location

  // すべての平年値で min ≤ max
  all cn: ClimateNormal | cn.min_temp <= cn.max_temp
}

// P2: 重複観測データの不在
assert NoObservationDuplication {
  no disj o1, o2: Observation |
    o1.location = o2.location and o1.date = o2.date
}

// P3: 座標範囲違反の不在
assert NoCoordinateViolation {
  all loc: Location |
    loc.latitude >= -90000000 and loc.latitude <= 90000000 and
    loc.longitude >= -180000000 and loc.longitude <= 180000000

  all ws: WeatherStation |
    ws.latitude >= -90000000 and ws.latitude <= 90000000 and
    ws.longitude >= -180000000 and ws.longitude <= 180000000
}

// P4: 平年値の論理的整合性
assert ClimateNormalConsistency {
  all cn: ClimateNormal |
    cn.min_temp <= cn.avg_temp and cn.avg_temp <= cn.max_temp
}

// P5: 平年値の完全性
assert ClimateNormalCompletenessAssertion {
  all ws: WeatherStation | #ws.normals = 12
}

// SP1: SQLインジェクションは常に防がれる
assert SQLInjectionAlwaysPrevented {
  all q: SQLQuery | q.uses_prepared_statement = True

  // プリペアドステートメント使用時、攻撃は成功しない
  no q: SQLQuery |
    q.uses_prepared_statement = True and
    (some input: q.has_user_input | input.is_sanitized = False)
}

// SP2: XSSは常に防がれる
assert XSSAlwaysPrevented {
  all output: HTMLOutput | output.is_escaped = True

  // エスケープ済み出力にスクリプトタグは含まれない
  no output: HTMLOutput |
    output.is_escaped = True and
    (some content: output.content | content in ScriptTag)
}

sig ScriptTag extends String {}

/**
 * ============================================================
 * 7. 検証コマンド
 * ============================================================
 */

// 検証1: データ不整合がないことを確認
check NoDataInconsistency for 5

// 検証2: 重複観測データがないことを確認
check NoObservationDuplication for 5

// 検証3: 座標範囲違反がないことを確認
check NoCoordinateViolation for 5

// 検証4: 平年値の整合性を確認
check ClimateNormalConsistency for 5

// 検証5: 平年値の完全性を確認
check ClimateNormalCompletenessAssertion for 5

// 検証6: SQLインジェクション防御
check SQLInjectionAlwaysPrevented for 5

// 検証7: XSS防御
check XSSAlwaysPrevented for 5

/**
 * ============================================================
 * 8. シナリオ実行例（Run Commands）
 * ============================================================
 */

// シナリオ1: 正常な観測地点追加（日本国内）
run AddLocationScenarioJapan {
  some loc: Location |
    loc.latitude >= 24000000 and loc.latitude <= 46000000 and
    loc.longitude >= 122000000 and loc.longitude <= 154000000 and
    one loc.nearest_station
} for 3

// シナリオ2: 平年値比較が成功
run ComparisonScenario {
  some obs: Observation, cn: ClimateNormal |
    obs.location.nearest_station = cn.station and
    extractMonth[obs.date] = cn.month
} for 3

// シナリオ3: 異常検出（平年値から大幅乖離 > 5℃）
run AnomalyDetectionScenario {
  some obs: Observation, cn: ClimateNormal |
    obs.location.nearest_station = cn.station and
    extractMonth[obs.date] = cn.month and
    let diff = obs.lst - cn.avg_temp |
      diff > 50 or diff < -50  // 5.0℃ * 10 = 50
} for 3

// シナリオ4: 複数地点での観測
run MultiLocationObservation {
  #Location > 1 and
  #Observation > 1 and
  (all o: Observation | one o.location)
} for 4

// シナリオ5: 観測所の平年値完全性
run WeatherStationWithCompleteNormals {
  some ws: WeatherStation |
    #ws.normals = 12 and
    (all m: Int | m >= 1 and m <= 12 implies
      one cn: ws.normals | cn.month = m)
} for 3 but exactly 1 WeatherStation, exactly 12 ClimateNormal

/**
 * ============================================================
 * 9. テストケース生成
 * ============================================================
 */

// TC1: 境界値テスト（緯度・経度の限界値）
run BoundaryValueTest {
  some loc: Location |
    (loc.latitude = -90000000 or loc.latitude = 90000000) and
    (loc.longitude = -180000000 or loc.longitude = 180000000)
} for 3

// TC2: NDVI境界値テスト
run NDVIBoundaryTest {
  some obs: Observation |
    obs.ndvi = 0 or obs.ndvi = 1000
} for 3

// TC3: 平年値の整合性テスト（最低 = 平均 = 最高のケース）
run ClimateNormalEqualityTest {
  some cn: ClimateNormal |
    cn.min_temp = cn.avg_temp and cn.avg_temp = cn.max_temp
} for 3

/**
 * ============================================================
 * 10. カバレッジ分析用のラン
 * ============================================================
 */

// すべての制約を満たすインスタンスを生成
run ValidInstance {
  #Location >= 2 and
  #Observation >= 2 and
  #WeatherStation >= 1 and
  #ClimateNormal = 12
} for 5

/**
 * ============================================================
 * 検証結果の期待値（コメント）
 * ============================================================
 *
 * すべてのcheckコマンドは「No counterexample found」を返すべき。
 * これは、仕様が論理的に整合していることを意味する。
 *
 * runコマンドは、制約を満たすインスタンスを生成する。
 * これにより、仕様が実現可能であることを確認できる。
 */
