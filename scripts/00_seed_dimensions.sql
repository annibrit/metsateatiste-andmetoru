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
