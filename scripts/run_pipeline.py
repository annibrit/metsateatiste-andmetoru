"""Metsateatiste andmetöövoog.

Skript pärib Metsaregistri WFS-ist kehtivad ja arhiveeritud metsateatised,
Maa-ameti WFS-ist KOV piirid, ning salvestab need staging kihti.
Transformatsioonid ja kvaliteeditestid käivitatakse eraldi SQL-failidena.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import psycopg2

# Kasutame requests teeki HTTP päringuteks (sama mis Jupyter testides)
import requests


SCRIPT_DIR = Path(__file__).resolve().parent
TRANSFORM_SQL = SCRIPT_DIR / "01_transform.sql"
QUALITY_SQL = SCRIPT_DIR / "02_quality_tests.sql"
SEED_SQL = SCRIPT_DIR / "00_seed_dimensions.sql"

# WFS lehekülgede suurus (API max on 5000)
WFS_PAGE_SIZE = 5000


class UserFacingError(RuntimeError):
    """Viga, mille sõnum sobib otse kasutajale näitamiseks."""


def log(message: str) -> None:
    print(message, flush=True)


def get_env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def get_connection():
    return psycopg2.connect(
        host=get_env("DB_HOST", "db"),
        port=get_env("DB_PORT", "5432"),
        user=get_env("DB_USER", "metsaregister"),
        password=get_env("DB_PASSWORD", "metsaregister"),
        dbname=get_env("DB_NAME", "metsaregister"),
    )


# ============================================================
# WFS pärimine
# ============================================================

def fetch_wfs_page(
    base_url: str,
    type_name: str,
    start_index: int = 0,
    count: int = WFS_PAGE_SIZE,
    cql_filter: str | None = None,
    property_names: list[str] | None = None,
) -> dict:
    """Pärib ühe lehekülje WFS feature'eid GeoJSON-ina."""
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeName": type_name,
        "outputFormat": "application/json",
        "count": count,
        "startIndex": start_index,
    }
    if cql_filter:
        params["CQL_FILTER"] = cql_filter
    if property_names:
        params["propertyName"] = ",".join(property_names)

    try:
        resp = requests.get(base_url, params=params, timeout=120)
        resp.raise_for_status()
    except requests.RequestException as exc:
        raise UserFacingError(
            f"WFS päring ebaõnnestus ({type_name}, startIndex={start_index}): {exc}"
        ) from exc

    try:
        return resp.json()
    except ValueError as exc:
        raise UserFacingError("WFS vastus ei olnud loetav JSON.") from exc


def fetch_all_wfs(
    base_url: str,
    type_name: str,
    cql_filter: str | None = None,
    property_names: list[str] | None = None,
) -> list[dict]:
    """Pärib kõik feature'id lehekülgede kaupa. Tagastab feature'ide listi."""
    all_features = []
    start_index = 0

    while True:
        data = fetch_wfs_page(
            base_url, type_name, start_index=start_index,
            cql_filter=cql_filter, property_names=property_names,
        )
        features = data.get("features", [])
        all_features.extend(features)

        total = data.get("totalFeatures")
        fetched_so_far = start_index + len(features)

        if total:
            log(f"  {type_name}: {fetched_so_far}/{total} kirjet")
        else:
            log(f"  {type_name}: {fetched_so_far} kirjet (kokku teadmata)")

        # Kui saime vähem kui küsisime, oleme lõpus
        if len(features) < WFS_PAGE_SIZE:
            break

        start_index += WFS_PAGE_SIZE

    return all_features


def feature_geojson(feature: dict) -> str | None:
    """Tagastab feature geomeetria GeoJSON stringina PostGIS-i jaoks."""
    geom = feature.get("geometry")
    if geom is None:
        return None
    return json.dumps(geom)


# ============================================================
# Pipeline runs jälgimine
# ============================================================

def insert_pipeline_run(conn, *, run_id: uuid.UUID, source_name: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO staging.pipeline_runs (run_id, started_at, source_name, status, message)
            VALUES (%s, %s, %s, 'running', 'Laadimine algas.')
            """,
            (str(run_id), datetime.now(timezone.utc), source_name),
        )
    conn.commit()


def finish_pipeline_run(
    conn, *, run_id: uuid.UUID, status: str, rows_loaded: int, message: str,
) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE staging.pipeline_runs
            SET status = %s,
                finished_at = %s,
                rows_loaded = %s,
                message = %s
            WHERE run_id = %s
            """,
            (status, datetime.now(timezone.utc), rows_loaded, message, str(run_id)),
        )
    conn.commit()


