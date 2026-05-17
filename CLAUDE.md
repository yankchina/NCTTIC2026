# CLAUDE.md — NCTTIC2026 项目上下文

> 本文件供 Claude 在每次对话开始时读取，以快速恢复项目背景。
> 最后更新：2026-05-17

---

## 项目概况

**项目名称**：NCTTIC2026（National College Teaching and Teaching Innovation Competition）  
**项目性质**：私有项目，东南大学教师教学发展中心内部使用  
**核心目标**：建立一个教学创新比赛获奖教师数据库，支持多维检索、标签管理与数据分析  
**项目负责人**：Allan（杨安康），东南大学教师教学发展中心

---

## 技术路线

### 阶段一：Mac 桌面端（当前阶段）
- **语言**：Swift / SwiftUI
- **数据库**：本地 PostgreSQL（通过 `libpq` 或 GRDB 直连）
- **数据导入**：Python 脚本（pandas + psycopg2）从 Excel 导入
- **目标平台**：macOS 14+

### 阶段二：移动端（后续阶段）
- **平台**：iPad / iPhone
- **框架**：SwiftUI（与 Mac 端共享尽量多的代码）
- **数据层**：SwiftData（本地）+ 可选 CloudKit 同步
- **过渡策略**：Mac 端作为主数据录入端，移动端以检索与展示为主

---

## 数据库设计（PostgreSQL）

### 核心表结构

```
schools          学校信息（含中英文名称、缩写、类别、省市、官网）
teachers         教师基本信息（含性别、民族、政治面貌、学历、官网）
teacher_private  教师敏感信息（证件号、银行账号，隔离存储）
courses          课程信息（含学科、描述）
award_records    获奖记录【核心事实表】（含学校快照、教师职称快照）
tags             标签库（含系统标签：收藏、关注）
entity_tags      标签多态关联表（挂载到任意实体）
```

### ENUM 类型

| ENUM 名称 | 说明 | 值域（部分） |
|---|---|---|
| `competition_level_type` | 比赛等级 | 校级 / 省级 / 国家级 |
| `team_role_type` | 团队角色 | 负责人 / 成员第一…第三 / 产业导师 |
| `award_title_type` | 获奖称号 | 特等奖 / 一等奖 / … / 专项奖 |
| `school_category_type` | 学校类别 | 985 / 211 / 双一流 / 部属高校 / … |
| `gender_type` | 性别 | 男 / 女 / 其他 |
| `id_doc_type` | 证件类型 | 居民身份证 / 护照 / 其他证件 |
| `degree_type` | 学位 | 学士 / 硕士 / 博士 / 博士后 / 其他 |
| `political_affiliation_type` | 政治面貌 | 中国共产党 / 九三学社 / 群众 / … |
| `entity_type` | 标签多态实体 | teacher / course / school / award_record |

### 关键设计决策

1. **双快照策略**：`award_records` 同时存储 `school_id`（外键，用于统计）和 `school_name_snapshot` / `school_province_snapshot`（快照，历史存证），解决教师调动导致的数据失真问题
2. **获奖等级双字段**：`award_level`（整数 1–4，用于排序筛选）+ `award_title`（ENUM 称号，用于展示），两者独立
3. **敏感信息隔离**：`teacher_private` 独立表，应用层按需加载，未来加密存储
4. **标签多态设计**：`entity_tags` 通过 `entity_type + entity_id` 挂载到任意实体，系统标签（收藏/关注）通过 `tag_key` 字段识别
5. **幂等导入**：Python 导入脚本使用 `ON CONFLICT (name) DO UPDATE`，支持重跑

---

## 目录结构

```
NCTTIC2026/
├── CLAUDE.md                  # 本文件，项目上下文
├── README.md                  # 项目说明
│
├── database/
│   ├── migrations/            # SQL 迁移文件，按版本号命名
│   │   └── 001_initial_schema.sql
│   └── seeds/                 # 测试/初始化数据
│
├── src/
│   ├── macos/                 # macOS SwiftUI 应用
│   │   └── (Xcode 项目)
│   └── ios/                   # iOS/iPadOS SwiftUI 应用
│       └── (Xcode 项目)
│
├── scripts/                   # Python 数据处理脚本
│   ├── import_schools.py      # 学校数据导入
│   ├── import_teachers.py     # 教师数据导入
│   └── import_awards.py       # 获奖记录导入
│
└── docs/
    ├── ai/                    # AI 提示词与对话记录
    │   └── prompts/
    └── worklog/               # 工作日志，按日期命名
        └── 2026-05-17.md
```

---

## 检索维度

多层检索支持以下维度的任意组合：

- 学校（名称、缩写）
- 地区（省份、城市）
- 学科
- 课程名称
- 获奖等级（`award_level` 数值范围）
- 获奖称号（`award_title`）
- 获奖届次（`award_session`）
- 获奖年度（`award_year`）
- 比赛等级（校级 / 省级 / 国家级）
- 是否为负责人（`team_role = '负责人'`）
- 标签（收藏 / 关注 / 自定义标签）

---

## 数据文件约定

### Excel 导入列名规范

**学校表 Excel 列名**

| 列名 | 必填 | 说明 |
|---|---|---|
| 学校全称 | ✅ | 唯一键 |
| 英文全称 | | Southeast University |
| 中文缩写 | | 东大 |
| 英文缩写 | | SEU |
| 省份 | ✅ | |
| 城市 | | |
| 学校类别 | | 逗号分隔，如 `985,双一流` |
| 官网 | | https://… |
| 备注 | | |

---

## 约定与规范

- 所有 SQL 迁移文件以 `NNN_description.sql` 命名，`NNN` 为三位序号
- Python 脚本统一使用 `python 3.11+`，依赖写入各脚本头部注释
- 工作日志用中文写作，记录当日完成事项、决策与待办
- Swift 代码遵循 Apple 官方 Swift API Design Guidelines
- 敏感字段（证件号、银行账号）在代码中以 `// SENSITIVE` 注释标记
