#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Satellite Data Viewer - 要求工学分析スクリプト
NetworkXによるゴール依存関係とコンポーネント依存関係の構造的解析
"""

import networkx as nx
import matplotlib.pyplot as plt
import json
from pathlib import Path

# 日本語フォント設定
plt.rcParams['font.sans-serif'] = ['MS Gothic', 'Yu Gothic', 'Meiryo', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

def build_goal_dependency_graph():
    """KAOSゴール依存関係グラフの構築"""
    G = nx.DiGraph()

    # ゴール定義
    goals = {
        "G0": "農地観測の\n意思決定支援",
        "G1": "観測データを\n可視化",
        "G2": "データの\n信頼性保証",
        "G3": "使いやすい\nUI提供",

        # レベル2
        "G1.1": "衛星データを\n地図表示",
        "G1.2": "平年値との\n比較分析",
        "G1.3": "時系列\nグラフ表示",

        "G2.1": "入力データ\n検証",
        "G2.2": "セキュリティ\n脅威防御",
        "G2.3": "データ整合性\n維持",

        "G3.1": "直感的\n操作性",
        "G3.2": "データ\nエクスポート",
        "G3.3": "システム\n保守性",

        # レベル3（主要な葉ゴール）
        "G1.1.1": "LST表示",
        "G1.1.2": "NDVI表示",
        "G1.2.1": "最寄り観測所\n検索",
        "G1.2.2": "平年値取得",
        "G1.3.1": "3本線グラフ",

        "G2.1.1": "座標範囲\nチェック",
        "G2.1.2": "数値型強制",
        "G2.1.3": "HTMLタグ除去",
        "G2.2.1": "SQLi防御",
        "G2.2.2": "XSS防御",
        "G2.3.1": "外部キー制約",
        "G2.3.2": "重複防止",
    }

    # ノード追加
    for node_id, label in goals.items():
        level = node_id.count('.')
        G.add_node(node_id, label=label, level=level)

    # エッジ追加（AND-精緻化）
    refinements = [
        # レベル0 → レベル1
        ("G0", "G1"), ("G0", "G2"), ("G0", "G3"),

        # レベル1 → レベル2
        ("G1", "G1.1"), ("G1", "G1.2"), ("G1", "G1.3"),
        ("G2", "G2.1"), ("G2", "G2.2"), ("G2", "G2.3"),
        ("G3", "G3.1"), ("G3", "G3.2"), ("G3", "G3.3"),

        # レベル2 → レベル3
        ("G1.1", "G1.1.1"), ("G1.1", "G1.1.2"),
        ("G1.2", "G1.2.1"), ("G1.2", "G1.2.2"),
        ("G1.3", "G1.3.1"),

        ("G2.1", "G2.1.1"), ("G2.1", "G2.1.2"), ("G2.1", "G2.1.3"),
        ("G2.2", "G2.2.1"), ("G2.2", "G2.2.2"),
        ("G2.3", "G2.3.1"), ("G2.3", "G2.3.2"),
    ]

    G.add_edges_from(refinements)
    return G, goals


def analyze_goal_graph(G, goals):
    """ゴール依存関係グラフの分析"""
    print("=" * 60)
    print("ゴール依存関係グラフ分析")
    print("=" * 60)
    print()

    # 1. 基本統計
    print(f"総ゴール数: {G.number_of_nodes()}")
    print(f"精緻化関係数: {G.number_of_edges()}")
    print()

    # 2. 各ゴールのサブゴール数（出次数）
    print("--- サブゴール数（出次数）Top 5 ---")
    out_degrees = sorted(G.out_degree(), key=lambda x: x[1], reverse=True)
    for node, degree in out_degrees[:5]:
        label = goals[node].replace('\n', '')
        print(f"{node:8} ({label:20}): {degree}個のサブゴール")
    print()

    # 3. 重要度分析（PageRank）
    print("--- 重要度分析（PageRank）Top 5 ---")
    pagerank = nx.pagerank(G)
    sorted_pagerank = sorted(pagerank.items(), key=lambda x: x[1], reverse=True)
    for node, score in sorted_pagerank[:5]:
        label = goals[node].replace('\n', '')
        print(f"{node:8} ({label:20}): {score:.4f}")
    print()

    # 4. クリティカルパス分析
    print("--- 最長依存パス（クリティカルパス）---")
    leaf_nodes = [n for n in G.nodes() if G.out_degree(n) == 0]
    root_node = "G0"
    longest_path = []
    max_length = 0
    for leaf in leaf_nodes:
        try:
            paths = list(nx.all_simple_paths(G, root_node, leaf))
            for path in paths:
                if len(path) > max_length:
                    max_length = len(path)
                    longest_path = path
        except nx.NetworkXNoPath:
            continue

    print(f"パス長: {max_length - 1} (階層数: {max_length})")
    path_str = " → ".join([f"{n}" for n in longest_path])
    print(path_str)
    print()

    # 5. ボトルネック分析（媒介中心性）
    print("--- ボトルネック分析（媒介中心性）Top 5 ---")
    betweenness = nx.betweenness_centrality(G)
    sorted_betweenness = sorted(betweenness.items(), key=lambda x: x[1], reverse=True)
    for node, score in sorted_betweenness[:5]:
        if score > 0:
            label = goals[node].replace('\n', '')
            print(f"{node:8} ({label:20}): {score:.4f}")
    print()

    return pagerank, betweenness


def visualize_goal_graph(G, goals):
    """ゴール依存関係グラフの可視化"""
    plt.figure(figsize=(20, 14))
    pos = nx.spring_layout(G, k=2, iterations=50, seed=42)

    # レベル別色分け
    level_colors = {0: '#FF6B6B', 1: '#4ECDC4', 2: '#45B7D1', 3: '#96CEB4'}
    node_colors = [level_colors[G.nodes[node]['level']] for node in G.nodes()]

    nx.draw(G, pos,
            labels={n: goals[n] for n in G.nodes()},
            node_color=node_colors,
            node_size=3000,
            font_size=8,
            font_weight='bold',
            edge_color='gray',
            arrows=True,
            arrowsize=20,
            arrowstyle='->')

    plt.title("Satellite Data Viewer - KAOSゴール依存関係グラフ",
              fontsize=16, fontweight='bold', pad=20)
    plt.axis('off')
    plt.tight_layout()

    output_path = Path("goal_dependency_graph.png")
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"[OK] グラフを {output_path} に保存しました")

    # JSONエクスポート
    graph_data = {
        "nodes": [{"id": n, "label": goals[n], "level": G.nodes[n]['level']}
                  for n in G.nodes()],
        "edges": [{"source": u, "target": v} for u, v in G.edges()]
    }

    json_path = Path("goal_dependency_graph.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(graph_data, f, ensure_ascii=False, indent=2)
    print(f"[OK] グラフデータを {json_path} に保存しました")
    print()


def build_component_dependency_graph():
    """コンポーネント依存関係グラフの構築"""
    C = nx.DiGraph()

    # コンポーネントノード
    components = {
        "User": "ユーザー",
        "Browser": "Webブラウザ",
        "Frontend": "フロントエンド",
        "API": "バックエンドAPI",
        "Database": "MySQL DB",
        "Python": "Pythonスクリプト",
        "JAXA": "JAXA G-Portal",
        "JMA": "気象庁データ",
    }

    C.add_nodes_from(components.keys())

    # 依存関係（矢印: A → B = "AがBに依存"）
    dependencies = [
        ("User", "Browser"),
        ("Browser", "Frontend"),
        ("Frontend", "API"),
        ("API", "Database"),
        ("Python", "JAXA"),
        ("Python", "JMA"),
        ("Python", "Database"),
        ("API", "Python"),  # 間接依存
    ]

    C.add_edges_from(dependencies)
    return C, components


def analyze_component_graph(C, components):
    """コンポーネント依存関係グラフの分析"""
    print("=" * 60)
    print("コンポーネント依存関係分析")
    print("=" * 60)
    print()

    # 1. 強連結成分分析（循環依存の検出）
    strongly_connected = list(nx.strongly_connected_components(C))
    print(f"強連結成分数: {len(strongly_connected)}")
    for i, component in enumerate(strongly_connected, 1):
        if len(component) > 1:
            print(f"  循環依存 {i}: {component}")
        else:
            print(f"  孤立成分 {i}: {component}")
    print()

    # 2. トポロジカルソート（ビルド順序）
    try:
        topo_order = list(nx.topological_sort(C))
        print(f"推奨ビルド順序: {' → '.join(topo_order)}")
    except nx.NetworkXError:
        print("警告: 循環依存が存在するため、トポロジカルソートできません")
    print()

    # 3. 重要コンポーネント（入次数 = 依存される数）
    print("--- 依存される回数（入次数）---")
    in_degrees = sorted(C.in_degree(), key=lambda x: x[1], reverse=True)
    for node, degree in in_degrees:
        comp_name = components[node]
        print(f"{node:10} ({comp_name:15}): {degree}個のコンポーネントが依存")
    print()

    # 4. 単一障害点（SPOF）の識別
    print("--- 単一障害点（SPOF）分析 ---")
    articulation_points = list(nx.articulation_points(C.to_undirected()))
    if articulation_points:
        print("以下のコンポーネントが停止すると、システムが分断されます:")
        for node in articulation_points:
            comp_name = components[node]
            print(f"  - {node} ({comp_name})")
    else:
        print("単一障害点は検出されませんでした")
    print()


def visualize_component_graph(C, components):
    """コンポーネント依存関係グラフの可視化"""
    plt.figure(figsize=(12, 8))
    pos = nx.spring_layout(C, k=1.5, iterations=50, seed=42)

    nx.draw(C, pos,
            labels=components,
            node_color='lightblue',
            node_size=4000,
            font_size=10,
            font_weight='bold',
            edge_color='gray',
            arrows=True,
            arrowsize=20)

    plt.title("Satellite Data Viewer - コンポーネント依存関係グラフ",
              fontsize=14, fontweight='bold', pad=20)
    plt.axis('off')
    plt.tight_layout()

    output_path = Path("component_dependency_graph.png")
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"[OK] コンポーネントグラフを {output_path} に保存しました")
    print()


def generate_traceability_matrix(G, goals):
    """トレーサビリティマトリクスの生成"""
    print("=" * 60)
    print("トレーサビリティマトリクス生成")
    print("=" * 60)
    print()

    # 葉ゴール（実装可能なゴール）のみを抽出
    leaf_goals = [n for n in G.nodes() if G.out_degree(n) == 0]

    # 実装ファイルとのマッピング
    implementation_map = {
        "G1.1.1": {"file": "frontend/js/map.js:48-65", "test": "目視確認"},
        "G1.1.2": {"file": "frontend/js/map.js:162-180", "test": "目視確認"},
        "G1.2.1": {"file": "backend/api.php:746-780", "test": "test_api.sh"},
        "G1.2.2": {"file": "backend/api.php:345-367", "test": "test_api.sh"},
        "G1.3.1": {"file": "frontend/js/chart.js:231-269", "test": "目視確認"},
        "G2.1.1": {"file": "backend/api.php:458-471", "test": "test_security.sh:Test 9,10"},
        "G2.1.2": {"file": "backend/api.php:445-456", "test": "test_security.sh:Test 1,2"},
        "G2.1.3": {"file": "backend/api.php:446,477-480", "test": "test_security.sh:Test 3"},
        "G2.2.1": {"file": "backend/api.php:全体", "test": "test_security.sh:Test 1,2"},
        "G2.2.2": {"file": "backend/api.php:446,477-480", "test": "test_security.sh:Test 3"},
        "G2.3.1": {"file": "backend/db_setup.sql:45-47", "test": "DB制約エラー"},
        "G2.3.2": {"file": "backend/db_setup.sql:50", "test": "DB制約エラー"},
    }

    print(f"{'ゴールID':<10} {'要求記述':<20} {'実装ファイル':<35} {'検証方法':<30}")
    print("-" * 100)
    for goal_id in sorted(leaf_goals):
        if goal_id in implementation_map:
            label = goals[goal_id].replace('\n', '')
            impl = implementation_map[goal_id]
            print(f"{goal_id:<10} {label:<20} {impl['file']:<35} {impl['test']:<30}")

    print()


def main():
    """メイン処理"""
    print()
    print("*" * 60)
    print(" Satellite Data Viewer - 要求工学分析")
    print(" KAOS + NetworkX による構造的解析")
    print("*" * 60)
    print()

    # 1. ゴール依存関係グラフの分析
    G, goals = build_goal_dependency_graph()
    pagerank, betweenness = analyze_goal_graph(G, goals)
    visualize_goal_graph(G, goals)

    # 2. コンポーネント依存関係グラフの分析
    C, components = build_component_dependency_graph()
    analyze_component_graph(C, components)
    visualize_component_graph(C, components)

    # 3. トレーサビリティマトリクス生成
    generate_traceability_matrix(G, goals)

    print("=" * 60)
    print("分析完了")
    print("=" * 60)
    print()
    print("生成されたファイル:")
    print("  - goal_dependency_graph.png")
    print("  - goal_dependency_graph.json")
    print("  - component_dependency_graph.png")
    print()


if __name__ == "__main__":
    main()
