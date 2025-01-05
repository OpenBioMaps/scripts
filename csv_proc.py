# @Miklós Bán banm@vocs.unideb.hu
# 2024-05-31
# Version 1.2
# A brute force csv processing and transforming to create a postgres table
#
# It uses a json config file
#{
#    "dbhost": "",
#    "dbname": "",
#    "dbuser": "",
#    "dbpass": "",
#    "dbport": "",
#    "db_schema_name": "",  //default is public
#    "db_table_name": "",   //default is the file's name
#    "csv_file": "",        //optional can be passed as a cml argument
#    "csv_sep": ";"         // default is ,
#    "csv_quote": "'",      // default is "
#    "import_data": false,   // print to stdout or execute postgres commands
#    "create_table": true
#}

# Usage:
# python3 csv_proc.py config.json [x.csv]

import pandas as pd
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
import re
import sys
import os 
import json
from datetime import datetime
import warnings
import argparse
import numpy as np
import chardet

# Elnyomjuk a UserWarning típusú figyelmeztetéseket
warnings.filterwarnings("ignore", category=UserWarning)


# Argumentumok definiálása
parser = argparse.ArgumentParser(description="CSV Processing application.")
parser.add_argument("config_file", help="Config file name")
parser.add_argument("--csv_file", help="csv file name")

# Argumentumok beolvasása
args = parser.parse_args()

# Ellenőrzés, hogy megadott-e a felhasználó argumentumokat
if not args.config_file:
    print("Error: No config file name provided!")
    sys.exit(1)

# Reading config file
try:
    with open(args.config_file, 'r') as config_file:
        config = json.load(config_file)
except FileNotFoundError:
    print(f"Error: The given config file not found: {args.config_file}")
    sys.exit(1)

file_name = config.get('csv_file', args.csv_file)
separator = config.get('csv_sep', ',')
quote = config.get('csv_quote', '"')
import_data = config.get('import_data', False)
insert_data = config.get('insert_data', False)
create_table = config.get('create_table', True)
delete_data = config.get('delete_data', False)
encoding = config.get('character_encoding', 'utf8')
sample_size = config.get('sample_size', 4000)
row_error_check = config.get('row_error_check', False)

# Detecting character encoding
with open(file_name, 'rb') as f:
    result = chardet.detect(f.read(30000))  # Trying to detect using the first 10K bytes
    encoding = result['encoding']

# Reading a sample from the input file
with open(file_name, mode='r', encoding='utf-8') as file:
    sample_df = pd.read_csv(file, sep=separator, quotechar=quote, nrows=sample_size)

# Type check
def infer_sql_type(series):
    if series.isnull().all():
        return 'TEXT'

    if pd.api.types.is_integer_dtype(series):
        max_val = series.max()
        min_val = series.min()
        if pd.api.types.is_integer_dtype(series) and (min_val >= -2147483648 and max_val <= 2147483647):
            return 'INTEGER'
        else:
            return 'BIGINT'
    elif pd.api.types.is_float_dtype(series):
        max_val = series.max()
        min_val = series.min()
        if series.apply(lambda x: len(str(x).split('.')[-1]) if '.' in str(x) else 0).max() > 6:
            return 'NUMERIC'
        elif np.finfo(np.float32).min <= min_val <= np.finfo(np.float32).max and np.finfo(np.float32).min <= max_val <= np.finfo(np.float32).max:
            return 'REAL'  # 32 bites lebegőpontos szám
        else:
            return 'DOUBLE PRECISION'  # 64 bites lebegőpontos szám
    else:
        # Time típus ellenőrzése: csak HH:MM vagy HH:MM:SS formátumú értékek
        time_pattern = series.dropna().apply(lambda x: isinstance(x, str) and pd.to_datetime(x, format='%H:%M:%S', errors='coerce') is not pd.NaT or
                                             pd.to_datetime(x, format='%H:%M', errors='coerce') is not pd.NaT)
        if time_pattern.all():
            return 'TIME WITHOUT TIME ZONE'

        # Timestamp vagy Date típus ellenőrzése
        try:
            converted_series = pd.to_datetime(series, errors='coerce', utc=True)
            if converted_series.notnull().all():
                if (converted_series.dt.hour != 0).any() or (converted_series.dt.minute != 0).any() or (converted_series.dt.second != 0).any():
                    return 'TIMESTAMP WITHOUT TIME ZONE'
                return 'DATE'
        except Exception:
            pass
        
        # Minden egyéb text
        return 'TEXT'

# Field name conversion
def normalize_column_names(df):
    df.columns = df.columns.str.replace(' ', '_').str.lower().str.normalize('NFKD').str.encode('ascii', errors='ignore').str.decode('utf-8')
    df.columns = df.columns.map(lambda x: re.sub(r'\W+', '', x))
    df.columns = ['c' + col if col[0].isdigit() else col for col in df.columns]
    return df

# Field name normalization based on the sample data
sample_df = normalize_column_names(sample_df)

# Field/Column type assign
print("Detecting column types...")
column_types = {col: infer_sql_type(sample_df[col]) for col in sample_df.columns}

# Reading input file
with open(file_name, mode='r', encoding='utf-8') as file:
    df = pd.read_csv(file, sep=separator, quotechar=quote, low_memory=False)

# Normalize the column names for the main DataFrame as well
df = normalize_column_names(df)

# DB Connect, and cursor
conn = psycopg2.connect(
    host=config['dbhost'],
    database=config['dbname'],
    port=config.get('dbport',5432),
    user=config['dbuser'],
    password=config['dbpass']
)
conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
cur = conn.cursor()

