#!/usr/bin/env python3
"""
import_schools.py
将「中国高校数据」Excel 导入 PostgreSQL schools 表

依赖：
    pip install pandas openpyxl psycopg2-binary tabulate

用法：
    python import_schools.py 中国高校数据-2025-10-07.xlsx --dry-run   # 仅预览
    python import_schools.py 中国高校数据-2025-10-07.xlsx             # 正式导入
"""

import sys
import argparse
from pathlib import Path

import pandas as pd
import psycopg2
import psycopg2.extras
from tabulate import tabulate

# ─────────────────────────────────────────────────────────────
# 配置区
# ─────────────────────────────────────────────────────────────

DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "seucfd",
    "user":     "postgres",
    "password": "",
}

# 标签列 → school_category_type[] 的映射规则
# Excel 标签值  →  数据库 ENUM 值（None 表示忽略该标签）
TAG_TO_CATEGORY = {
    "985":      "985",
    "211":      "211",
    "DFC01":    "第一批双一流",   # migration 003：第一批双一流
    "DFC02":    "第二批双一流",   # migration 003：第二批双一流
    "民办":     "民办本科",
    "中外办学": "合作办学",
    # 注意：以下两个 ENUM 值尚未在 migration 中添加，
    # 若数据库中不存在会在写入时报错，届时需补充 migration：
    # ALTER TYPE school_category_type ADD VALUE '军队院校';
    # ALTER TYPE school_category_type ADD VALUE '境外机构';
    "军校":     "军队院校",
    "海南境外": "境外机构",
}

# 备注列 → school_category_type 的附加推断
REMARK_TO_CATEGORY = {
    "民办":         "民办本科",
    "中外合作办学及内地与港澳合作办学": "合作办学",
}

# 有效的 ENUM 值集合（与 migration 001 + 003 保持同步）
VALID_CATEGORIES = {
    "985", "211",
    "第一批双一流", "第二批双一流",   # migration 003 新增
    "部属高校", "地方本科", "民办本科", "合作办学",
    "军队院校", "境外机构",           # 若尚未在 migration 中添加，写入时会报错
}

VALID_EDUCATION_LEVELS = {"本科", "专科"}

# 部属高校判定：主管单位包含以下关键词则标记为"部属高校"
MINISTERIAL_KEYWORDS = [
    "教育部", "工业和信息化部", "国家卫生健康委员会",
    "国家体育总局", "国家民委", "农业农村部",
    "国家林业和草原局", "交通运输部", "水利部",
    "民政部", "公安部", "外交部", "司法部",
    "财政部", "自然资源部", "生态环境部",
    "住房和城乡建设部", "文化和旅游部",
    "中国科学院", "中国社会科学院",
    "应急管理部", "中国气象局",
]

# ─────────────────────────────────────────────────────────────
# 解析逻辑
# ─────────────────────────────────────────────────────────────

def parse_categories(tag_str: str, remark_str: str, supervisory_unit: str) -> list[str]:
    """
    从标签列、备注列、主管单位三个来源推断 categories。
    返回去重后的有效 ENUM 值列表。
    """
    result = set()

    # 1. 解析标签列
    if pd.notna(tag_str) and str(tag_str).strip():
        for raw in str(tag_str).replace("，", ",").split(","):
            raw = raw.strip()
            mapped = TAG_TO_CATEGORY.get(raw)
            if mapped and mapped in VALID_CATEGORIES:
                result.add(mapped)
            # 未映射的标签暂时忽略（脚本末尾会统计未知标签）

    # 2. 解析备注列
    if pd.notna(remark_str) and str(remark_str).strip():
        remark = str(remark_str).strip()
        mapped = REMARK_TO_CATEGORY.get(remark)
        if mapped:
            result.add(mapped)

    # 3. 根据主管单位推断"部属高校"
    if pd.notna(supervisory_unit):
        gb = str(supervisory_unit).strip()
        if any(kw in gb for kw in MINISTERIAL_KEYWORDS):
            result.add("部属高校")

    return sorted(result)


def parse_education_level(raw: str) -> str | None:
    val = str(raw).strip() if pd.notna(raw) else ""
    return val if val in VALID_EDUCATION_LEVELS else None


