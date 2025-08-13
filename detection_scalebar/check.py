import os
import pandas as pd

csv_path = "/fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysScalebar/scalebars.csv"

df = pd.read_csv(csv_path)

for col in df.columns:
    print(f"Column: {col} ---> NaN values: {df[col].isna().sum()}")

print(df["number of scalebars"].value_counts())
print(df["checkflag"].value_counts())

