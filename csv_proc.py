# @Miklós Bán banm@vocs.unideb.hu
# 2024-05-31
# 2025-02-24
#
# Version 1.33
#
# A brute force csv processing and transforming to create or fill a postgres table
#
# It uses a json config file, which can be combined command line arguments.
#{
#    "dbhost": "",          // Obligatory. An url or ip address of target PostgrSQL server
#    "dbname": "",          // Obligatory. A database name
#    "dbuser": "",          // Obligatory. A user name with connect to the database
#    "dbpass": "",          // Obligatory. A password to autenticate
#    "dbport": "",          // Optional. Default is 5432
#    "db_schema_name": "",  // Optional. Default is public
#    "db_table_name": "",   // Optional. Default is the file's name, can be passed with cml argument --target_table
#    "db_table_comment": "",// Optional. Default is NULL, can be passed with cml argument --table_comment
#    "csv_file": "",        // Obligatory. Data file name we would like to process. Can be passed as a cml argument --csv-file
#    "csv_sep": ";"         // Optional. Default is ,
#    "csv_quote": "'",      // Optional. Default is "
#    "dry_run": true,       // Optional. Default is true, which means printing all SQL commands to the stdout, no operations. If true, executing SQL commands on the server
#    "create_table": true,  // Optional. Default is creating create table command for `db_table_name` in `db_schema_name`. If false, we assume, the target table is already exists.
#    "insert_rows": true,   // Optional. Default is creating insert rows command for `db_table_name`
#    "delete_data": false,  // Optional. Delete data from `db_table_name` before inserting new lines. It has no meaning if the table is a newly created one.
#    "encoding": "utf8",    // Optional. Default is utf8
#    "sample_size": 10000,  // Optional. Default is reading 3000-10000 lines as a sample from the file (depending on the file length) to analyse the column types
#    "row_error_check": false  // Optional. Default is no row based error checking. If true each line will be inserted separately and printing error messages for the spcific row.
#    "sql_copy_no": false   // Optional: Default is false. If sql_copy is not allowed on the sql server, turn this on. This is much slower than the sql_copy.
#}

# Usage:
# python csv_proc.py config.json [--csv_file x.csv] [--target_table table_name] [--table_comment '...']

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
from tqdm import tqdm
from psycopg2.extras import execute_values
import io

# Elnyomjuk a UserWarning típusú figyelmeztetéseket
warnings.filterwarnings("ignore", category=UserWarning)


# Argumentumok definiálása
parser = argparse.ArgumentParser(description="CSV Processing application for Postgres SQL Import.")
parser.add_argument("config_file", help="Config file name")
parser.add_argument("--csv_file", help="Csv file name")
parser.add_argument("--target_table", help="Target table name")
parser.add_argument("--table_comment", help="Table comments")

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

file_name = args.csv_file or config.get('csv_file')
separator = config.get('csv_sep', ',')
quote = config.get('csv_quote', '"')
dry_run = config.get('dry_run', True)
import_data = not dry_run
insert_rows = config.get('insert_rows', True)
create_table = config.get('create_table', True)
delete_data = config.get('delete_data', False)
encoding = config.get('character_encoding', 'utf8')
sample_size = config.get('sample_size', 4000)
row_error_check = config.get('row_error_check', False)
db_table_name = args.target_table or config.get('db_table_name') or None
db_table_comment = args.table_comment or config.get('db_table_comment')
sql_copy_no = config.get('sql_copy_no', False)

if not file_name:
    print("Error: CSV file name not provided. Please specify either --csv_file argument or 'csv_file' in the config file.")
    sys.exit(1)

# Detecting character encoding
with open(file_name, 'rb') as f:
    result = chardet.detect(f.read(30000))  # Trying to detect using the first 10K bytes
    encoding = result['encoding']

def count_lines(file_name):
    with open(file_name, 'r', encoding='utf-8') as f:
        return sum(1 for _ in f) - 1  # header nélkül

# Sampling strategy
def get_sample_indices(total_rows):
    if total_rows <= 3000:
        return list(range(total_rows))

    max_sample = min(sample_size, total_rows) # sample_size default is 10.000

    # 3 részre osztjuk
    chunk = max_sample // 3

    start = list(range(0, chunk))

    middle_start = total_rows // 2 - chunk // 2
    middle = list(range(middle_start, middle_start + chunk))

    end = list(range(total_rows - chunk, total_rows))

    return sorted(set(start + middle + end))