def clean_str(val) -> str | None:
    if pd.isna(val):
        return None
    s = str(val).strip()
    return s if s else None


# ─────────────────────────────────────────────────────────────
# 读取与验证
# ─────────────────────────────────────────────────────────────

def load_and_validate(excel_path: Path):
    """
    返回:
        valid_rows   : list[dict]  待插入的记录
        error_rows   : list[dict]  验证失败的行
        unknown_tags : set[str]    未在映射表中出现的标签值
    """
    df = pd.read_excel(excel_path, dtype=str)
    print(f"  读取完成：共 {len(df)} 行，列名：{list(df.columns)}")

    valid_rows, error_rows = [], []
    unknown_tags: set[str] = set()

    for i, row in df.iterrows():
        excel_row = i + 2
        errors = []

        school_name = clean_str(row.get("学校名称"))
        province    = clean_str(row.get("所在省")) or "省名保密"  # 省份为空时使用默认值

        if not school_name:
            errors.append("学校名称为空")

        # 收集未知标签（用于报告，不作为错误）
        tag_str = row.get("标签", "")
        if pd.notna(tag_str) and str(tag_str).strip():
            for raw in str(tag_str).replace("，", ",").split(","):
                raw = raw.strip()
                if raw and raw not in TAG_TO_CATEGORY:
                    unknown_tags.add(raw)

        if errors:
            error_rows.append({
                "行号":   excel_row,
                "学校名称": school_name or "(空)",
                "错误":   " | ".join(errors),
            })
            continue

        supervisory_unit = clean_str(row.get("主管单位"))
        remark_str       = row.get("备注", "")
        categories       = parse_categories(tag_str, remark_str, supervisory_unit)
        education_level  = parse_education_level(row.get("办学层次", ""))

        valid_rows.append({
            "name":                 school_name,
            "official_unique_code": clean_str(row.get("学校编码")),  # migration 002
            "supervisory_unit":     supervisory_unit,                # migration 003
            "province":             province,
            "city":                 clean_str(row.get("所在市")),
            "education_level":      education_level,                 # migration 003
            "categories":           categories,
            "remark":               clean_str(remark_str) if pd.notna(remark_str) else None,
        })

    return valid_rows, error_rows, unknown_tags


# ─────────────────────────────────────────────────────────────
# 终端预览
# ─────────────────────────────────────────────────────────────

def print_preview(valid_rows: list, error_rows: list, unknown_tags: set):
    print("\n" + "=" * 65)
    print("  📊 导入预览")
    print("=" * 65)
    print(f"  ✅ 有效行：{len(valid_rows)} 条")
    print(f"  ❌ 错误行：{len(error_rows)} 条")
    if unknown_tags:
        print(f"  ⚠️  未映射标签（已忽略）：{', '.join(sorted(unknown_tags))}")

    if error_rows:
        print("\n【错误明细】")
        print(tabulate(error_rows, headers="keys", tablefmt="rounded_outline"))

    # 按省份统计
    from collections import Counter
    province_count = Counter(r["province"] for r in valid_rows)
    print("\n【按省份统计（Top 15）】")
    stats = [{"省份": p, "学校数": c}
             for p, c in province_count.most_common(15)]
    print(tabulate(stats, headers="keys", tablefmt="rounded_outline"))

    # 按类别统计
    cat_count: Counter = Counter()
    for r in valid_rows:
        for c in r["categories"]:
            cat_count[c] += 1
    print("\n【按类别标签统计】")
    cat_stats = [{"类别": k, "学校数": v}
                 for k, v in cat_count.most_common()]
    print(tabulate(cat_stats, headers="keys", tablefmt="rounded_outline"))

    # 按办学层次统计
    level_count = Counter(r["education_level"] or "(未知)" for r in valid_rows)
    print("\n【按办学层次统计】")
    print(tabulate([{"层次": k, "数量": v} for k, v in level_count.items()],
                   headers="keys", tablefmt="rounded_outline"))

    # 数据预览（前10行）
    print("\n【数据样例（前 10 行）】")
    sample = [
        {
            "学校名称":  r["name"],
            "编码":      r["official_unique_code"] or "-",
            "省/市":    f"{r['province']} {r['city'] or ''}".strip(),
            "层次":      r["education_level"] or "-",
            "类别":      ",".join(r["categories"]) or "-",
            "主管单位":  (r["supervisory_unit"] or "-")[:12],
        }
        for r in valid_rows[:10]
    ]
    print(tabulate(sample, headers="keys", tablefmt="rounded_outline"))
    print()


