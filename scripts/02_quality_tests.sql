-- scripts/02_quality_tests.sql
-- ============================================================
-- Metsateatiste andmekvaliteedi testid
-- Kirjutab tulemused quality.test_results tabelisse.
-- Käivitamine: python scripts/run_pipeline.py test
--
-- Staatused:
--   passed  — kõik korras
--   warning — väike probleem (alla lävendi), pipeline jätkab
--   failed  — tõsine probleem, pipeline PEATUB
--
-- Lävendid:
--   vigane geomeetria  < 1%  → warning, >= 1% → failed
--   NULL väärtused     < 5%  → warning, >= 5% → failed
--   duplikaadid        < 0.1% → puhasta + warning, >= 0.1% → puhasta + failed
--   tühi tabel                → alati failed
-- ============================================================

-- Tühjenda eelmised tulemused
TRUNCATE TABLE quality.test_results;

-- ============================================================
-- DUPLIKAATIDE PUHASTUS JA LOGIMINE
-- ============================================================

-- Loo duplikaatide logi tabel kui pole olemas
CREATE TABLE IF NOT EXISTS quality.duplicate_log (
    id              SERIAL PRIMARY KEY,
    tabel           TEXT,
    tunnus          TEXT,
    duplikaatide_arv INTEGER,
    leitud_kp       TIMESTAMP DEFAULT NOW()
);

-- raw_metsateatis duplikaadid: logi ja puhasta
INSERT INTO quality.duplicate_log (tabel, tunnus, duplikaatide_arv)
SELECT 'staging.raw_metsateatis', sys_id::text, COUNT(*) - 1
FROM staging.raw_metsateatis
GROUP BY sys_id
HAVING COUNT(*) > 1;

DELETE FROM staging.raw_metsateatis
WHERE ctid IN (
    SELECT ctid FROM (
        SELECT ctid, ROW_NUMBER() OVER (PARTITION BY sys_id ORDER BY ctid) AS rn
        FROM staging.raw_metsateatis
    ) t WHERE rn > 1
);

-- raw_metsateatis_arhiiv duplikaadid: logi ja puhasta
INSERT INTO quality.duplicate_log (tabel, tunnus, duplikaatide_arv)
SELECT 'staging.raw_metsateatis_arhiiv', sys_id::text, COUNT(*) - 1
FROM staging.raw_metsateatis_arhiiv
GROUP BY sys_id
HAVING COUNT(*) > 1;

DELETE FROM staging.raw_metsateatis_arhiiv
WHERE ctid IN (
    SELECT ctid FROM (
        SELECT ctid, ROW_NUMBER() OVER (PARTITION BY sys_id ORDER BY ctid) AS rn
        FROM staging.raw_metsateatis_arhiiv
    ) t WHERE rn > 1
);

-- raw_kataster duplikaadid: logi ja puhasta
INSERT INTO quality.duplicate_log (tabel, tunnus, duplikaatide_arv)
SELECT 'staging.raw_kataster', tunnus, COUNT(*) - 1
FROM staging.raw_kataster
GROUP BY tunnus
HAVING COUNT(*) > 1;

DELETE FROM staging.raw_kataster
WHERE ctid IN (
    SELECT ctid FROM (
        SELECT ctid, ROW_NUMBER() OVER (PARTITION BY tunnus ORDER BY ctid) AS rn
        FROM staging.raw_kataster
    ) t WHERE rn > 1
);

-- ============================================================
-- TEST 1: raw_metsateatis — sys_id not null
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
-- TEST 2: raw_metsateatis — pindala > 0
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
-- TEST 3: raw_metsateatis — raiutav_maht info (null/0 ei ole viga)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
WITH negatiivsed AS (SELECT COUNT(*) AS neg FROM staging.raw_metsateatis WHERE raiutav_maht < 0),
nullid AS (SELECT COUNT(*) AS nul FROM staging.raw_metsateatis WHERE raiutav_maht = 0 OR raiutav_maht IS NULL)
SELECT
    'raw_metsateatis: raiutav_maht info',
    CASE WHEN neg > 0 THEN 'failed' ELSE 'passed' END,
    neg::integer,
    CASE WHEN neg > 0
        THEN neg || ' teatist negatiivse mahuga (viga!). Nullmaht: ' || nul || ' teatist (normaalne).'
        ELSE 'Negatiivseid mahte pole. Nullmaht: ' || nul || ' teatist (sanitaar- vm raie, normaalne).'
    END
