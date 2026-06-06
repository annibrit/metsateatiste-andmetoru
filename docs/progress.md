# Edenemisraport

## Mis on valmis

- [+ ] Docker Compose käivitab kõik teenused
- [+ ] Andmeid saadakse allikast kätte
- [+ ] Andmed laetakse `staging` kihti
- [+ ] Vähemalt üks transformatsioon toimib: tehtud on KOV-piiride faili geomi parandus, tehtud on spatial join, mis lisab KOV-piiride failist metsateatistele KOV-nimed. Loodud on esimene mart-tabel dashboardi jaoks.
- [+ ] Vähemalt üks näidikulaud on nähtaval
- [+ ] Vähemalt üks andmekvaliteedi test läbib

[Täpsusta lühidalt, mis täpselt valmis on]

## Järgmised sammud

- Superseti kaardirakenduste osas selgus - milline kaardi chart tüüp annab meile selle visuaali mida me tahame JA töötab nende andmetega mis meil on (st millisel kujul geoinfot/koordinaate vaja on)
- Superseti jaoks vajalike mart tabelite koostamiseks transformatsioonid
- Nendele transformatsioonidega kaasas käivad kvaliteeditestid
- Orkestratsioon Airflow-ga
- dbt kasutuselevõtt (kui jääb aega)

## Mis takistab

- Otseselt ei takista, aga on otsustamise/mõttekoht: kuna meil on KOV-i nimede saamiseks vaja teha spatial join, mis on natukene ajakulukas (144k teatise puhul võttis ühe tiimikaaslase arvutis 6 min, teisel 45+ minutit aega, samas seda on vaja teha ainult 1x päevas), siis kuidas kaasata arhiiv (800 000+ metsateatist), ilma et vahetöötlus ei läheks liiga aeglaseks? Alternatiiv oleks lisada KOV-i nimed uue seedtabeliga (katastriüksuste andmete kaudu). Kui jääda spatial joini juurde, kas vahetöötluse tabel teha vaade või tabel (või hoopis materialised view)? Hetkel on tabel, kuna meie algandmete töötlus on natukene keerulisem kui lihtsad filtrid.

## Kontrollpunkt

Käsk, millega saab kontrollida, et töövoog töötab:

```bash
docker compose exec pipeline python scripts/run_pipeline.py check
```

Oodatav tulemus: käsk väljastab staging- ja transformeeritud tabelite ridade
arvu ning viimaste sissevõtu-käivituste staatuse. Töötava süsteemi puhul on
kõik loendid (peale arhiivi) nullist suuremad:

```
Staging tabelite seis
---------------------
  raw_metsateatis:            145,016 kirjet
  raw_metsateatis_arhiiv:           0 kirjet   (arhiiv on sprint 3 ülesanne)
  raw_kov_piirid:                  78 kirjet

Transformeeritud tabelite seis
------------------------------
  v_metsateatis_kov:           145,016 rida
  mart_raie_kov:                 1,431 rida