# ─────────────────────────────────────────────────────────────
# 数据库写入
# ─────────────────────────────────────────────────────────────

INSERT_SQL = """
INSERT INTO schools (
    name, official_unique_code, supervisory_unit,
    province, city, education_level,
    categories, remark
)
VALUES (
    %(name)s, %(official_unique_code)s, %(supervisory_unit)s,
    %(province)s, %(city)s,
    %(education_level)s,
    %(categories)s::school_category_type[],
    %(remark)s
)
ON CONFLICT (name) DO UPDATE SET
    official_unique_code = EXCLUDED.official_unique_code,
    supervisory_unit     = EXCLUDED.supervisory_unit,
    province             = EXCLUDED.province,
    city                 = EXCLUDED.city,
    education_level      = EXCLUDED.education_level,
    categories           = EXCLUDED.categories,
    remark               = EXCLUDED.remark,
    updated_at           = NOW()
RETURNING name, (xmax = 0) AS is_new;
"""


def do_import(valid_rows: list):
    inserted = updated = failed = 0
    fail_details = []

    conn = psycopg2.connect(**DB_CONFIG)
    try:
        with conn:
            with conn.cursor() as cur:
                for row in valid_rows:
                    row_copy = row.copy()
                    # 将 Python list 转为 PostgreSQL 数组字面量
                    row_copy["categories"] = (
                        "{" + ",".join(row["categories"]) + "}"
                        if row["categories"] else "{}"
                    )
                    try:
                        cur.execute(INSERT_SQL, row_copy)
                        result = cur.fetchone()
                        if result and result[1]:   # is_new
                            inserted += 1
                        else:
                            updated += 1
                    except Exception as e:
                        failed += 1
                        fail_details.append({"学校": row["name"], "错误": str(e)[:80]})
                        conn.rollback()             # 单条失败，回滚后继续

        print(f"\n✅ 导入完成：新增 {inserted} 条，更新 {updated} 条，失败 {failed} 条。")
        if fail_details:
            print("\n【写入失败明细】")
            print(tabulate(fail_details, headers="keys", tablefmt="rounded_outline"))

    except Exception as e:
        conn.rollback()
        print(f"❌ 数据库连接或事务失败，已回滚：{e}")
        sys.exit(1)
    finally:
        conn.close()


# ─────────────────────────────────────────────────────────────
# 主入口
# ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="中国高校数据 Excel → PostgreSQL schools 表导入工具"
    )
    parser.add_argument("excel", help="Excel 文件路径")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="仅预览，不写入数据库"
    )
    parser.add_argument(
        "--limit", type=int, default=None,
        help="仅处理前 N 行（调试用）"
    )
    args = parser.parse_args()

    excel_path = Path(args.excel)
    if not excel_path.exists():
        print(f"❌ 文件不存在：{excel_path}")
        sys.exit(1)

    print(f"\n📂 读取文件：{excel_path.resolve()}")
    valid_rows, error_rows, unknown_tags = load_and_validate(excel_path)

    if args.limit:
        valid_rows = valid_rows[:args.limit]
        print(f"  ⚠️  --limit {args.limit}，仅处理前 {args.limit} 条有效行")

    print_preview(valid_rows, error_rows, unknown_tags)

    if args.dry_run:
        print("ℹ️  --dry-run 模式，不写入数据库。")
        return

    if not valid_rows:
        print("⚠️  没有有效数据，退出。")
        return

    prompt = (
        f"存在 {len(error_rows)} 条错误行将被跳过，继续导入 {len(valid_rows)} 条有效行？[y/N] "
        if error_rows else
        f"确认导入 {len(valid_rows)} 条记录到数据库？[y/N] "
    )
    if input(prompt).strip().lower() != "y":
        print("已取消。")
        return

    do_import(valid_rows)


if __name__ == "__main__":
    main()