# ============================================================
# Kehtivad metsateatised — igapäevane täislaadimine
# ============================================================

def upsert_metsateatis(conn, features: list[dict], run_id: uuid.UUID) -> int:
    """Upsert kehtivad teatised staging.raw_metsateatis tabelisse."""
    loaded = 0
    now = datetime.now(timezone.utc)

    with conn.cursor() as cur:
        for f in features:
            p = f["properties"]
            geojson = feature_geojson(f)

            cur.execute(
                """
                INSERT INTO staging.raw_metsateatis (
                    sys_id, teatise_nr, kinnistu_nimetus, kinnistu_nr,
                    metskond, katastri_nr, kvartali_nr, eraldise_nr,
                    pindala, too_kood, raiutav_maht, otsus,
                    otsuse_pohjendus, otsus_kinnitatud_kp, kehtiv_kuni,
                    geom, _loaded_at, _run_id
                )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    ST_SetSRID(ST_GeomFromGeoJSON(%s), 3301),
                    %s, %s
                )
                ON CONFLICT (sys_id) DO UPDATE SET
                    teatise_nr          = EXCLUDED.teatise_nr,
                    kinnistu_nimetus     = EXCLUDED.kinnistu_nimetus,
                    kinnistu_nr         = EXCLUDED.kinnistu_nr,
                    metskond            = EXCLUDED.metskond,
                    katastri_nr         = EXCLUDED.katastri_nr,
                    kvartali_nr         = EXCLUDED.kvartali_nr,
                    eraldise_nr         = EXCLUDED.eraldise_nr,
                    pindala             = EXCLUDED.pindala,
                    too_kood            = EXCLUDED.too_kood,
                    raiutav_maht        = EXCLUDED.raiutav_maht,
                    otsus               = EXCLUDED.otsus,
                    otsuse_pohjendus    = EXCLUDED.otsuse_pohjendus,
                    otsus_kinnitatud_kp = EXCLUDED.otsus_kinnitatud_kp,
                    kehtiv_kuni         = EXCLUDED.kehtiv_kuni,
                    geom                = EXCLUDED.geom,
                    _loaded_at          = EXCLUDED._loaded_at,
                    _run_id             = EXCLUDED._run_id
                """,
                (
                    p.get("sys_id"),
                    p.get("teatise_nr"),
                    p.get("kinnistu_nimetus"),
                    p.get("kinnistu_nr"),
                    p.get("metskond"),
                    p.get("katastri_nr"),
                    p.get("kvartali_nr"),
                    p.get("eraldise_nr"),
                    p.get("pindala"),
                    p.get("too_kood"),
                    p.get("raiutav_maht"),
                    p.get("otsus"),
                    p.get("otsuse_pohjendus"),
                    p.get("otsus_kinnitatud_kp"),
                    p.get("kehtiv_kuni"),
                    geojson,
                    now,
                    str(run_id),
                ),
            )
            loaded += 1

    conn.commit()
    return loaded


def ingest() -> None:
    """Kehtivate metsateatiste igapäevane täislaadimine."""
    wfs_url = get_env("WFS_BASE_URL", "https://gsavalik.envir.ee/geoserver/metsaregister/ows")
    run_id = uuid.uuid4()

    conn = get_connection()
    try:
        insert_pipeline_run(conn, run_id=run_id, source_name="metsaregister:teatis")
        log("Pärin kehtivaid metsateatiseid...")

        features = fetch_all_wfs(wfs_url, "metsaregister:teatis")
        log(f"Saadud {len(features)} teatist, laadin andmebaasi...")

        loaded = upsert_metsateatis(conn, features, run_id)

        finish_pipeline_run(
            conn, run_id=run_id, status="success", rows_loaded=loaded,
            message=f"Kehtivad teatised laaditud: {loaded} kirjet.",
        )
        log(f"Kehtivad teatised valmis. {loaded} kirjet, run_id: {run_id}")

    except Exception as exc:
        conn.rollback()
        finish_pipeline_run(
            conn, run_id=run_id, status="error", rows_loaded=0, message=str(exc),
        )
        raise
    finally:
        conn.close()


# ============================================================
# KOV piirid — ühekordne laadimine
# ============================================================

