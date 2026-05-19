# !/bin/bash

# Done: 2026-05-17 
# psql -U postgres -d TIC2026 -f database/migrations/001_initial_schema.sql
# psql -U postgres -d TIC2026 -f database/migrations/002_add_official_unique_code_to_schools.sql
psql -U postgres -d TIC2026 -f database/migrations/003_add_supervisory_unit_and_education_level_to_schools.sql