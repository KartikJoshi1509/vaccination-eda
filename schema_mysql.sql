-- =====================================================================
-- Vaccination database - relational schema for MySQL 8.0.16+ (also MariaDB 10.2+)
-- Source: five cleaned WHO/UNICEF extracts (see Vaccination_EDA notebook)
--
--   Lookup tables : who_region, country, antigen, coverage_category,
--                   disease, intro_vaccine, schedule_vaccine, target_population
--   Fact tables   : vaccine_coverage, disease_incidence, reported_cases,
--                   vaccine_introduction, vaccine_schedule
--
-- NOTE: CHECK constraints are only enforced from MySQL 8.0.16 (older versions parse and ignore them).
-- Re-runnable: drops and recreates everything inside the `vaccination` database.
-- =====================================================================
CREATE DATABASE IF NOT EXISTS vaccination
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE vaccination;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
DROP VIEW  IF EXISTS v_vaccine_coverage_detail;
DROP VIEW  IF EXISTS v_disease_surveillance;
DROP TABLE IF EXISTS vaccine_schedule;
DROP TABLE IF EXISTS vaccine_introduction;
DROP TABLE IF EXISTS reported_cases;
DROP TABLE IF EXISTS disease_incidence;
DROP TABLE IF EXISTS vaccine_coverage;
DROP TABLE IF EXISTS target_population;
DROP TABLE IF EXISTS schedule_vaccine;
DROP TABLE IF EXISTS intro_vaccine;
DROP TABLE IF EXISTS disease;
DROP TABLE IF EXISTS coverage_category;
DROP TABLE IF EXISTS antigen;
DROP TABLE IF EXISTS country;
DROP TABLE IF EXISTS who_region;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- Lookup / dimension tables
-- ---------------------------------------------------------------------
CREATE TABLE who_region (
    who_region_code  VARCHAR(10) NOT NULL,             -- AFRO, AMRO, EMRO, EURO, SEARO, WPRO
    PRIMARY KEY (who_region_code)
) ENGINE=InnoDB;

CREATE TABLE country (
    country_code     CHAR(3)      NOT NULL,            -- ISO-3
    country_name     VARCHAR(100) NOT NULL,
    who_region_code  VARCHAR(10)  NULL,                -- NULL when the source gives no region
    PRIMARY KEY (country_code),
    CONSTRAINT fk_country_region FOREIGN KEY (who_region_code) REFERENCES who_region (who_region_code)
) ENGINE=InnoDB;

CREATE TABLE antigen (
    antigen_code         VARCHAR(20)  NOT NULL,        -- e.g. MCV1, DTPCV3, BCG
    antigen_description  VARCHAR(150) NOT NULL,
    PRIMARY KEY (antigen_code)
) ENGINE=InnoDB;

CREATE TABLE coverage_category (
    category_code         VARCHAR(20)  NOT NULL,       -- ADMIN, OFFICIAL, WUENIC, HPV, PAB
    category_description VARCHAR(100) NOT NULL,
    PRIMARY KEY (category_code)
) ENGINE=InnoDB;

CREATE TABLE disease (
    disease_code           VARCHAR(30)  NOT NULL,      -- e.g. MEASLES, POLIO
    disease_description    VARCHAR(100) NOT NULL,
    incidence_denominator  VARCHAR(50)  NOT NULL,      -- unit the incidence rate is expressed in (fixed per disease)
    PRIMARY KEY (disease_code)
) ENGINE=InnoDB;

-- Vaccines as named in the vaccine-introduction file (no code in the source)
CREATE TABLE intro_vaccine (
    intro_vaccine_id     SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    vaccine_description  VARCHAR(100)      NOT NULL,
    PRIMARY KEY (intro_vaccine_id),
    UNIQUE KEY uq_intro_vaccine_desc (vaccine_description)
) ENGINE=InnoDB;

-- Vaccines as coded in the national-schedule file
CREATE TABLE schedule_vaccine (
    vaccine_code         VARCHAR(20)  NOT NULL,
    vaccine_description  VARCHAR(150) NOT NULL,
    PRIMARY KEY (vaccine_code)
) ENGINE=InnoDB;

