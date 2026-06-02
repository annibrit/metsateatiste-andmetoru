-- Metsateatiste transformatsioonikiht.
-- Loob staging.v_metsateatis_kov ja staging.v_metsateatis_kov_arhiiv
-- katastritunnuse kaudu KOV nime lisamisega ning mart tabelid mõõdikutega.

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
