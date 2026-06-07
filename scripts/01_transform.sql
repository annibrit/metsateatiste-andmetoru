-- Metsateatiste transformatsioonikiht.
-- Loob staging.v_metsateatis_kov ja staging.v_metsateatis_kov_arhiiv
-- katastritunnuse kaudu KOV nime lisamisega ning mart tabeli mõõdikutega.

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
-- Katastritunnused aga muutuvad ajas seega kaotame ca 7%
-- arhiivi teatistest, sest neile ei saa KOVi nime juurde
-- (ilmselt varem eksisteerinud katastrinumbrit täna enam ei eksisteeri)
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

-- kuna varasemalt olid meil ka kõik need tabelid, siis igaksjuhuks
-- dropime need tabelid, kui kellelgi on veel jäänud eelmistest runidest

DROP TABLE IF EXISTS mart.mart_raie_kov;

DROP TABLE IF EXISTS staging.kov_piirid_parandatud;

DROP TABLE IF EXISTS mart.mart_teatised_kaardile;
-- ============================================================
-- mart.mart_raie_kov_kaart
-- Raienäitajad (kehtivad teatised + arhiiv) KOV-i kaupa
-- koos piiripolügooniga — koropletkaardi jaoks.
-- Sammud: 1) agregeeri tekstandmed (GROUP BY ilma geomeetriata)
--          2) join KOV piiridega geomeetria lisamiseks (ainult 78 rida)
-- ============================================================

DROP TABLE IF EXISTS mart.mart_raie_kov_kaart;

CREATE TABLE mart.mart_raie_kov_kaart AS
SELECT
    agg.maakond,
    agg.kov_nimi,
    agg.aasta,
    agg.raieliik,
    agg.teatiste_arv,
    agg.kogupindala_ha,
    agg.kogumaht_m3,
    ST_AsGeoJSON(ST_Simplify(ST_Transform(k.geom, 4326), 0.001)) AS geojson
FROM (
    SELECT
        maakond,
        kov_nimi,
        aasta,
        raieliik,
        COUNT(sys_id)               AS teatiste_arv,
        ROUND(SUM(pindala), 2)      AS kogupindala_ha,
        ROUND(SUM(raiutav_maht), 0) AS kogumaht_m3
    FROM (
        SELECT sys_id, kov_nimi, maakond, aasta, raieliik, pindala, raiutav_maht
        FROM staging.v_metsateatis_kov
        WHERE kov_nimi IS NOT NULL AND aasta >= 2018
        UNION ALL
        SELECT sys_id, kov_nimi, maakond, aasta, raieliik, pindala, raiutav_maht
        FROM staging.v_metsateatis_kov_arhiiv
        WHERE kov_nimi IS NOT NULL AND aasta >= 2018
    ) AS c
    GROUP BY maakond, kov_nimi, aasta, raieliik
) AS agg
LEFT JOIN staging.raw_kov_piirid AS k
    ON agg.kov_nimi = k.onimi
WHERE k.geom IS NOT NULL;
