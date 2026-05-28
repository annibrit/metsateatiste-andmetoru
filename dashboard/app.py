import os
import streamlit as st
import pandas as pd
import folium
from folium.plugins import MarkerCluster
from streamlit_folium import st_folium
import psycopg2
import plotly.express as px
 
# --- Lehe seadistus ---
st.set_page_config(
    page_title="Raieteatised",
    layout="wide"
)
 
# --- Lihtne paroolikaitse ---
PASSWORD = os.getenv("DASHBOARD_PASSWORD", "")
if PASSWORD:
    if "authenticated" not in st.session_state:
        st.session_state.authenticated = False
    if not st.session_state.authenticated:
        st.title("Raieteatiste näidiklaud")
        pwd = st.text_input("Sisesta parool", type="password")
        if st.button("Logi sisse"):
            if pwd == PASSWORD:
                st.session_state.authenticated = True
                st.rerun()
            else:
                st.error("Vale parool")
        st.stop()
 
st.title("Raieteatiste näidiklaud")
 
# --- Andmebaasi ühendus ---
@st.cache_resource
def get_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        user=os.getenv("DB_USER", "metsaregister"),
        password=os.getenv("DB_PASSWORD", ""),
        dbname=os.getenv("DB_NAME", "metsaregister")
    )
 
@st.cache_data(ttl=3600)
def load_data():
    conn = get_connection()
    query = """
        SELECT
            sys_id,
            teatise_nr,
            kinnistu_nimetus,
            metskond,
            katastri_nr,
            pindala,
            too_kood,
            raieliik,
            raiutav_maht,
            otsus,
            otsus_kinnitatud_kp::date AS kp,
            kehtiv_kuni::date AS kehtiv_kuni,
            aasta,
            aktiivne,
            kov_nimi,
            maakond
        FROM staging.v_metsateatis_kov
        ORDER BY otsus_kinnitatud_kp DESC NULLS LAST
    """
    df = pd.read_sql(query, conn)
    return df
 
@st.cache_data(ttl=3600)
def load_geom():
    conn = get_connection()
    query = """
        SELECT
            sys_id,
            ST_Y(ST_Centroid(ST_Transform(geom, 4326))) AS lat,
            ST_X(ST_Centroid(ST_Transform(geom, 4326))) AS lon
        FROM staging.raw_metsateatis
        WHERE geom IS NOT NULL
    """
    return pd.read_sql(query, conn)
 
# --- Andmete laadimine ---
try:
    df = load_data()
    geom_df = load_geom()
    df = df.merge(geom_df, on="sys_id", how="left")
except Exception as e:
    st.error(f"Andmebaasi ühenduse viga: {e}")
    st.stop()
 
# --- Filtrid külgribal ---
st.sidebar.header(" Filtrid")
 
# Maakond
maakonnad = ["Kõik"] + sorted(df["maakond"].dropna().unique().tolist())
valitud_maakond = st.sidebar.selectbox("Maakond", maakonnad)
 
# Vald/KOV — sõltub maakonnast
if valitud_maakond != "Kõik":
    kov_valikud = df[df["maakond"] == valitud_maakond]["kov_nimi"].dropna().unique().tolist()
else:
    kov_valikud = df["kov_nimi"].dropna().unique().tolist()
kov_valikud = ["Kõik"] + sorted(kov_valikud)
valitud_kov = st.sidebar.selectbox("Vald/linn", kov_valikud)
 
# Raieliik
raieliigid = ["Kõik"] + sorted(df["raieliik"].dropna().unique().tolist())
valitud_raieliik = st.sidebar.selectbox("Raieliik", raieliigid)
 
# Otsus
otsused = ["Kõik"] + sorted(df["otsus"].dropna().unique().tolist())
valitud_otsus = st.sidebar.selectbox("Otsus", otsused)
 
# Aasta
aastad = sorted(df["aasta"].dropna().unique().astype(int).tolist(), reverse=True)
valitud_aasta = st.sidebar.selectbox("Aasta", ["Kõik"] + [str(a) for a in aastad])
 
# Ainult aktiivsed
valitud_aktiivne = st.sidebar.checkbox("Ainult aktiivsed raieteatised", value=False)
 
# --- Filtreerimine ---
filtered = df.copy()
if valitud_maakond != "Kõik":
    filtered = filtered[filtered["maakond"] == valitud_maakond]
if valitud_kov != "Kõik":
    filtered = filtered[filtered["kov_nimi"] == valitud_kov]
if valitud_raieliik != "Kõik":
    filtered = filtered[filtered["raieliik"] == valitud_raieliik]
if valitud_otsus != "Kõik":
    filtered = filtered[filtered["otsus"] == valitud_otsus]
if valitud_aasta != "Kõik":
    filtered = filtered[filtered["aasta"] == int(valitud_aasta)]
if valitud_aktiivne:
    filtered = filtered[filtered["aktiivne"] == True]
 
