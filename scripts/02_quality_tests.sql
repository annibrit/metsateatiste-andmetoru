-- scripts/02_quality_tests.sql
-- ============================================================
-- Metsateatiste andmekvaliteedi testid
-- Kirjutab tulemused quality.test_results tabelisse.
-- Käivitamine: python scripts/run_pipeline.py test
-- ============================================================

-- Tühjenda eelmised tulemused
TRUNCATE TABLE quality.test_results;

-- ============================================================
-- TEST 1: sys_id ei tohi olla NULL
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis: sys_id not null',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigil kehtivatel teatistel on sys_id olemas.'
        ELSE COUNT(*) || ' teatist ilma sys_id-ta.'
    END
FROM staging.raw_metsateatis
WHERE sys_id IS NULL;

-- ============================================================
-- TEST 2: pindala peab olema positiivne
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis: pindala > 0',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigi teatiste pindala on positiivne.'
        ELSE COUNT(*) || ' teatist nullpindala või negatiivse pindalaga.'
    END
FROM staging.raw_metsateatis
WHERE pindala IS NULL OR pindala <= 0;

-- ============================================================
-- TEST 3: raiutav_maht ei tohi olla negatiivne
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis: raiutav_maht >= 0',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigi teatiste raiutav maht on nullist suurem või null.'
        ELSE COUNT(*) || ' teatist negatiivse raiutava mahuga.'
    END
FROM staging.raw_metsateatis
WHERE raiutav_maht < 0;

-- ============================================================
-- TEST 4: otsus on JAH või EI
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis: otsus in (JAH, EI)',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigi teatiste otsus on JAH või EI.'
        ELSE COUNT(*) || ' teatist tundmatu otsusega.'
    END
FROM staging.raw_metsateatis
WHERE otsus NOT IN ('JAH', 'EI');

-- ============================================================
-- TEST 5: too_kood ei tohi olla NULL
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis: too_kood not null',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigil teatistel on raieliigi kood olemas.'
        ELSE COUNT(*) || ' teatist ilma raieliigi koodita.'
    END
FROM staging.raw_metsateatis
WHERE too_kood IS NULL;

-- ============================================================
-- TEST 6: otsus_kinnitatud_kp ei tohi olla NULL
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis: otsus_kinnitatud_kp not null',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigil teatistel on otsuse kuupäev olemas.'
        ELSE COUNT(*) || ' teatist ilma otsuse kuupäevata.'
    END
FROM staging.raw_metsateatis
WHERE otsus_kinnitatud_kp IS NULL;

-- ============================================================
-- TEST 7: geomeetria ei tohi olla NULL
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis: geom not null',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigil teatistel on geomeetria olemas.'
        ELSE COUNT(*) || ' teatist ilma geomeetriata.'
    END
FROM staging.raw_metsateatis
WHERE geom IS NULL;

-- ============================================================
-- TEST 8: geomeetria peab olema kehtiv
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis: geom is valid',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigi teatiste geomeetria on kehtiv.'
        ELSE COUNT(*) || ' teatist vigase geomeetriaga.'
    END
FROM staging.raw_metsateatis
WHERE geom IS NOT NULL AND NOT ST_IsValid(geom);

-- ============================================================
-- TEST 9: KOV piirid on laaditud (vähemalt 70 omavalitsust)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_kov_piirid: minimaalne arv',
    CASE WHEN COUNT(*) >= 70 THEN 'passed' ELSE 'failed' END,
    GREATEST(0, 70 - COUNT(*))::integer,
    'KOV piire laaditud: ' || COUNT(*) || ' (oodatav vähemalt 70).'
FROM staging.raw_kov_piirid;

-- ============================================================
-- TEST 10: mart tabel on täidetud
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'mart_raie_kov: tabel ei ole tühi',
    CASE WHEN COUNT(*) > 0 THEN 'passed' ELSE 'failed' END,
    CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END::integer,
    CASE WHEN COUNT(*) > 0
        THEN 'Mart tabelis on ' || COUNT(*) || ' rida.'
        ELSE 'Mart tabel on tühi — transformatsioon pole käivitatud.'
    END
FROM mart.mart_raie_kov;

-- ============================================================
-- TEST 11: arhiivi sys_id unikaalsus
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis_arhiiv: sys_id unikaalne',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõik arhiivi sys_id väärtused on unikaalsed.'
        ELSE COUNT(*) || ' duplikaatset sys_id arhiivis.'
    END
FROM (
    SELECT sys_id
    FROM staging.raw_metsateatis_arhiiv
    GROUP BY sys_id
    HAVING COUNT(*) > 1
) dup;

-- ============================================================
-- Näita kokkuvõte
-- ============================================================
SELECT
    test_name,
    status,
    failed_rows,
    message
FROM quality.test_results
ORDER BY status DESC, test_name;