def load_kov_piirid(conn, features: list[dict]) -> int:
    """Laadib KOV piiripolügoonid staging.raw_kov_piirid tabelisse.
    Kustutab enne vanad read (truncate + insert), sest KOV-e on ainult ~78."""
    now = datetime.now(timezone.utc)

    with conn.cursor() as cur:
        cur.execute("TRUNCATE TABLE staging.raw_kov_piirid")

        loaded = 0
        for f in features:
            p = f["properties"]
            geojson = feature_geojson(f)

            cur.execute(
                """
                INSERT INTO staging.raw_kov_piirid (
                    okood, onimi, mkood, mnimi, tyyp, vers_algus, alus,
                    geom, _loaded_at
                )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s,
                    ST_SetSRID(ST_GeomFromGeoJSON(%s), 3301),
                    %s
                )
                """,
                (
                    p.get("OKOOD"),
                    p.get("ONIMI"),
                    p.get("MKOOD"),
                    p.get("MNIMI"),
                    p.get("TYYP"),
                    p.get("VERS_ALGUS"),
                    p.get("ALUS"),
                    geojson,
                    now,
                ),
            )
            loaded += 1

    conn.commit()
    return loaded


def ingest_kov() -> None:
    """KOV piiride ühekordne laadimine Maa-ameti WFS-ist."""
    maa_url = get_env("MAA_WFS_BASE_URL", "https://gsavalik.envir.ee/geoserver/ms/ows")

    conn = get_connection()
    try:
        log("Pärin KOV piire Maa-ameti WFS-ist...")
        features = fetch_all_wfs(maa_url, "ms:omavalitsus_pind")
        log(f"Saadud {len(features)} KOV-i, laadin andmebaasi...")

        loaded = load_kov_piirid(conn, features)
        log(f"KOV piirid valmis. {loaded} omavalitsust laaditud.")
    finally:
        conn.close()


# ============================================================
# Katastritüksused — KOV-viidete tabel arhiivi joiniks
# ============================================================

# Kihi nimi (typeName) GetCapabilities vastusest: <Name>kataster:ky_kehtiv</Name> (<Title>KÜ piirid</Title>)
KATASTER_WFS_URL = "https://gsavalik.envir.ee/geoserver/kataster/wfs"
KATASTER_LAYER = "kataster:ky_kehtiv"
KATASTER_FIELDS = ["tunnus", "ov_nimi", "mk_nimi"]


def load_kataster(conn, features: list[dict]) -> int:
    """Laadib katastritüksuste KOV-viited staging.raw_kataster tabelisse.
    Kustutab enne vanad read — täislaadimine iga kord."""
    now = datetime.now(timezone.utc)

    with conn.cursor() as cur:
        cur.execute("TRUNCATE TABLE staging.raw_kataster")
        rows = [
            (
                f["properties"].get("tunnus"),
                f["properties"].get("ov_nimi"),
                f["properties"].get("mk_nimi"),
                now,
            )
            for f in features
            if f["properties"].get("tunnus") is not None
        ]
        cur.executemany(
            "INSERT INTO staging.raw_kataster (tunnus, ov_nimi, mk_nimi, _loaded_at) VALUES (%s, %s, %s, %s)",
            rows,
        )

    conn.commit()
    return len(rows)


def ingest_kataster() -> None:
    """Katastritüksuste KOV-viidete laadimine Maa-ameti WFS-ist.
    Laadib ainult tunnus + ov_nimi + mk_nimi, ilma geomeetriata."""
    conn = get_connection()
    try:
        log("Pärin katastritüksuseid Maa-ameti WFS-ist...")
        features = fetch_all_wfs(
            KATASTER_WFS_URL,
            KATASTER_LAYER,
            property_names=KATASTER_FIELDS,
        )
        log(f"Saadud {len(features)} katastritüksust, laadin andmebaasi...")
        loaded = load_kataster(conn, features)
        log(f"Kataster valmis. {loaded} kirjet laaditud.")
    finally:
        conn.close()


# ============================================================
# Arhiveeritud teatised — backfill + inkrementaalne
# ============================================================