FROM negatiivsed, nullid;

-- ============================================================
-- TEST 4: raw_metsateatis — otsus in (JAH, EI)
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
-- TEST 5: raw_metsateatis — too_kood not null
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
-- TEST 6: raw_metsateatis — otsus_kinnitatud_kp not null
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
-- TEST 7: raw_metsateatis — geom not null
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
-- TEST 8: raw_metsateatis — geom is valid (lävend 1%)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis: geom is valid',
    CASE
        WHEN COUNT(*) = 0 THEN 'passed'
        WHEN COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM staging.raw_metsateatis), 0) < 1 THEN 'warning'
        ELSE 'failed'
    END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigi teatiste geomeetria on kehtiv.'
        ELSE COUNT(*) || ' teatist vigase geomeetriaga ('
            || ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM staging.raw_metsateatis), 0), 2)
            || '% — lävend 1%).'
    END
FROM staging.raw_metsateatis
WHERE geom IS NOT NULL AND NOT ST_IsValid(geom);

-- ============================================================
-- TEST 9: raw_metsateatis — sys_id unikaalsus (pärast puhastust)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
WITH dup AS (
    SELECT COUNT(*) - 1 AS extra
    FROM staging.raw_metsateatis
    GROUP BY sys_id
    HAVING COUNT(*) > 1
),
total AS (SELECT COUNT(*) AS n FROM staging.raw_metsateatis),
dup_count AS (SELECT COALESCE(SUM(extra), 0) AS d FROM dup)
SELECT
    'raw_metsateatis: sys_id unikaalne',
    CASE
        WHEN d = 0 THEN 'passed'
        WHEN d * 100.0 / NULLIF(n, 0) < 0.1 THEN 'warning'
        ELSE 'failed'
    END,
    d::integer,
    CASE WHEN d = 0
        THEN 'Kõik sys_id väärtused on unikaalsed.'
        ELSE d || ' duplikaati puhastatud ('
            || ROUND(d * 100.0 / NULLIF(n, 0), 3) || '% — lävend 0.1%).'
    END
FROM dup_count, total;

-- ============================================================
-- TEST 10: raw_metsateatis_arhiiv — sys_id not null
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis_arhiiv: sys_id not null',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigil arhiivi teatistel on sys_id olemas.'
        ELSE COUNT(*) || ' arhiivi teatist ilma sys_id-ta.'
    END
FROM staging.raw_metsateatis_arhiiv
WHERE sys_id IS NULL;

-- ============================================================
-- TEST 11: raw_metsateatis_arhiiv — sys_id unikaalsus (pärast puhastust)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
WITH dup AS (
    SELECT COUNT(*) - 1 AS extra
    FROM staging.raw_metsateatis_arhiiv
    GROUP BY sys_id
    HAVING COUNT(*) > 1
),
total AS (SELECT COUNT(*) AS n FROM staging.raw_metsateatis_arhiiv),
dup_count AS (SELECT COALESCE(SUM(extra), 0) AS d FROM dup)
SELECT
    'raw_metsateatis_arhiiv: sys_id unikaalne',
    CASE
        WHEN d = 0 THEN 'passed'
        WHEN d * 100.0 / NULLIF(n, 0) < 0.1 THEN 'warning'
        ELSE 'failed'
    END,
    d::integer,
    CASE WHEN d = 0
        THEN 'Kõik arhiivi sys_id väärtused on unikaalsed.'
        ELSE d || ' duplikaati puhastatud ('
            || ROUND(d * 100.0 / NULLIF(n, 0), 3) || '% — lävend 0.1%).'
    END
FROM dup_count, total;

-- ============================================================
-- TEST 12: raw_metsateatis_arhiiv — pindala > 0 (lävend 0.1%)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_metsateatis_arhiiv: pindala > 0',
    CASE
        WHEN COUNT(*) = 0 THEN 'passed'
        WHEN COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM staging.raw_metsateatis_arhiiv), 0) < 0.1 THEN 'warning'
        ELSE 'failed'
    END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigi arhiivi teatiste pindala on positiivne.'
        ELSE COUNT(*) || ' arhiivi teatist nullpindala või negatiivse pindalaga ('
            || ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM staging.raw_metsateatis_arhiiv), 0), 3)
            || '% — lävend 0.1%).'
    END
FROM staging.raw_metsateatis_arhiiv
WHERE pindala IS NULL OR pindala <= 0;

