# NCTTIC2026

**National College Teaching and Teaching Innovation Competition — 教学创新比赛获奖教师数据库**

东南大学教师教学发展中心内部项目，用于管理历届教学创新比赛获奖教师信息，支持多维检索、标签管理与数据分析。

> ⚠️ 私有项目，含敏感数据，请勿公开。

## 技术栈

| 层级 | 技术 |
|---|---|
| macOS 应用 | Swift + SwiftUI |
| iOS 应用 | Swift + SwiftUI + SwiftData |
| 数据库 | PostgreSQL 16（本地） |
| 数据导入 | Python 3.11 + pandas + psycopg2 |

## 目录说明

```
src/macos/      macOS SwiftUI 桌面应用（主录入端）
src/ios/        iOS/iPadOS 应用（检索展示端）
database/       SQL 迁移文件与初始化数据
scripts/        Python 数据导入工具
docs/ai/        AI 辅助开发的提示词记录
docs/worklog/   开发工作日志
```

## 快速开始

### 数据库初始化

```bash
psql -U postgres -d seucfd -f database/migrations/001_initial_schema.sql
```

### 导入学校数据

```bash
pip install pandas openpyxl psycopg2-binary tabulate
python scripts/import_schools.py data/schools.xlsx --dry-run
python scripts/import_schools.py data/schools.xlsx
```

## 参考文档

- [CLAUDE.md](./CLAUDE.md) — AI 上下文文件，供 Claude 读取项目背景
- [工作日志](./docs/worklog/) — 按日期记录开发过程