def upsert_metsateatis_arhiiv(conn, features: list[dict], run_id: uuid.UUID) -> int:
    """Upsert arhiivi kirjed staging.raw_metsateatis_arhiiv tabelisse."""
    loaded = 0
    now = datetime.now(timezone.utc)

    with conn.cursor() as cur:
        for f in features:
            p = f["properties"]
            geojson = feature_geojson(f)

            cur.execute(
                """
                INSERT INTO staging.raw_metsateatis_arhiiv (
                    sys_id, versioon, teatis_id, teatise_nr,
                    kinnistu_nimetus, kinnistu_nr, metskond, katastri_nr,
                    kvartali_nr, eraldise_nr, pindala, too_kood,
                    raiutav_maht, otsus, otsuse_pojendus,
                    otsus_kinnitatud_kp, arhiveerimise_aeg,
                    geom, _loaded_at, _run_id
                )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    %s, %s,
                    ST_SetSRID(ST_GeomFromGeoJSON(%s), 3301),
                    %s, %s
                )
                ON CONFLICT (sys_id) DO UPDATE SET
                    versioon            = EXCLUDED.versioon,
                    teatis_id           = EXCLUDED.teatis_id,
                    teatise_nr          = EXCLUDED.teatise_nr,
                    kinnistu_nimetus     = EXCLUDED.kinnistu_nimetus,
                    kinnistu_nr         = EXCLUDED.kinnistu_nr,
                    metskond            = EXCLUDED.metskond,
                    katastri_nr         = EXCLUDED.katastri_nr,
                    kvartali_nr         = EXCLUDED.kvartali_nr,
                    eraldise_nr         = EXCLUDED.eraldise_nr,
                    pindala             = EXCLUDED.pindala,
                    too_kood            = EXCLUDED.too_kood,
                    raiutav_maht        = EXCLUDED.raiutav_maht,
                    otsus               = EXCLUDED.otsus,
                    otsuse_pojendus     = EXCLUDED.otsuse_pojendus,
                    otsus_kinnitatud_kp = EXCLUDED.otsus_kinnitatud_kp,
                    arhiveerimise_aeg   = EXCLUDED.arhiveerimise_aeg,
                    geom                = EXCLUDED.geom,
                    _loaded_at          = EXCLUDED._loaded_at,
                    _run_id             = EXCLUDED._run_id
                """,
                (
                    p.get("sys_id"),
                    p.get("versioon"),
                    p.get("teatis_id"),
                    p.get("teatise_nr"),
                    p.get("kinnistu_nimetus"),
                    p.get("kinnistu_nr"),
                    p.get("metskond"),
                    p.get("katastri_nr"),
                    p.get("kvartali_nr"),
                    p.get("eraldise_nr"),
                    p.get("pindala"),
                    p.get("too_kood"),
                    p.get("raiutav_maht"),
                    p.get("otsus"),
                    p.get("otsuse_pojendus"),
                    p.get("otsus_kinnitatud_kp"),
                    p.get("arhiveerimise_aeg"),
                    geojson,
                    now,
                    str(run_id),
                ),
            )
            loaded += 1

    conn.commit()
    return loaded


def ingest_arhiiv() -> None:
    """Arhiivi laadimine. Kui tabel on tühi, teeb täisbackfilli.
    Kui tabelis on andmed, laadib ainult uued kirjed (arhiveerimise_aeg järgi)."""
    wfs_url = get_env("WFS_BASE_URL", "https://gsavalik.envir.ee/geoserver/metsaregister/ows")
    run_id = uuid.uuid4()

    conn = get_connection()
    try:
        insert_pipeline_run(conn, run_id=run_id, source_name="metsaregister:teatis_arhiiv")

        # Kontrollime, kas tabelis on juba andmeid
        with conn.cursor() as cur:
            cur.execute("SELECT MAX(arhiveerimise_aeg) FROM staging.raw_metsateatis_arhiiv")
            max_date = cur.fetchone()[0]

        if max_date is None:
            # Tabel on tühi — täisbackfill
            log("Arhiiv on tühi, alustan täisbackfilli...")
            cql_filter = None
        else:
            # Inkrementaalne: ainult uuemad kirjed
            # Vormistame kuupäeva WFS CQL formaadis
            cutoff = max_date.strftime("%Y-%m-%dT%H:%M:%SZ")
            cql_filter = f"arhiveerimise_aeg > '{cutoff}'"
            log(f"Inkrementaalne laadimine alates {cutoff}...")

        features = fetch_all_wfs(wfs_url, "metsaregister:teatis_arhiiv", cql_filter=cql_filter)
        log(f"Saadud {len(features)} arhiivikirjet, laadin andmebaasi...")

        loaded = upsert_metsateatis_arhiiv(conn, features, run_id)

        finish_pipeline_run(
            conn, run_id=run_id, status="success", rows_loaded=loaded,
            message=f"Arhiiv laaditud: {loaded} kirjet.",
        )
        log(f"Arhiiv valmis. {loaded} kirjet, run_id: {run_id}")

    except Exception as exc:
        conn.rollback()
        finish_pipeline_run(
            conn, run_id=run_id, status="error", rows_loaded=0, message=str(exc),
        )
        raise
    finally:
        conn.close()


# ============================================================
# Transformatsioon ja kvaliteeditestid
# ============================================================

