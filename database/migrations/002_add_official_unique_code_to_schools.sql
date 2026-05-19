-- ============================================================
-- Migration: 002_add_official_unique_code_to_schools.sql
-- Description: 在 schools 表增加教育部高校唯一编号字段
-- Date: 2026-05-17
-- Database: PostgreSQL 16
-- ============================================================

ALTER TABLE schools
ADD COLUMN official_unique_code VARCHAR(200);

COMMENT ON COLUMN schools.official_unique_code IS '教育部规定的高校唯一编号';
