import os
import hashlib
import mimetypes
import psycopg2
import json
from datetime import datetime
from PIL import Image
from PIL.ExifTags import TAGS
import argparse
from tqdm import tqdm  # Import tqdm for progress bar

# Function to calculate MD5 hash of a file
def calculate_md5(file_path):
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()

# Function to calculate SHA1 hash of a file
def calculate_sha1(file_path):
    hash_sha1 = hashlib.sha1()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_sha1.update(chunk)
    return hash_sha1.hexdigest()

# Function to extract EXIF data if the file is an image
def extract_exif(file_path):
    try:
        image = Image.open(file_path)
        exif_data = image._getexif()
        if exif_data is None:
            return None
        exif = {TAGS.get(tag): value for tag, value in exif_data.items() if tag in TAGS}
        return json.dumps(exif)
    except Exception as e:
        return None

# Function to insert data into the PostgreSQL table
def insert_into_db(conn, project_table, project_schema, user_id, data_table, reference, datum, file_sum, mime_type, exif_data):
    query = f"""
    INSERT INTO system.files 
    (reference, datum, sum, mimetype, exif, user_id, data_table, access, project_table, project_schema)
    VALUES (%s, %s, %s, %s, %s, %s, %s, 0, '{project_table}', '{project_schema}') ON CONFLICT (project_table,data_table,reference) DO NOTHING;
    """
    with conn.cursor() as cursor:
        cursor.execute(query, (reference, datum, file_sum, mime_type, exif_data, user_id, data_table))
    conn.commit()

def main():
    parser = argparse.ArgumentParser(description='Process files and insert into PostgreSQL.')
    parser.add_argument('directory', help='Directory containing the files')
    parser.add_argument('project_table', help='Project table name')
    parser.add_argument('project_schema', help='Project schema name')
    parser.add_argument('user_id', type=int, help='User ID')
    parser.add_argument('data_table', help='Data table name')
    parser.add_argument('--dbhost', default='localhost', help='Database host')
    parser.add_argument('--dbport', default='5432', help='Database port')
    parser.add_argument('--dbname', default='your_db', help='Database name')
    parser.add_argument('--dbuser', default='your_user', help='Database user')
    parser.add_argument('--dbpass', default='your_password', help='Database password')
    
    args = parser.parse_args()

    # Connect to PostgreSQL
    conn = psycopg2.connect(
        host=args.dbhost,
        port=args.dbport,
        dbname=args.dbname,
        user=args.dbuser,
        password=args.dbpass
    )
    
    # Get list of files
    files = [f for f in os.listdir(args.directory) if os.path.isfile(os.path.join(args.directory, f))]
    
    # Process files in the directory
    for filename in tqdm(files, desc="Processing files", unit="file"):
        file_path = os.path.join(args.directory, filename)

        # Get file details
        reference = filename
        datum = datetime.now()
        file_sum = calculate_sha1(file_path)
        mime_type, _ = mimetypes.guess_type(file_path)
        exif_data = extract_exif(file_path) if mime_type and mime_type.startswith('image') else None
            
        # Insert data into the database
        insert_into_db(conn, args.project_table, args.project_schema, args.user_id, args.data_table, 
                       reference, datum, file_sum, mime_type, exif_data)

    conn.close()

if __name__ == '__main__':
    main()

# RUN
# python3 read_files.py /path/to/files my_project_table my_project_schema 1 my_data_table --dbuser=myuser --dbpass=mypassword
