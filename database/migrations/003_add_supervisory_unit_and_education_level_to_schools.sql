-- ============================================================
-- Migration: 003_add_supervisory_unit_and_education_level_to_schools.sql
-- Description: schools 增加主管单位与办学层次；扩展 school_category_type 枚举
-- Date: 2026-05-17
-- Database: PostgreSQL 16
-- ============================================================

-- 扩展学校类别枚举
ALTER TYPE school_category_type ADD VALUE IF NOT EXISTS '第一批双一流';
ALTER TYPE school_category_type ADD VALUE IF NOT EXISTS '第二批双一流';

-- schools 增加字段
ALTER TABLE schools
ADD COLUMN supervisory_unit VARCHAR(200),
ADD COLUMN education_level VARCHAR(20) CHECK (education_level IN ('本科', '专科'));

COMMENT ON COLUMN schools.supervisory_unit IS '主管单位（如教育部、省教育厅等）';
COMMENT ON COLUMN schools.education_level IS '办学层次：本科或专科';