def read_sample_df(file_name, separator, quote):
    total_rows = count_lines(file_name)
    sample_indices = set(get_sample_indices(total_rows))

    def skip_func(i):
        # i = sor index, 0 = header
        if i == 0:
            return False
        return (i - 1) not in sample_indices

    df = pd.read_csv(
        file_name,
        sep=separator,
        quotechar=quote,
        skiprows=skip_func,
        low_memory=False
    )

    return df

def to_sql_literal(val):
    if val is None:
        return 'NULL'
    if isinstance(val, str):
        return "'" + val.replace("'", "''") + "'"
    return str(val)

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

def escape_copy_value(v):
    if v is None:
        return '\\N'

    s = str(v)

    # kritikus escape-ek
    s = s.replace('\\', '\\\\')   # backslash
    s = s.replace('\t', ' ')      # TAB → space
    s = s.replace('\n', ' ')      # newline → space
    s = s.replace('\r', ' ')      # CR → space

    return s

# Field name conversion
def normalize_column_names(df):
    df.columns = df.columns.str.replace(' ', '_').str.lower().str.normalize('NFKD').str.encode('ascii', errors='ignore').str.decode('utf-8')
    df.columns = df.columns.map(lambda x: re.sub(r'\W+', '', x))
    df.columns = ['c' + col if col[0].isdigit() else col for col in df.columns]
    return df


def clean_row_func(row):
    clean_row = []

    for col_name, val in zip(df.columns, row):
        col_type = column_types.get(col_name)

        # ---------------------------
        # NULL kezelés
        # ---------------------------
        if pd.isna(val) or str(val).strip() == '' or str(val).lower() in ['nan', 'none', 'null']:
            clean_row.append(None)

        # ---------------------------
        # INTEGER / BIGINT
        # ---------------------------
        elif col_type in ['INTEGER', 'BIGINT']:
            try:
                clean_row.append(int(float(val)))
            except Exception:
                clean_row.append(None)

        # ---------------------------
        # FLOAT / NUMERIC
        # ---------------------------
        elif col_type in ['REAL', 'DOUBLE PRECISION', 'NUMERIC']:
            try:
                clean_row.append(float(val))
            except Exception:
                clean_row.append(None)

        # ---------------------------
        # TIME
        # ---------------------------
        elif col_type == 'TIME WITHOUT TIME ZONE':
            if isinstance(val, str):
                try:
                    time_obj = datetime.strptime(val, '%H:%M')
                    clean_row.append(time_obj.strftime('%H:%M:00'))
                except ValueError:
                    try:
                        time_obj = datetime.strptime(val, '%H:%M:%S')
                        clean_row.append(time_obj.strftime('%H:%M:%S'))
                    except ValueError:
                        clean_row.append(None)
            else:
                clean_row.append(val)

        # ---------------------------
        # DATE / TIMESTAMP
        # ---------------------------
        elif col_type in ['DATE', 'TIMESTAMP WITHOUT TIME ZONE']:
            try:
                dt = pd.to_datetime(val, errors='coerce')
                if pd.isna(dt):
                    clean_row.append(None)
                else:
                    if col_type == 'DATE':
                        clean_row.append(dt.strftime('%Y-%m-%d'))
                    else:
                        clean_row.append(dt.strftime('%Y-%m-%d %H:%M:%S'))
            except Exception:
                clean_row.append(None)

        # ---------------------------
        # DEFAULT (TEXT stb.)
        # ---------------------------
        else:
            clean_row.append(val)

    return tuple(clean_row)


print("Sampling data for type detection...")
sample_df = read_sample_df(file_name, separator, quote)

# Field name normalization based on the sample data
sample_df = normalize_column_names(sample_df)

# Field/Column type assign
print("Detecting column types...")
column_types = {col: infer_sql_type(sample_df[col]) for col in sample_df.columns}

# Reading input file
with open(file_name, mode='r', encoding='utf-8') as file:
    #df = pd.read_csv(file, sep=separator, quotechar=quote, escapechar='\\', engine='python')
    df = pd.read_csv(file, sep=separator, quotechar=quote, low_memory=False)

