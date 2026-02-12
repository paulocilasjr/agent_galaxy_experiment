#!/usr/bin/env python3
"""
Step 3: Inspect CSV Schema and Identify Column Indices
"""
import json
import pandas as pd
from bioblend.galaxy import GalaxyInstance

GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"

def main():
    gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

    # Load uploaded datasets
    with open('metadata/uploaded_datasets.json', 'r') as f:
        uploaded_datasets = json.load(f)

    # Get train dataset ID
    train_dataset_id = uploaded_datasets['HANCOCK_train_split.csv']['dataset_id']

    print("Downloading and inspecting training CSV...")
    print("="*60)

    # Download a preview of the CSV
    dataset_content = gi.datasets.download_dataset(train_dataset_id, use_default_filename=False)

    # Save the full CSV locally
    with open('data/HANCOCK_train_split.csv', 'wb') as f:
        f.write(dataset_content)

    print("✅ Downloaded training CSV")

    # Load with pandas
    df_train = pd.read_csv('data/HANCOCK_train_split.csv')

    print(f"\nDataset Shape: {df_train.shape[0]} rows x {df_train.shape[1]} columns")
    print("\nColumn Names and Indices:")
    print("-"*60)

    schema_info = {}
    for idx, col in enumerate(df_train.columns):
        print(f"Column {idx}: {col}")
        schema_info[col] = {
            'index': idx,
            'dtype': str(df_train[col].dtype),
            'null_count': int(df_train[col].isnull().sum()),
            'unique_count': int(df_train[col].nunique())
        }

    print("\nFirst 5 rows:")
    print(df_train.head())

    # Identify key columns
    print("\n" + "="*60)
    print("KEY COLUMN IDENTIFICATION:")
    print("="*60)

    # Find patient ID column
    patient_id_col = None
    for col in df_train.columns:
        if 'patient' in col.lower() and 'id' in col.lower():
            patient_id_col = col
            break

    # Find target column
    target_col = None
    for col in df_train.columns:
        if 'target' in col.lower() or 'recurrence' in col.lower():
            target_col = col
            break

    # Find image path columns
    image_cols = [col for col in df_train.columns if 'image' in col.lower() and 'path' in col.lower()]

    config = {
        'patient_id_column': {
            'name': patient_id_col,
            'index': list(df_train.columns).index(patient_id_col) if patient_id_col else None
        },
        'target_column': {
            'name': target_col,
            'index': list(df_train.columns).index(target_col) if target_col else None,
            'values': df_train[target_col].value_counts().to_dict() if target_col else None
        },
        'image_columns': [
            {
                'name': col,
                'index': list(df_train.columns).index(col)
            } for col in image_cols
        ],
        'feature_columns': [
            {
                'name': col,
                'index': idx,
                'dtype': str(df_train[col].dtype)
            } for idx, col in enumerate(df_train.columns)
            if col != patient_id_col and col != target_col and col not in image_cols
        ]
    }

    print(f"\n✅ Patient ID Column: {patient_id_col} (index {config['patient_id_column']['index']})")
    print(f"✅ Target Column: {target_col} (index {config['target_column']['index']})")
    print(f"   Target distribution: {config['target_column']['values']}")
    print(f"\n✅ Image Path Columns:")
    for img_col in config['image_columns']:
        print(f"   - {img_col['name']} (index {img_col['index']})")

    print(f"\n✅ Feature Columns: {len(config['feature_columns'])} columns")
    for feat in config['feature_columns'][:5]:  # Show first 5
        print(f"   - {feat['name']} (index {feat['index']}, {feat['dtype']})")
    if len(config['feature_columns']) > 5:
        print(f"   ... and {len(config['feature_columns']) - 5} more")

    # Save configuration
    with open('metadata/csv_schema.json', 'w') as f:
        json.dump(schema_info, f, indent=2)

    with open('metadata/column_config.json', 'w') as f:
        json.dump(config, f, indent=2)

    print("\n" + "="*60)
    print("✅ Phase 3 Complete: CSV schema inspected and column indices identified")
    print("="*60)
    print(f"Schema saved to: metadata/csv_schema.json")
    print(f"Column config saved to: metadata/column_config.json")

if __name__ == "__main__":
    import os
    os.makedirs('data', exist_ok=True)
    main()
