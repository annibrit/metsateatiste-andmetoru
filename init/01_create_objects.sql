-- Metsateatiste andmetöövoo skeemid ja tabelid.
-- Docker käivitab selle faili automaatselt PostgreSQL-i esimesel stardil
-- (docker-entrypoint-initdb.d kaudu).

-- PostGIS laiendus geomeetria veergude jaoks
CREATE EXTENSION IF NOT EXISTS postgis;

-- Skeemid
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS quality;

-- ============================================================
-- staging: toorandmed API-st
-- ============================================================

-- Iga sissevõtu käivitus saab oma rea, et jälgida ajalugu ja staatust.
CREATE TABLE IF NOT EXISTS staging.pipeline_runs (
    run_id       uuid         PRIMARY KEY,
    started_at   timestamptz  NOT NULL,
    finished_at  timestamptz,
    source_name  text         NOT NULL,
    status       text         NOT NULL,   -- running | success | error
    rows_loaded  integer,
    message      text
);

-- Kehtivad metsateatised (metsaregister:teatis).
-- Igapäevane täislaadimine, upsert sys_id järgi.
-- Geomeetria on Polygon või MultiPolygon, EPSG:3301.
CREATE TABLE IF NOT EXISTS staging.raw_metsateatis (
    sys_id               integer        PRIMARY KEY,
    teatise_nr           text,
    kinnistu_nimetus      text,
    kinnistu_nr          integer,
    metskond             text,
    katastri_nr          text,
    kvartali_nr          text,
    eraldise_nr          integer,
    pindala              numeric(10, 4),
    too_kood             text,
    raiutav_maht         numeric(12, 2),
    otsus                text,
    otsuse_pohjendus     text,
    otsus_kinnitatud_kp  timestamptz,
    kehtiv_kuni          timestamptz,
    geom                 geometry(Geometry, 3301),
    _loaded_at           timestamptz    NOT NULL DEFAULT now(),
    _run_id              uuid
);

-- Arhiveeritud metsateatised (metsaregister:teatis_arhiiv).
-- Ühekordne backfill (~845k kirjet batchitena) + igapäevased lisandused.
-- NB: arhiivis on 'otsuse_pojendus' (kirjaviga), mitte 'otsuse_pohjendus'.
-- Hoiame bronze kihis algsel kujul; silver kiht ühtlustab.
CREATE TABLE IF NOT EXISTS staging.raw_metsateatis_arhiiv (
    sys_id               integer        PRIMARY KEY,
    versioon             numeric,
    teatis_id            integer,
    teatise_nr           text,
    kinnistu_nimetus      text,
    kinnistu_nr          integer,
    metskond             text,
    katastri_nr          text,
    kvartali_nr          text,
    eraldise_nr          integer,
    pindala              numeric(10, 4),
    too_kood             text,
    raiutav_maht         numeric(12, 2),
    otsus                text,
    otsuse_pojendus      text,
    otsus_kinnitatud_kp  timestamptz,
    arhiveerimise_aeg    timestamptz,
    geom                 geometry(Geometry, 3301),
    _loaded_at           timestamptz    NOT NULL DEFAULT now(),
    _run_id              uuid
);

-- KOV-ide piirid (Maa-ameti WFS: ms:omavalitsus_pind).
-- 78 omavalitsust, ühekordne laadimine.
CREATE TABLE IF NOT EXISTS staging.raw_kov_piirid (
    okood                text           PRIMARY KEY,
    onimi                text           NOT NULL,
    mkood                text,
    mnimi                text,
    tyyp                 text,
    vers_algus           date,
    alus                 text,
    geom                 geometry(Geometry, 3301),
    _loaded_at           timestamptz    NOT NULL DEFAULT now()
);

-- ============================================================
-- quality: testide tulemused
-- ============================================================

CREATE TABLE IF NOT EXISTS quality.test_results (
    test_run_at  timestamptz  NOT NULL DEFAULT now(),
    test_name    text         NOT NULL,
    status       text         NOT NULL,   -- passed | failed
    failed_rows  integer      NOT NULL,
    message      text         NOT NULL
);

-- ============================================================
-- Ruumilised indeksid (kiirendavad ST_Intersects päringuid)
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_raw_metsateatis_geom
    ON staging.raw_metsateatis USING gist (geom);

CREATE INDEX IF NOT EXISTS idx_raw_metsateatis_arhiiv_geom
    ON staging.raw_metsateatis_arhiiv USING gist (geom);

CREATE INDEX IF NOT EXISTS idx_raw_kov_piirid_geom
    ON staging.raw_kov_piirid USING gist (geom);

-- Abistab arhiivi backfilli jätkamist ja igapäevaseid lisandusi
CREATE INDEX IF NOT EXISTS idx_raw_metsateatis_arhiiv_aeg
    ON staging.raw_metsateatis_arhiiv (arhiveerimise_aeg);

-- Katastritüksuste KOV-viidete tabel (Maa-ameti WFS: kataster:KU_piirid).
-- Ainult tunnus + haldusüksused, ilma geomeetriata.
-- Kasutatakse KOV-i nime lisamiseks arhiivi metsateatistele katastritunnuse kaudu.
CREATE TABLE IF NOT EXISTS staging.raw_kataster (
    tunnus       text           PRIMARY KEY,
    ov_nimi      text,
    mk_nimi      text,
    _loaded_at   timestamptz    NOT NULL DEFAULT now()
);
