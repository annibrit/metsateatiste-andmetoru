# Edenemisraport

## Mis on valmis

- [+ ] Docker Compose käivitab kõik teenused
- [+ ] Andmeid saadakse allikast kätte
- [+ ] Andmed laetakse `staging` kihti
- [+ ] Vähemalt üks transformatsioon toimib: tehtud on KOV-piiride faili geomi parandus, tehtud on spatial join, mis lisab KOV-piiride failist metsateatistele KOV-nimed. Loodud on esimene mart-tabel dashboardi jaoks.
- [ ] Vähemalt üks näidikulaud on nähtaval
- [+ ] Vähemalt üks andmekvaliteedi test läbib

[Täpsusta lühidalt, mis täpselt valmis on]

## Järgmised sammud

- Superseti kaardirakenduste osas selgus - milline chart tüüp annab meile selle visuaali mida me tahame JA töötab nende andmetega mis meil on (st millist geoinfot/koordinaate vaja on?
- Superseti jaoks vajalike mart tabelite koostamiseks transformatsioonid
- Nendele transformatsioonidega kaasas käivad kvaliteeditestid
- Orkestratsioon Airflow-ga
- dbt kasutuselevõtt (kui jääb aega)

## Mis takistab

- Otseselt ei takista, aga on otsustamise/mõttekoht: kuna meil on KOV-i nimede saamiseks vaja teha spatial join, mis on natukene ajakulukas (144k teatise puhul võttis umbes 6 min aega, samas seda on vaja teha ainult 1x päevas), siis kuidas kaasata arhiiv (800 000+ metsateatist), ilma et vahetöötlus ei läheks liiga aeglaseks? Alternatiiv oleks lisada KOV-i nimed uue seedtabeliga (katastriüksuste andmete kaudu). Kui jääda spatial joini juurde, kas vahetöötluse tabel teha vaade või tabel (või hoopis materialised view)? Hetkel on tabel, kuna meie algandmete töötlus on natukene keerulisem kui lihtsad filtrid. 

## Kontrollpunkt

Käsk, millega saab kontrollida, et töövoog töötab:

```bash
# [Lisa siia käsk, mis näitab, et andmed liiguvad allikast näidikulauani]
# Näiteks:
docker compose exec pipeline python scripts/run_pipeline.py check
```

Oodatav tulemus: [Kirjelda, mida töötav süsteem väljastab]