def execute_sql_file(conn, path: Path) -> None:
    """Käivitab SQL-faili. Kui faili pole, annab selge veateate."""
    if not path.exists():
        raise UserFacingError(f"SQL-fail puudub: {path.name} (see on ilmselt teise grupiliikme ülesanne)")
    log(f"Käivitan SQL-faili {path.name}.")
    sql = path.read_text(encoding="utf-8")
    with conn.cursor() as cur:
        cur.execute(sql)
    conn.commit()


def transform() -> None:
    conn = get_connection()
    try:
        if SEED_SQL.exists():
            execute_sql_file(conn, SEED_SQL)
        execute_sql_file(conn, TRANSFORM_SQL)
        log("Transformatsioon valmis.")
    finally:
        conn.close()


def run_quality_tests() -> None:
    conn = get_connection()
    try:
        execute_sql_file(conn, QUALITY_SQL)
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT test_name, status, failed_rows, message
                FROM quality.test_results
                ORDER BY test_name
                """
            )
            results = cur.fetchall()

        log("Andmekvaliteedi testid:")
        for test_name, status, failed_rows, message in results:
            log(f"  {test_name}: {status} ({failed_rows} vigast rida) — {message}")

        failed = [row for row in results if row[1] == "failed"]
        if failed:
            raise UserFacingError("Vähemalt üks andmekvaliteedi test ebaõnnestus.")
    finally:
        conn.close()


# ============================================================
# Kontrolli tulemusi
# ============================================================

def check_results() -> None:
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM staging.raw_metsateatis")
            kehtivad = cur.fetchone()[0]

            cur.execute("SELECT COUNT(*) FROM staging.raw_metsateatis_arhiiv")
            arhiiv = cur.fetchone()[0]

            cur.execute("SELECT COUNT(*) FROM staging.raw_kov_piirid")
            kov = cur.fetchone()[0]

            cur.execute("SELECT COUNT(*) FROM staging.raw_kataster")
            kataster = cur.fetchone()[0]

        print()
        print("Staging tabelite seis")
        print("---------------------")
        print(f"  raw_metsateatis:         {kehtivad:>10,} kirjet")
        print(f"  raw_metsateatis_arhiiv:  {arhiiv:>10,} kirjet")
        print(f"  raw_kov_piirid:          {kov:>10,} kirjet")
        print(f"  raw_kataster:            {kataster:>10,} kirjet")

        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT run_id, started_at, source_name, status, rows_loaded, message
                FROM staging.pipeline_runs
                ORDER BY started_at DESC
                LIMIT 5
                """
            )
            rows = cur.fetchall()

        print()
        print("Viimased käivitused")
        print("-------------------")
        if not rows:
            print("  (tühi)")
        for _, started, source, status, rows_loaded, _ in rows:
            print(f"  {started}  {source:<35s}  {status:<8s}  {rows_loaded or 0} rida")

    finally:
        conn.close()


# ============================================================
# Andmete kustutamine
# ============================================================

def reset_data() -> None:
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                TRUNCATE TABLE
                    staging.raw_metsateatis,
                    staging.raw_metsateatis_arhiiv,
                    staging.raw_kov_piirid,
                    staging.raw_kataster,
                    staging.pipeline_runs,
                    quality.test_results
                CASCADE
                """
            )
        conn.commit()
        log("Kõik staging ja quality tabelid on tühjendatud.")
    finally:
        conn.close()


# ============================================================
# Kogu töövoog
# ============================================================

def run_all() -> None:
    """Käivitab igapäevase töövoo: kehtivad teatised + KOV piirid + kataster.
    Arhiivi backfill käivitatakse eraldi käsuga (ingest-arhiiv),
    sest see võtab pikalt aega."""
    ingest()
    ingest_kov()
    ingest_kataster()
    if TRANSFORM_SQL.exists():
        transform()
    if QUALITY_SQL.exists():
        run_quality_tests()
    log("Töövoog lõpetatud.")


# ============================================================
# CLI
# ============================================================

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Metsateatiste andmetöövoog.")
    parser.add_argument(
        "command",
        choices=["ingest", "ingest-kov", "ingest-kataster", "ingest-arhiiv", "transform", "test", "check", "reset", "run-all"],
        help="Töövoo samm, mida käivitada.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "ingest":
            ingest()
        elif args.command == "ingest-kov":
            ingest_kov()
        elif args.command == "ingest-kataster":
            ingest_kataster()
        elif args.command == "ingest-arhiiv":
            ingest_arhiiv()
        elif args.command == "transform":
            transform()
        elif args.command == "test":
            run_quality_tests()
        elif args.command == "check":
            check_results()
        elif args.command == "reset":
            reset_data()
        elif args.command == "run-all":
            run_all()
        return 0
    except UserFacingError as exc:
        print(f"Viga: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
