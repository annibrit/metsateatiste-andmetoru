-- Metsateatiste transformatsioonikiht.
-- Parandab vigased KOV-ide piirid 
-- Loob vaate staging.v_metsateatis_kov (kus KOV nimi tuleb juurde spatial joiniga)
-- ja mart tabelid mõõdikutega.

DROP TABLE IF EXISTS staging.kov_piirid_parandatud;
CREATE TABLE staging.kov_piirid_parandatud AS
SELECT * FROM staging.raw_kov_piirid;
UPDATE staging.kov_piirid_parandatud SET geom = ST_MakeValid(geom) WHERE NOT ST_IsValid(geom);
CREATE INDEX ON staging.kov_piirid_parandatud USING gist(geom);

DROP VIEW IF EXISTS staging.v_metsateatis_kov;
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
    k.onimi                                     AS kov_nimi,
    k.mnimi                                     AS maakond,
    m.geom
FROM staging.raw_metsateatis AS m
LEFT JOIN staging.kov_piirid_parandatud AS k
    ON ST_Intersects(ST_PointOnSurface(m.geom), k.geom)
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
