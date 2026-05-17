-- ============================================================
-- Migration: 001_initial_schema.sql
-- Description: 初始数据库结构
-- Date: 2026-05-17
-- Author: Allan (杨安康)
-- Database: PostgreSQL 16
-- ============================================================


-- ============================================================
-- ENUM 类型定义
-- ============================================================

CREATE TYPE competition_level_type AS ENUM (
    '校级', '省级', '国家级'
);

CREATE TYPE team_role_type AS ENUM (
    '负责人',
    '团队成员排名第一',
    '团队成员排名第二',
    '团队成员排名第三',
    '团队成员产业导师'
);

CREATE TYPE award_title_type AS ENUM (
    '特等奖', '一等奖', '二等奖', '三等奖', '优秀奖', '专项奖'
);

CREATE TYPE school_category_type AS ENUM (
    '985', '211', '双一流', '部属高校', '地方本科', '民办本科', '合作办学'
);

CREATE TYPE gender_type AS ENUM ('男', '女', '其他');

CREATE TYPE id_doc_type AS ENUM ('居民身份证', '护照', '其他证件');

CREATE TYPE degree_type AS ENUM ('学士', '硕士', '博士', '博士后', '其他');

CREATE TYPE political_affiliation_type AS ENUM (
    '中国共产党',
    '中国国民党革命委员会',
    '中国民主同盟',
    '中国民主建国会',
    '中国民主促进会',
    '中国农工民主党',
    '中国致公党',
    '九三学社',
    '台湾民主自治同盟',
    '无党派人士',
    '群众'
);

CREATE TYPE entity_type AS ENUM (
    'teacher', 'course', 'school', 'award_record'
);


-- ============================================================
-- 学校信息表
-- ============================================================

