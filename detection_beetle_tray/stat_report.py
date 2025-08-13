import os
import pandas as pd
import shutil

base_dir = "/fs/ess/PAS2136/CarabidImaging-sample-output/TestOutputABTraysCompleted"
csv_path = os.path.join(base_dir, "GDino-Detection-Stats.csv")

df = pd.read_csv(csv_path)

total = len(df)-df['actual'].isna().sum()
match = (df['actual'] == df['detected']).sum()
print(f"Total Trays: {len(df)} Non-NAN Trays: {total} -----> Exact Match: {match} ---> {match/total:.2%}")

print(f"Total number of Beetles: {df['detected'].sum()}")

print(f"No. of cases where detected > actual: {(df['detected'] > df['actual']).sum()}")
print(f"No. of cases where detected < actual: {(df['detected'] < df['actual']).sum()}")


more_dir = os.path.join(base_dir,"More")
os.makedirs(more_dir, exist_ok=True)

less_dir = os.path.join(base_dir,"Less")
os.makedirs(less_dir, exist_ok=True)

more_than_actual = df[df['detected'] > df['actual']]['filename']
less_than_actual = df[df['detected'] < df['actual']]['filename']


for filename in more_than_actual:
    source_path = os.path.join(base_dir, filename)
    dest_path = os.path.join(more_dir, filename)
    if os.path.exists(source_path):
        shutil.copy2(source_path, dest_path)
    else:
        print(f"File {filename} not found in {base_dir}")


for filename in less_than_actual:
    source_path = os.path.join(base_dir, filename)
    dest_path = os.path.join(less_dir, filename)
    if os.path.exists(source_path):
        shutil.copy2(source_path, dest_path)
    else:
        print(f"File {filename} not found in {base_dir}")

print("File copying completed.")


nan_rows = df[df['actual'].isna()]
print(f"Rows with NaN in 'actual': {len(nan_rows)}")
