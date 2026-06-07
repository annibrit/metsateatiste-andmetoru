-- Raieliikide dimensioonitabel.
-- Loob mart.dim_raieliik tabeli ja laadib too_kood → raieliik vastavuse.

CREATE TABLE IF NOT EXISTS staging.dim_raieliik (
    too_kood  text PRIMARY KEY,
    raieliik  text NOT NULL
);

TRUNCATE TABLE staging.dim_raieliik;

INSERT INTO staging.dim_raieliik (too_kood, raieliik) VALUES
    ('LR', 'Lageraie'),
    ('HR', 'Harvendusraie'),
    ('AR', 'Aegjärkne raie'),
    ('SR', 'Sanitaarraie'),
    ('HL', 'Häilraie'),
    ('VR', 'Valikraie'),
    ('VE', 'Veerraie'),
    ('RD', 'Raadamine'),
    ('TR', 'Trassiraie'),
    ('KR', 'Kujundusraie');

-- Eesti maakondade ISO 3166-2 koodid — Superseti Country Map jaoks.

CREATE TABLE IF NOT EXISTS staging.dim_maakond_iso (
    maakond   text PRIMARY KEY,
    iso_kood  text NOT NULL
);

TRUNCATE TABLE staging.dim_maakond_iso;

INSERT INTO staging.dim_maakond_iso (maakond, iso_kood) VALUES
    ('Harju maakond',      'EE-37'),
    ('Hiiu maakond',       'EE-39'),
    ('Ida-Viru maakond',   'EE-44'),
    ('Jõgeva maakond',     'EE-49'),
    ('Järva maakond',      'EE-51'),
    ('Lääne maakond',      'EE-57'),
    ('Lääne-Viru maakond', 'EE-59'),
    ('Põlva maakond',      'EE-65'),
    ('Pärnu maakond',      'EE-67'),
    ('Rapla maakond',      'EE-70'),
    ('Saare maakond',      'EE-74'),
    ('Tartu maakond',      'EE-78'),
    ('Valga maakond',      'EE-82'),
    ('Viljandi maakond',   'EE-84'),
    ('Võru maakond',       'EE-86');
