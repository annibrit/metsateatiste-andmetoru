-- Metsateatiste transformatsioonikiht.
-- Loob staging.v_metsateatis_kov ja staging.v_metsateatis_kov_arhiiv
-- katastritunnuse kaudu KOV nime lisamisega ning mart tabelid mõõdikutega.

-- KOV piirid parandatakse ainult siis, kui tabelit pole veel loodud või on tühi.
-- KOV-id muutuvad harva, seega ei pea seda iga transformatsiooniga uuesti tegema.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'staging'
          AND table_name   = 'kov_piirid_parandatud'
    ) OR (SELECT COUNT(*) FROM staging.kov_piirid_parandatud) = 0 THEN
        DROP TABLE IF EXISTS staging.kov_piirid_parandatud;
        CREATE TABLE staging.kov_piirid_parandatud AS
        SELECT * FROM staging.raw_kov_piirid;
        UPDATE staging.kov_piirid_parandatud
           SET geom = ST_MakeValid(geom)
         WHERE NOT ST_IsValid(geom);
        CREATE INDEX ON staging.kov_piirid_parandatud USING gist(geom);
        RAISE NOTICE 'kov_piirid_parandatud loodud.';
    ELSE
        RAISE NOTICE 'kov_piirid_parandatud on juba olemas, ei vaheta.';
    END IF;
END $$;

DROP TABLE IF EXISTS staging.v_metsateatis_kov;

CREATE TABLE staging.v_metsateatis_kov AS
SELECT
    m.sys_id,
    m.teatise_nr,
    m.kinnistu_nimetus,
    m.metskond,
    m.katastri_nr,
    m.pindala,
    m.too_kood,
    COALESCE(d.raieliik, m.too_kood)           AS raieliik,
    m.raiutav_maht,
    m.otsus,
    m.otsus_kinnitatud_kp,
    m.kehtiv_kuni,
    EXTRACT(YEAR FROM m.otsus_kinnitatud_kp)::int AS aasta,
    TRUE                                        AS aktiivne,
    k.ov_nimi                                  AS kov_nimi,
    k.mk_nimi                                  AS maakond,
    m.geom
FROM staging.raw_metsateatis AS m
LEFT JOIN staging.raw_kataster AS k
    ON m.katastri_nr = k.tunnus
LEFT JOIN staging.dim_raieliik AS d
    ON m.too_kood = d.too_kood;


-- ============================================================
-- staging.v_metsateatis_kov_arhiiv
-- Arhiivitud teatised koos KOV nimega (katastritunnuse kaudu).
-- Ruumilise joini asemel kasutatakse katastri viidetabelit,
-- sest 845k kirje peale oleks spatial join liiga aeglane.
-- ============================================================

DROP TABLE IF EXISTS staging.v_metsateatis_kov_arhiiv;

CREATE TABLE staging.v_metsateatis_kov_arhiiv AS
SELECT
    m.sys_id,
    m.teatise_nr,
    m.kinnistu_nimetus,
    m.metskond,
    m.katastri_nr,
    m.pindala,
    m.too_kood,
    COALESCE(d.raieliik, m.too_kood)           AS raieliik,
    m.raiutav_maht,
    m.otsus,
    m.otsus_kinnitatud_kp,
    m.arhiveerimise_aeg,
    EXTRACT(YEAR FROM m.otsus_kinnitatud_kp)::int AS aasta,
    k.ov_nimi                                  AS kov_nimi,
    k.mk_nimi                                  AS maakond
FROM staging.raw_metsateatis_arhiiv AS m
LEFT JOIN staging.raw_kataster AS k
    ON m.katastri_nr = k.tunnus
LEFT JOIN staging.dim_raieliik AS d
    ON m.too_kood = d.too_kood;

-- ============================================================
-- mart.mart_raie_kov
-- Raienäitajad omavalitsuse, aasta ja raieliigi kaupa.
-- ============================================================

DROP TABLE IF EXISTS mart.mart_raie_kov;

CREATE TABLE mart.mart_raie_kov AS
SELECT
    maakond,
    kov_nimi,
    aasta,
    raieliik,
    COUNT(sys_id)              AS teatiste_arv,
    ROUND(SUM(pindala), 2)     AS kogupindala_ha,
    ROUND(SUM(raiutav_maht), 0) AS kogumaht_m3
FROM staging.v_metsateatis_kov
WHERE kov_nimi IS NOT NULL
  AND aasta    IS NOT NULL
GROUP BY maakond, kov_nimi, aasta, raieliik;

-- ============================================================
-- mart.mart_teatised_kaardile
-- Iga teatis ühe punktina kaardil — Superseti scatter plot jaoks.
-- Koordinaadid on WGS84 (EPSG:4326) kraadides (lon/lat).
-- Filtreeritav aasta ja raieliigi järgi.
-- ============================================================

DROP TABLE IF EXISTS mart.mart_teatised_kaardile;

CREATE TABLE mart.mart_teatised_kaardile AS
SELECT
    m.sys_id,
    m.teatise_nr,
    m.kinnistu_nimetus,
    m.aasta,
    m.raieliik,
    m.pindala,
    m.raiutav_maht,
    m.kov_nimi,
    m.maakond,
    ST_X(ST_Transform(ST_Centroid(m.geom), 4326)) AS lon,
    ST_Y(ST_Transform(ST_Centroid(m.geom), 4326)) AS lat
FROM staging.v_metsateatis_kov AS m
WHERE m.geom IS NOT NULL
  AND m.aasta IS NOT NULL;

-- ============================================================
-- mart.mart_raie_kov_kaart
-- Raienäitajad KOV-i kaupa koos piiripolügooniga — koropletkaardi jaoks.
-- Deck.gl Polygon chart kasutab geojson veergu (WGS84).
-- Filtreeritav aasta ja raieliigi järgi.
-- ============================================================

DROP TABLE IF EXISTS mart.mart_raie_kov_kaart;

CREATE TABLE mart.mart_raie_kov_kaart AS
SELECT
    r.maakond,
    r.kov_nimi,
    r.aasta,
    r.raieliik,
    r.teatiste_arv,
    r.kogupindala_ha,
    r.kogumaht_m3,
    ST_AsGeoJSON(ST_Transform(k.geom, 4326)) AS geojson
FROM mart.mart_raie_kov AS r
LEFT JOIN staging.kov_piirid_parandatud AS k
    ON r.kov_nimi = k.onimi
WHERE k.geom IS NOT NULL;