-- (code, description) pairs; code is NULL for "General/routine" with no sub-code
CREATE TABLE target_population (
    target_pop_id           TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    target_pop_code         VARCHAR(20)      NULL,
    target_pop_description  VARCHAR(100)     NOT NULL,
    PRIMARY KEY (target_pop_id),
    UNIQUE KEY uq_target_pop (target_pop_code, target_pop_description)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Fact tables
-- ---------------------------------------------------------------------
-- NULL measures mean "not reported" - never imputed as 0.
-- coverage_pct may legitimately exceed 100 (administrative over-reporting), so only >= 0 is enforced.
CREATE TABLE vaccine_coverage (
    country_code   CHAR(3)           NOT NULL,
    year           SMALLINT UNSIGNED NOT NULL,
    antigen_code   VARCHAR(20)       NOT NULL,
    category_code  VARCHAR(20)       NOT NULL,
    target_number  DOUBLE            NULL,
    doses          DOUBLE            NULL,
    coverage_pct   DECIMAL(6,2)      NULL,
    PRIMARY KEY (country_code, year, antigen_code, category_code),
    KEY ix_coverage_antigen_year (antigen_code, year),
    CONSTRAINT fk_cov_country  FOREIGN KEY (country_code)  REFERENCES country (country_code),
    CONSTRAINT fk_cov_antigen  FOREIGN KEY (antigen_code)  REFERENCES antigen (antigen_code),
    CONSTRAINT fk_cov_category FOREIGN KEY (category_code) REFERENCES coverage_category (category_code),
    CONSTRAINT ck_cov_pct CHECK (coverage_pct IS NULL OR coverage_pct >= 0)
) ENGINE=InnoDB;

CREATE TABLE disease_incidence (
    country_code    CHAR(3)           NOT NULL,
    year            SMALLINT UNSIGNED NOT NULL,
    disease_code    VARCHAR(30)       NOT NULL,
    incidence_rate  DECIMAL(12,2)     NULL,
    PRIMARY KEY (country_code, year, disease_code),
    KEY ix_incidence_disease_year (disease_code, year),
    CONSTRAINT fk_inc_country FOREIGN KEY (country_code) REFERENCES country (country_code),
    CONSTRAINT fk_inc_disease FOREIGN KEY (disease_code) REFERENCES disease (disease_code),
    CONSTRAINT ck_inc_rate CHECK (incidence_rate IS NULL OR incidence_rate >= 0)
) ENGINE=InnoDB;

CREATE TABLE reported_cases (
    country_code  CHAR(3)           NOT NULL,
    year          SMALLINT UNSIGNED NOT NULL,
    disease_code  VARCHAR(30)       NOT NULL,
    cases         INT UNSIGNED      NULL,
    PRIMARY KEY (country_code, year, disease_code),
    KEY ix_cases_disease_year (disease_code, year),
    CONSTRAINT fk_rep_country FOREIGN KEY (country_code) REFERENCES country (country_code),
    CONSTRAINT fk_rep_disease FOREIGN KEY (disease_code) REFERENCES disease (disease_code)
) ENGINE=InnoDB;

CREATE TABLE vaccine_introduction (
    country_code      CHAR(3)           NOT NULL,
    year              SMALLINT UNSIGNED NOT NULL,
    intro_vaccine_id  SMALLINT UNSIGNED NOT NULL,
    is_introduced     TINYINT(1)        NULL,            -- 1 = Yes, 0 = No, NULL = unknown
    PRIMARY KEY (country_code, year, intro_vaccine_id),
    KEY ix_intro_vaccine_year (intro_vaccine_id, year),
    CONSTRAINT fk_intro_country FOREIGN KEY (country_code)     REFERENCES country (country_code),
    CONSTRAINT fk_intro_vaccine FOREIGN KEY (intro_vaccine_id) REFERENCES intro_vaccine (intro_vaccine_id),
    CONSTRAINT ck_intro_flag CHECK (is_introduced IS NULL OR is_introduced IN (0, 1))
) ENGINE=InnoDB;

CREATE TABLE vaccine_schedule (
    schedule_id       INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    country_code      CHAR(3)           NOT NULL,
    year              SMALLINT UNSIGNED NOT NULL,
    vaccine_code      VARCHAR(20)       NOT NULL,
    schedule_rounds   TINYINT UNSIGNED  NOT NULL,
    target_pop_id     TINYINT UNSIGNED  NOT NULL,
    geo_area          VARCHAR(12)       NULL,
    age_administered  VARCHAR(20)       NULL,
    source_comment    TEXT              NULL,
    PRIMARY KEY (schedule_id),
    UNIQUE KEY uq_schedule_natural (country_code, year, vaccine_code, schedule_rounds, target_pop_id),
    KEY ix_schedule_vaccine (vaccine_code),
    CONSTRAINT fk_sched_country FOREIGN KEY (country_code)  REFERENCES country (country_code),
    CONSTRAINT fk_sched_vaccine FOREIGN KEY (vaccine_code)  REFERENCES schedule_vaccine (vaccine_code),
    CONSTRAINT fk_sched_pop     FOREIGN KEY (target_pop_id) REFERENCES target_population (target_pop_id),
    CONSTRAINT ck_sched_rounds CHECK (schedule_rounds >= 1),
    CONSTRAINT ck_sched_geo CHECK (geo_area IS NULL OR geo_area IN ('NATIONAL', 'SUBNATIONAL'))
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Convenience views
-- ---------------------------------------------------------------------
CREATE VIEW v_vaccine_coverage_detail AS
SELECT c.country_code, c.country_name, c.who_region_code,
       vc.year, vc.antigen_code, a.antigen_description,
       vc.category_code, cc.category_description,
       vc.target_number, vc.doses, vc.coverage_pct
FROM vaccine_coverage vc
JOIN country           c  ON c.country_code   = vc.country_code
JOIN antigen           a  ON a.antigen_code   = vc.antigen_code
JOIN coverage_category cc ON cc.category_code = vc.category_code;

CREATE VIEW v_disease_surveillance AS
SELECT c.country_code, c.country_name, c.who_region_code,
       i.year, d.disease_code, d.disease_description, d.incidence_denominator,
       r.cases, i.incidence_rate
FROM disease_incidence i
JOIN reported_cases r ON r.country_code = i.country_code
                     AND r.year         = i.year
                     AND r.disease_code = i.disease_code
JOIN country c ON c.country_code = i.country_code
JOIN disease d ON d.disease_code = i.disease_code;