CREATE TABLE schools (
    id          UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(200)            NOT NULL UNIQUE,   -- 中文全称（唯一键）
    name_en     VARCHAR(300),                              -- 英文全称
    abbr_zh     VARCHAR(20),                               -- 中文缩写，如"东大"
    abbr_en     VARCHAR(30),                               -- 英文缩写，如 SEU
    province    VARCHAR(50)             NOT NULL,
    city        VARCHAR(50),
    categories  school_category_type[]  NOT NULL DEFAULT '{}',
    website     VARCHAR(500),
    remark      TEXT,
    created_at  TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ             NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  schools             IS '学校信息';
COMMENT ON COLUMN schools.name        IS '中文全称，全局唯一，作为导入幂等键';
COMMENT ON COLUMN schools.name_en     IS '英文全称，如 Southeast University';
COMMENT ON COLUMN schools.abbr_zh     IS '中文缩写，UI 空间紧凑场景使用';
COMMENT ON COLUMN schools.abbr_en     IS '英文缩写，如 SEU，用于标签、角标等';
COMMENT ON COLUMN schools.categories  IS '学校类别，支持多选，用 GIN 索引';
COMMENT ON COLUMN schools.website     IS '学校官方主页 URL';

CREATE INDEX idx_schools_province   ON schools (province);
CREATE INDEX idx_schools_city       ON schools (city);
CREATE INDEX idx_schools_categories ON schools USING GIN (categories);


-- ============================================================
-- 教师基本信息表
-- ============================================================

CREATE TABLE teachers (
    id                    UUID                       PRIMARY KEY DEFAULT gen_random_uuid(),
    name                  VARCHAR(100)               NOT NULL,

    -- 个人信息
    gender                gender_type,
    birth_date            DATE,
    hometown              VARCHAR(100),              -- 籍贯
    ethnicity             VARCHAR(30),               -- 民族，自由文本，可空
    political_affiliation political_affiliation_type,-- 政治面貌，可空

    -- 证件（类型在主表，号码在敏感表）
    id_doc_type           id_doc_type                NOT NULL DEFAULT '居民身份证',

    -- 学历
    highest_degree        degree_type,
    degree_school         VARCHAR(200),              -- 最高学位毕业学校
    research_direction    TEXT,                      -- 研究专业方向

    -- 现任信息
    current_title         VARCHAR(100),              -- 现职称
    current_position      VARCHAR(100),              -- 现职务
    school_id             UUID                       REFERENCES schools(id) ON DELETE SET NULL,

    -- 链接
    website               VARCHAR(500),              -- 个人主页或学院介绍页

    remark                TEXT,
    created_at            TIMESTAMPTZ                NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ                NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  teachers                       IS '教师基本信息';
COMMENT ON COLUMN teachers.ethnicity             IS '民族，如汉族、回族，可空';
COMMENT ON COLUMN teachers.political_affiliation IS '政治面貌，可空';
COMMENT ON COLUMN teachers.id_doc_type           IS '证件类型，证件号存于 teacher_private';
COMMENT ON COLUMN teachers.school_id             IS '当前所在学校；历史所在学校通过 award_records 快照追踪';
COMMENT ON COLUMN teachers.website               IS '个人主页或所在学院教师介绍页';

CREATE INDEX idx_teachers_school ON teachers (school_id);
CREATE INDEX idx_teachers_gender ON teachers (gender);
CREATE INDEX idx_teachers_degree ON teachers (highest_degree);


-- ============================================================
-- 教师敏感信息表（隔离存储）
-- ============================================================

CREATE TABLE teacher_private (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id   UUID         NOT NULL UNIQUE REFERENCES teachers(id) ON DELETE CASCADE,
    id_number    VARCHAR(30),               -- 证件号 [SENSITIVE]
    bank_account VARCHAR(50),               -- 银行账号 [SENSITIVE]
    bank_name    VARCHAR(100),              -- 开户行
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  teacher_private              IS '教师敏感财务信息，与基本信息隔离';
COMMENT ON COLUMN teacher_private.id_number    IS '[SENSITIVE] 建议应用层加密后存储';
COMMENT ON COLUMN teacher_private.bank_account IS '[SENSITIVE] 建议应用层加密后存储';


-- ============================================================
-- 课程信息表
-- ============================================================

CREATE TABLE courses (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(200)  NOT NULL,
    subject     VARCHAR(100),              -- 所属学科
    description TEXT,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  courses         IS '课程信息';
COMMENT ON COLUMN courses.subject IS '所属学科门类，如理学、工学、医学等';

CREATE INDEX idx_courses_subject ON courses (subject);


-- ============================================================
-- 获奖记录表（核心事实表）
-- ============================================================

CREATE TABLE award_records (
    id                       UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),

    -- 时间与届次
    award_year               INTEGER                 NOT NULL,
    award_session            INTEGER                 NOT NULL,

    -- 获奖等级：数值（排序筛选）+ 称号（展示）
    award_level              SMALLINT                NOT NULL CHECK (award_level BETWEEN 1 AND 4),
    award_title              award_title_type        NOT NULL,

    -- 比赛信息
    competition_level        competition_level_type  NOT NULL,
    track                    VARCHAR(100),           -- 参赛赛道

    -- 教师参赛时快照（与主表解耦，历史存证）
    title_at_time            VARCHAR(100),           -- 获奖时职称
    department               VARCHAR(200),           -- 获奖时所在院系

    -- 学校快照（教师可能调动，双字段策略）
    school_id                UUID                    REFERENCES schools(id) ON DELETE SET NULL,
    school_name_snapshot     VARCHAR(200)            NOT NULL,
    school_province_snapshot VARCHAR(50)             NOT NULL,

    -- 团队角色
    team_role                team_role_type          NOT NULL,

    -- 外键
    teacher_id               UUID                    NOT NULL REFERENCES teachers(id),
    course_id                UUID                    NOT NULL REFERENCES courses(id),

    -- 防重：同届 + 同教师 + 同课程 + 同赛级不能重复
    UNIQUE (award_session, teacher_id, course_id, competition_level),

    remark                   TEXT,
    created_at               TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ             NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  award_records                        IS '获奖记录，一条记录 = 一位教师在一次比赛中的获奖情况';
COMMENT ON COLUMN award_records.award_level            IS '获奖等级数值：1最高，4最低，用于排序与范围筛选';
COMMENT ON COLUMN award_records.award_title            IS '获奖称号，用于展示，与 award_level 解耦';
COMMENT ON COLUMN award_records.title_at_time          IS '获奖时职称快照，不随 teachers 表更新';
COMMENT ON COLUMN award_records.school_id              IS '关联学校主表，供统计；学校删除时置 NULL';
COMMENT ON COLUMN award_records.school_name_snapshot   IS '获奖时学校名称，固化快照';
COMMENT ON COLUMN award_records.school_province_snapshot IS '获奖时省份，保证地区筛选历史准确性';

CREATE INDEX idx_ar_year              ON award_records (award_year);
CREATE INDEX idx_ar_session           ON award_records (award_session);
CREATE INDEX idx_ar_award_level       ON award_records (award_level);
CREATE INDEX idx_ar_competition_level ON award_records (competition_level);
CREATE INDEX idx_ar_team_role         ON award_records (team_role);
CREATE INDEX idx_ar_teacher           ON award_records (teacher_id);
CREATE INDEX idx_ar_course            ON award_records (course_id);
CREATE INDEX idx_ar_school            ON award_records (school_id);
CREATE INDEX idx_ar_school_province   ON award_records (school_province_snapshot);


-- ============================================================
-- 标签库
-- ============================================================

CREATE TABLE tags (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(50)  NOT NULL,
    color       VARCHAR(20),                -- HEX 颜色，如 #FFD700
    description TEXT,
    is_system   BOOLEAN      NOT NULL DEFAULT FALSE,
    tag_key     VARCHAR(50)  UNIQUE,        -- 系统标签固定标识，业务逻辑用此判断
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  tags          IS '标签库，is_system=TRUE 的标签不允许删除';
COMMENT ON COLUMN tags.tag_key  IS '系统标签程序标识，如 favorite / follow';
COMMENT ON COLUMN tags.color    IS 'HEX 颜色，供 UI 渲染标签色块';

-- 预置系统标签
INSERT INTO tags (name, color, is_system, tag_key, description) VALUES
    ('收藏', '#FFD700', TRUE, 'favorite', '收藏感兴趣的任意对象，统一在收藏页查看'),
    ('关注', '#4A90D9', TRUE, 'follow',   '持续关注某位教师、课程或学校的动态');


-- ============================================================
-- 标签关联表（多态）
-- ============================================================

CREATE TABLE entity_tags (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tag_id      UUID         NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    entity_type entity_type  NOT NULL,
    entity_id   UUID         NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tag_id, entity_type, entity_id)
);

COMMENT ON TABLE  entity_tags             IS '标签与任意实体的关联，多态设计';
COMMENT ON COLUMN entity_tags.entity_type IS '实体类型，决定 entity_id 指向哪张表';
COMMENT ON COLUMN entity_tags.entity_id   IS '目标实体 UUID';

CREATE INDEX idx_entity_tags_tag    ON entity_tags (tag_id);
CREATE INDEX idx_entity_tags_entity ON entity_tags (entity_type, entity_id);