-- ============================================================
-- TEST 13: raw_kataster — tabel ei ole tühi
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_kataster: tabel ei ole tühi',
    CASE WHEN COUNT(*) > 0 THEN 'passed' ELSE 'failed' END,
    CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END::integer,
    CASE WHEN COUNT(*) > 0
        THEN 'Katastris on ' || COUNT(*) || ' kirjet.'
        ELSE 'Kataster on tühi — ingest-kataster pole käivitatud.'
    END
FROM staging.raw_kataster;

-- ============================================================
-- TEST 14: raw_kataster — tunnus not null
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_kataster: tunnus not null',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigil katastri kirjetel on tunnus olemas.'
        ELSE COUNT(*) || ' katastri kirjet ilma tunnuseta.'
    END
FROM staging.raw_kataster
WHERE tunnus IS NULL;

-- ============================================================
-- TEST 15: raw_kataster — tunnus unikaalsus (pärast puhastust)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
WITH dup AS (
    SELECT COUNT(*) - 1 AS extra
    FROM staging.raw_kataster
    GROUP BY tunnus
    HAVING COUNT(*) > 1
),
total AS (SELECT COUNT(*) AS n FROM staging.raw_kataster),
dup_count AS (SELECT COALESCE(SUM(extra), 0) AS d FROM dup)
SELECT
    'raw_kataster: tunnus unikaalne',
    CASE
        WHEN d = 0 THEN 'passed'
        WHEN d * 100.0 / NULLIF(n, 0) < 0.1 THEN 'warning'
        ELSE 'failed'
    END,
    d::integer,
    CASE WHEN d = 0
        THEN 'Kõik katastritunnused on unikaalsed.'
        ELSE d || ' duplikaati puhastatud ('
            || ROUND(d * 100.0 / NULLIF(n, 0), 3) || '% — lävend 0.1%).'
    END
FROM dup_count, total;

-- ============================================================
-- TEST 16: raw_kataster — ov_nimi null alla 5%
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
WITH nullid AS (SELECT COUNT(*) AS n FROM staging.raw_kataster WHERE ov_nimi IS NULL),
total AS (SELECT COUNT(*) AS t FROM staging.raw_kataster)
SELECT
    'raw_kataster: ov_nimi not null',
    CASE
        WHEN n = 0 THEN 'passed'
        WHEN n * 100.0 / NULLIF(t, 0) < 5 THEN 'warning'
        ELSE 'failed'
    END,
    n::integer,
    CASE WHEN n = 0
        THEN 'Kõigil katastri kirjetel on omavalitsuse nimi.'
        ELSE n || ' katastri kirjet ilma ov_nimeta ('
            || ROUND(n * 100.0 / NULLIF(t, 0), 2) || '% — lävend 5%).'
    END
FROM nullid, total;

-- ============================================================
-- TEST 17: raw_kov_piirid — minimaalne arv (>= 70)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_kov_piirid: minimaalne arv',
    CASE WHEN COUNT(*) >= 70 THEN 'passed' ELSE 'failed' END,
    GREATEST(0, 70 - COUNT(*))::integer,
    'KOV piire laaditud: ' || COUNT(*) || ' (oodatav vähemalt 70).'
FROM staging.raw_kov_piirid;

-- ============================================================
-- TEST 18: raw_kov_piirid — onimi not null
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_kov_piirid: onimi not null',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigil KOV kirjetel on nimi olemas.'
        ELSE COUNT(*) || ' KOV kirjet ilma nimeta.'
    END
FROM staging.raw_kov_piirid
WHERE onimi IS NULL;

-- ============================================================
-- TEST 19: raw_kov_piirid — geom not null
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_kov_piirid: geom not null',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigil KOV kirjetel on geomeetria olemas.'
        ELSE COUNT(*) || ' KOV kirjet ilma geomeetriata.'
    END
FROM staging.raw_kov_piirid
WHERE geom IS NULL;

-- ============================================================
-- TEST 20: raw_kov_piirid — geom is valid (lävend 1%)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'raw_kov_piirid: geom is valid',
    CASE
        WHEN COUNT(*) = 0 THEN 'passed'
        WHEN COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM staging.raw_kov_piirid), 0) < 1 THEN 'warning'
        ELSE 'failed'
    END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigi KOV piiride geomeetria on kehtiv.'
        ELSE COUNT(*) || ' KOV piiri vigase geomeetriaga ('
            || ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM staging.raw_kov_piirid), 0), 2)
            || '% — lävend 1%).'
    END