# --- Kokkuvõtte numbrid ---
col1, col2, col3, col4 = st.columns(4)
col1.metric("Raieteatisi", f"{len(filtered):,}")
col2.metric("Kogupindala (ha)", f"{filtered['pindala'].sum():,.1f}")
col3.metric("Raiutav maht (m³)", f"{filtered['raiutav_maht'].sum():,.0f}")
col4.metric("Valdu/linnu", f"{filtered['kov_nimi'].nunique()}")
 
st.divider()
 
# --- Kaart ja diagrammid ---
col_map, col_charts = st.columns([2, 1])
 
with col_map:
    st.subheader("Kaart")
 
    varvid = {
        "Lageraie": "red",
        "Harvendusraie": "orange",
        "Sanitaarraie": "blue",
        "Erikujundusraie": "purple",
        "Valikraie": "green",
        "Kujundusraie": "darkgreen",
    }
 
    map_data = filtered.dropna(subset=["lat", "lon"])
    if not map_data.empty:
        center_lat = map_data["lat"].mean()
        center_lon = map_data["lon"].mean()
        zoom = 8 if valitud_maakond != "Kõik" else 7
        if valitud_kov != "Kõik":
            zoom = 11
    else:
        center_lat, center_lon, zoom = 58.5, 25.0, 7
 
    m = folium.Map(location=[center_lat, center_lon], zoom_start=zoom, tiles="CartoDB positron")
    cluster = MarkerCluster().add_to(m)
 
    for _, row in map_data.iterrows():
        varv = varvid.get(row.get("raieliik", ""), "gray")
        popup_tekst = f"""
        <b>{row['teatise_nr']}</b><br>
        <b>Vald:</b> {row['kov_nimi']}<br>
        <b>Maakond:</b> {row['maakond']}<br>
        <b>Raieliik:</b> {row['raieliik']}<br>
        <b>Pindala:</b> {row['pindala']} ha<br>
        <b>Otsus:</b> {row['otsus']}<br>
        <b>Kuupäev:</b> {row['kp']}
        """
        folium.CircleMarker(
            location=[row["lat"], row["lon"]],
            radius=5,
            color=varv,
            fill=True,
            fill_color=varv,
            fill_opacity=0.7,
            popup=folium.Popup(popup_tekst, max_width=280)
        ).add_to(cluster)
 
    st_folium(m, width=700, height=500)
 
with col_charts:
    st.subheader("Raieliikide jaotus")
    if not filtered.empty:
        rl_df = filtered.groupby("raieliik")["pindala"].sum().reset_index()
        rl_df.columns = ["Raieliik", "Pindala (ha)"]
        fig1 = px.pie(
            rl_df, names="Raieliik", values="Pindala (ha)",
            color_discrete_sequence=px.colors.qualitative.Set2
        )
        fig1.update_layout(margin=dict(t=20, b=20, l=0, r=0))
        st.plotly_chart(fig1, use_container_width=True)
 
    st.subheader("Top 10 valda pindala järgi")
    if not filtered.empty:
        kov_df = (
            filtered.groupby("kov_nimi")["pindala"]
            .sum().reset_index()
            .sort_values("pindala", ascending=False)
            .head(10)
        )
        kov_df.columns = ["Vald/linn", "Pindala (ha)"]
        fig2 = px.bar(
            kov_df, x="Pindala (ha)", y="Vald/linn",
            orientation="h",
            color_discrete_sequence=["#2E8B57"]
        )
        fig2.update_layout(margin=dict(t=20, b=20, l=0, r=0))
        st.plotly_chart(fig2, use_container_width=True)
 
# --- Ajaline trend ---
st.divider()
st.subheader("Raieala ajas")
if not filtered.empty and "aasta" in filtered.columns:
    trend_df = (
        filtered.groupby(["aasta", "raieliik"])["pindala"]
        .sum().reset_index()
    )
    trend_df.columns = ["Aasta", "Raieliik", "Pindala (ha)"]
    fig3 = px.bar(
        trend_df, x="Aasta", y="Pindala (ha)", color="Raieliik",
        color_discrete_sequence=px.colors.qualitative.Set2
    )
    fig3.update_layout(margin=dict(t=20, b=20, l=0, r=0))
    st.plotly_chart(fig3, use_container_width=True)
 
# --- Andmetabel ---
st.divider()
st.subheader("Andmetabel")
st.dataframe(
    filtered[[
        "teatise_nr", "maakond", "kov_nimi", "metskond",
        "raieliik", "pindala", "raiutav_maht", "otsus", "kp"
    ]].rename(columns={
        "teatise_nr": "Teatise nr",
        "maakond": "Maakond",
        "kov_nimi": "Vald/linn",
        "metskond": "Metskond",
        "raieliik": "Raieliik",
        "pindala": "Pindala (ha)",
        "raiutav_maht": "Maht (m³)",
        "otsus": "Otsus",
        "kp": "Kuupäev"
    }),
    use_container_width=True,
    hide_index=True
)