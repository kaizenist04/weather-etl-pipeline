"""Weather ETL pipeline: Open-Meteo API -> Pandas -> SQLite."""
import json
import sqlite3
from datetime import date, timedelta
from pathlib import Path

import pandas as pd
import requests
import time

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = DATA_DIR / "weather.db"
API_URL = "https://archive-api.open-meteo.com/v1/archive"

CITIES = {
    "Bengaluru": (12.97, 77.59),
    "Chennai": (13.08, 80.27),
    "Mumbai": (19.07, 72.88),
    "Delhi": (28.61, 77.21),
}


# ---------- EXTRACT ----------
def extract(city, lat, lon, start, end):
    """Call the API for one city and return the raw JSON."""
    params = {
        "latitude": lat,
        "longitude": lon,
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
        "daily": "temperature_2m_max,temperature_2m_min,precipitation_sum",
        "timezone": "Asia/Kolkata",
    }
    resp = None
    for attempt in range(1, 4):
        try:
            resp = requests.get(API_URL, params=params, timeout=90)
            resp.raise_for_status()
            break
        except requests.exceptions.RequestException as e:
            print(f"  Attempt {attempt}/3 failed for {city}: {type(e).__name__}")
            if attempt == 3:
                raise
            time.sleep(5 * attempt)
    raw = resp.json()
    DATA_DIR.mkdir(exist_ok=True)
    with open(DATA_DIR / f"raw_{city}.json", "w") as f:
        json.dump(raw, f)  # keep the raw copy
    return raw


# ---------- TRANSFORM ----------
def transform(city, raw):
    """Turn raw JSON into a clean DataFrame."""
    df = pd.DataFrame(raw["daily"])
    df = df.rename(columns={
        "time": "date",
        "temperature_2m_max": "temp_max_c",
        "temperature_2m_min": "temp_min_c",
        "precipitation_sum": "rainfall_mm",
    })
    df["city"] = city
    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    for col in ["temp_max_c", "temp_min_c", "rainfall_mm"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.drop_duplicates(subset=["city", "date"])
    df = df.dropna(subset=["date", "temp_max_c", "temp_min_c"])
    df["rainfall_mm"] = df["rainfall_mm"].fillna(0)
    df["temp_avg_c"] = ((df["temp_max_c"] + df["temp_min_c"]) / 2).round(2)
    df["date"] = df["date"].dt.strftime("%Y-%m-%d")
    return df[["city", "date", "temp_max_c", "temp_min_c", "temp_avg_c", "rainfall_mm"]]


# ---------- DATA QUALITY ----------
def quality_checks(df):
    """Fail loudly if the data looks wrong."""
    problems = []
    if df.empty:
        problems.append("DataFrame is empty")
    if df.duplicated(subset=["city", "date"]).any():
        problems.append("duplicate city/date rows found")
    if df[["city", "date", "temp_max_c", "temp_min_c"]].isnull().any().any():
        problems.append("null values in required columns")
    if (df["temp_max_c"] < df["temp_min_c"]).any():
        problems.append("temp_max is lower than temp_min in some rows")
    if (df["rainfall_mm"] < 0).any():
        problems.append("negative rainfall values")
    if problems:
        raise ValueError("Data quality check failed: " + "; ".join(problems))
    print(f"Quality checks passed ({len(df)} rows).")


# ---------- LOAD ----------
def load(df):
    DATA_DIR.mkdir(exist_ok=True)
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS daily_weather (
                city        TEXT NOT NULL,
                date        TEXT NOT NULL,
                temp_max_c  REAL,
                temp_min_c  REAL,
                temp_avg_c  REAL,
                rainfall_mm REAL,
                PRIMARY KEY (city, date)
            )
        """)
        # INSERT OR REPLACE makes the pipeline safe to re-run
        conn.executemany(
            "INSERT OR REPLACE INTO daily_weather VALUES (?,?,?,?,?,?)",
            df.itertuples(index=False, name=None),
        )
    print(f"Loaded {len(df)} rows into {DB_PATH.name}")


def run():
    end = date.today() - timedelta(days=7)  # archive data lags a few days
    start = end - timedelta(days=30)
    frames = []
    for city, (lat, lon) in CITIES.items():
        print(f"Extracting {city}...")
        raw = extract(city, lat, lon, start, end)
        frames.append(transform(city, raw))
    full = pd.concat(frames, ignore_index=True)
    quality_checks(full)
    load(full)


if __name__ == "__main__":
    run()