# Normalize the column names for the main DataFrame as well
df = normalize_column_names(df)

# DB Connect, and cursor
try:
    conn = psycopg2.connect(
        host=config['dbhost'],
        database=config['dbname'],
        port=config.get('dbport',5432),
        user=config['dbuser'],
        password=config['dbpass']
    )

except psycopg2.OperationalError as e:
    if "does not exist" in str(e):
        print(f"Error: The '{config['dbname']}' database does not exists. Try gisdata")
    else:
        print("Error: Unsuccesful connect to the PostgreSQL database.")
        print(f"Host: {config['dbhost']}")
        print(f"Database: {config['dbname']}")
        print("Check the host name, database name, the connection parameters, and whether the server is running.")
    sys.exit(1)

conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
cur = conn.cursor()

# Creating table name from the file name
base_name = os.path.splitext(os.path.basename(file_name))[0]
table_name = db_table_name if db_table_name else ('t' + base_name if base_name[0].isdigit() else base_name)
schema_name = config['db_schema_name'] if config['db_schema_name'] else 'public'

columns_with_types = ',\n'.join([f'"{col}" {column_types[col]}' for col in df.columns])
create_table_query = f'CREATE TABLE {schema_name}.{table_name} (\n{columns_with_types});'
delete_data_query = f'DELETE FROM {schema_name}.{table_name};'

if db_table_comment:
    safe_comment = db_table_comment.replace("'", "''")
    create_table_query += f"\nCOMMENT ON TABLE {schema_name}.{table_name} IS '{safe_comment}';"

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
        if insert_rows:

            from tqdm import tqdm
            from psycopg2.extras import execute_values
            import io

            print("Preparing data...")

            # biztosítjuk, hogy létezzen
            use_batch_mode = 'sql_copy_no' in locals() and sql_copy_no

            # =========================================================
            # SAFE MODE
            # =========================================================
            if row_error_check:
                print("SAFE MODE")

                insert_query = f"""
                    INSERT INTO {schema_name}.{table_name}
                    VALUES ({', '.join(['%s'] * len(df.columns))})
                """

                for index, row in tqdm(
                    enumerate(df.itertuples(index=False, name=None)),
                    total=len(df),
                    desc="Inserting rows"
                ):
                    clean_row = clean_row_func(row)

                    try:
                        cur.execute(insert_query, clean_row)
                    except Exception as e:
                        print(f"\nError on row {index + 1}: {e}")
                        raise

            # =========================================================
            # BATCH MODE
            # =========================================================
            elif use_batch_mode:
                print("BATCH MODE")

                rows = [
                    clean_row_func(row)
                    for row in tqdm(
                        df.itertuples(index=False, name=None),
                        total=len(df),
                        desc="Preparing rows"
                    )
                ]

                insert_query = f"""
                    INSERT INTO {schema_name}.{table_name}
                    VALUES %s
                """

                try:
                    execute_values(cur, insert_query, rows, page_size=10000)
                except Exception as e:
                    print(f"Error occurred: {e}")
                    raise

            # =========================================================
            # COPY MODE
            # =========================================================
            else:
                print("COPY MODE")

                buffer = io.StringIO()

                for row in tqdm(
                    df.itertuples(index=False, name=None),
                    total=len(df),
                    desc="Preparing buffer"
                ):
                    cleaned = clean_row_func(row)
                    buffer.write(
                        '\t'.join(escape_copy_value(v) for v in cleaned) + '\n'
                    )

                buffer.seek(0)

                copy_sql = f"""
                    COPY {schema_name}.{table_name}
                    FROM STDIN
                    WITH (FORMAT text, DELIMITER '\t', NULL '\\N')
                """

                try:
                    cur.copy_expert(copy_sql, buffer)
                except Exception as e:
                    print(f"COPY failed: {e}")
                    raise
                
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
    if insert_rows:
        for index, row in enumerate(df.itertuples(index=False, name=None)):
            clean_row = clean_row_func(row)

            insert_query = f"""
            INSERT INTO {schema_name}.{table_name}
            VALUES ({', '.join(to_sql_literal(v) for v in clean_row)});
            """

            print(insert_query)

# Close DB
cur.close()
conn.close()

# Write to CSV
#df.to_csv('modified.csv', index=False)