FROM staging.raw_kov_piirid
WHERE geom IS NOT NULL AND NOT ST_IsValid(geom);

-- ============================================================
-- TEST 21: mart_raie_kov_kaart — tabel ei ole tühi
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'mart_raie_kov_kaart: tabel ei ole tühi',
    CASE WHEN COUNT(*) > 0 THEN 'passed' ELSE 'failed' END,
    CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END::integer,
    CASE WHEN COUNT(*) > 0
        THEN 'Mart tabelis on ' || COUNT(*) || ' rida.'
        ELSE 'Mart tabel on tühi — transformatsioon pole käivitatud.'
    END
FROM mart.mart_raie_kov_kaart;

-- ============================================================
-- TEST 22: mart_raie_kov_kaart — kogupindala_ha > 0
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'mart_raie_kov_kaart: kogupindala_ha > 0',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigi mart kirjete kogupindala on positiivne.'
        ELSE COUNT(*) || ' mart kirjet nullpindala või negatiivse pindalaga.'
    END
FROM mart.mart_raie_kov_kaart
WHERE kogupindala_ha IS NULL OR kogupindala_ha <= 0;

-- ============================================================
-- TEST 23: mart_raie_kov_kaart — teatiste_arv > 0
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'mart_raie_kov_kaart: teatiste_arv > 0',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigi mart kirjete teatiste arv on positiivne.'
        ELSE COUNT(*) || ' mart kirjet nullteatiste arvuga.'
    END
FROM mart.mart_raie_kov_kaart
WHERE teatiste_arv IS NULL OR teatiste_arv <= 0;

-- ============================================================
-- TEST 24: mart_raie_kov_kaart — geojson not null
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
SELECT
    'mart_raie_kov_kaart: geojson not null',
    CASE WHEN COUNT(*) = 0 THEN 'passed' ELSE 'failed' END,
    COUNT(*)::integer,
    CASE WHEN COUNT(*) = 0
        THEN 'Kõigil mart kirjetel on GeoJSON olemas.'
        ELSE COUNT(*) || ' mart kirjet ilma GeoJSON-ita.'
    END
FROM mart.mart_raie_kov_kaart
WHERE geojson IS NULL;

-- ============================================================
-- TEST 25: KOV liitmine — kehtivate teatiste kaotus (lävend 5%)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
WITH raw AS (SELECT COUNT(*) AS n FROM staging.raw_metsateatis),
kov AS (SELECT COUNT(*) AS n FROM staging.v_metsateatis_kov WHERE kov_nimi IS NOT NULL),
kaotus AS (SELECT raw.n - kov.n AS k, raw.n AS kokku FROM raw, kov)
SELECT
    'v_metsateatis_kov: KOV liitmise kaotus',
    CASE
        WHEN k = 0 THEN 'passed'
        WHEN k * 100.0 / NULLIF(kokku, 0) < 5 THEN 'warning'
        ELSE 'failed'
    END,
    k::integer,
    k || ' kehtivat teatist ilma KOV nimeta ('
        || ROUND(k * 100.0 / NULLIF(kokku, 0), 2)
        || '% — lävend 5%).'
FROM kaotus;

-- ============================================================
-- TEST 26: KOV liitmine — arhiivi kaotus (lävend 10%)
-- ============================================================
INSERT INTO quality.test_results (test_name, status, failed_rows, message)
WITH raw AS (SELECT COUNT(*) AS n FROM staging.raw_metsateatis_arhiiv),
kov AS (SELECT COUNT(*) AS n FROM staging.v_metsateatis_kov_arhiiv WHERE kov_nimi IS NOT NULL),
kaotus AS (SELECT raw.n - kov.n AS k, raw.n AS kokku FROM raw, kov)
SELECT
    'v_metsateatis_kov_arhiiv: KOV liitmise kaotus',
    CASE
        WHEN k = 0 THEN 'passed'
        WHEN k * 100.0 / NULLIF(kokku, 0) < 10 THEN 'warning'
        ELSE 'failed'
    END,
    k::integer,
    k || ' arhiivi teatist ilma KOV nimeta ('
        || ROUND(k * 100.0 / NULLIF(kokku, 0), 2)
        || '% — lävend 10%).'
FROM kaotus;

-- ============================================================
-- KOKKUVÕTE
-- ============================================================
SELECT
    test_name,
    status,
    failed_rows,
    message
FROM quality.test_results
ORDER BY
    CASE status WHEN 'failed' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
    test_name;
