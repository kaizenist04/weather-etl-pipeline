import sqlite3
from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt

BASE = Path(__file__).resolve().parent.parent
conn = sqlite3.connect(BASE / "data" / "weather.db")
df = pd.read_sql_query(
    "SELECT city, ROUND(AVG(temp_avg_c),2) AS avg_temp, "
    "ROUND(SUM(rainfall_mm),1) AS rain FROM daily_weather "
    "GROUP BY city ORDER BY avg_temp DESC", conn)

fig, ax = plt.subplots(1, 2, figsize=(10, 4))
ax[0].bar(df["city"], df["avg_temp"], color="#e67e22")
ax[0].set_title("Average temperature (°C)")
ax[1].bar(df["city"], df["rain"], color="#2980b9")
ax[1].set_title("Total rainfall (mm)")
plt.tight_layout()
(BASE / "images").mkdir(exist_ok=True)
plt.savefig(BASE / "images" / "summary_chart.png", dpi=150)
print("Saved images/summary_chart.png")