# Creating table name from the file name
base_name = os.path.splitext(os.path.basename(file_name))[0]
table_name = config['db_table_name'] if config['db_table_name'] else ('t' + base_name if base_name[0].isdigit() else base_name)
schema_name = config['db_schema_name'] if config['db_schema_name'] else 'public'

columns_with_types = ',\n'.join([f'"{col}" {column_types[col]}' for col in df.columns])
create_table_query = f'CREATE TABLE {schema_name}.{table_name} (\n{columns_with_types});'
delete_data_query = f'DELETE FROM {schema_name}.{table_name};'

if import_data:
    try:
        # Begin a transaction
        cur.execute("BEGIN;")
        
        if create_table:
            cur.execute(create_table_query)

        if delete_data:
            print("Do you want to truncate the destination table?")
            print(f"   `{delete_data_query}`")
            answer = input("yes/no: ").strip().lower()
            if answer == 'yes':
                cur.execute(delete_data_query)

        # Import data
        if insert_data:

            # A progress bar
            if row_error_check:
                print("Inserting rows:")
                total_rows = df.shape[0]  # row number in the data.frame
                progress_bar_length = 10
                step = total_rows // progress_bar_length   # on every 10% print one point
                # Print the empty progress bar
                print(f"[{' ' * progress_bar_length}]", end='', flush=True)
                # Go back to the beginning of row
                print("\r[", end='', flush=True)
            else:
                print("Processing rows...")

            rows = []
            for index, row in df.iterrows():

                #clean_row = [None if pd.isna(val) or val == '' else val for val in row]
                clean_row = []
                for col_name, val in zip(df.columns, row):
                    # Üres mezők kezelése
                    if pd.isna(val) or val == '':
                        clean_row.append(None)
                    # Csak az 'time' vagy 'timestamp' típusú oszlopokban végezzük el a formázást
                    elif col_name in column_types and column_types[col_name] in ['TIME WITHOUT TIME ZONE']:
                        if isinstance(val, str):
                            try:
                                # Ha 'HH:MM' formátumú, akkor kiegészítjük 'HH:MM:00'-ra
                                time_obj = datetime.strptime(val, '%H:%M')
                                clean_row.append(time_obj.strftime('%H:%M:00'))
                            except ValueError:
                                # Ha nem 'HH:MM' formátumú, hagyjuk az eredeti értéket
                                clean_row.append(val)
                        else:
                            clean_row.append(val)
                    else:
                        clean_row.append(val)

                # Soronkénti hibaellenőrzés
                if row_error_check:
                    insert_query = f"INSERT INTO {schema_name}.{table_name} VALUES ({', '.join(['%s'] * len(clean_row))})"
                    try:
                        cur.execute(insert_query, tuple(clean_row))
                    except Exception as e:
                        # Ha egyéni sorban hiba történik, kiírjuk a sor számát és a hibát, majd kilépünk
                        print(f"Error on row {index + 1}: {e}")
                        cur.execute("ROLLBACK;")
                        print("Transaction rolled back due to error.")
                        break  # Opció: megszakítja a teljes importálási folyamatot

                    # print progress
                    if (index + 1) % step == 0:  # on every 10% print one point
                        print(".", end='', flush=True)  # print point without new line
                else:
                    rows.append(tuple(clean_row))  # Tiszta sor hozzáadása a listához
            
            if row_error_check:
                print("]")  # The end of the progress bar 

            if not row_error_check:
                print("Inserting table...")
                # Tömbös beillesztés az executemany használatával
                insert_query = f"INSERT INTO {schema_name}.{table_name} VALUES ({', '.join(['%s'] * len(df.columns))})"
                try:
                    cur.executemany(insert_query, rows)
                except Exception as e:
                    print(f"Error occurred: {e}")
                    cur.execute("ROLLBACK;")

        # Finsih the transaction
        cur.execute("COMMIT;")
        print("Done")
    
    except Exception as e:
        print(f"Error occurred during database operation: {e}")
        cur.execute("ROLLBACK;")
        print("Transaction rolled back due to error.")
    
else:
    # A DEBUG option: printing instead of SQL operations
    # Print create table
    if create_table:
        print(create_table_query)

    if delete_data:
        print(delete_data_query)
    
    # Print data
    if insert_data:
        for index, row in df.iterrows():
            clean_row = []
            for col_name, val in zip(df.columns, row):
                # Üres mezők kezelése
                if pd.isna(val) or val == '':
                    clean_row.append(None)
                # Csak az 'time' vagy 'timestamp' típusú oszlopokban végezzük el a formázást
                elif col_name in column_types and column_types[col_name] in ['TIME WITHOUT TIME ZONE']:
                    if isinstance(val, str):
                        try:
                            # Ha 'HH:MM' formátumú, akkor kiegészítjük 'HH:MM:00'-ra
                            time_obj = datetime.strptime(val, '%H:%M')
                            clean_row.append(time_obj.strftime('%H:%M:00'))
                        except ValueError:
                            # Ha nem 'HH:MM' formátumú, hagyjuk az eredeti értéket
                            clean_row.append(val)
                    else:
                        clean_row.append(val)
                else:
                    clean_row.append(val)

            insert_query = f"INSERT INTO {schema_name}.{table_name} VALUES ({', '.join([repr(val) if val is not None else 'NULL' for val in clean_row])});"
            print(insert_query)

# Close DB
cur.close()
conn.close()

# Write to CSV
#df.to_csv('modified.csv', index=False)
