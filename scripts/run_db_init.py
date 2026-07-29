#!/usr/bin/env python3
import os
import sys
import json
import boto3
import psycopg2

def initialize_database(secret_arn, sql_file_path):
    """Connects to the database and executes the initialization SQL script."""
    try:
        print(f"Fetching database credentials from Secrets Manager using ARN: {secret_arn}")
        session = boto3.session.Session()
        client = session.client(service_name='secretsmanager')
        get_secret_value_response = client.get_secret_value(SecretId=secret_arn)
        secret = json.loads(get_secret_value_response['SecretString'])
        print("Successfully fetched credentials.")

        print(f"Connecting to database host: {secret['host']}")
        conn = psycopg2.connect(
            host=secret['host'],
            dbname=secret['dbname'],
            user=secret['username'],
            password=secret['password'],
            port=secret.get('port', 5432),
            connect_timeout=10
        )
        print("Database connection successful.")

        with conn.cursor() as cur:
            print(f"Reading and executing SQL script from: {sql_file_path}")
            with open(sql_file_path, 'r') as f:
                cur.execute(f.read())
            print("SQL script executed successfully.")

        conn.commit()
        conn.close()
        print("Database initialization complete.")

    except Exception as e:
        print(f"ERROR: Database initialization failed: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python run_db_init.py <DB_SECRET_ARN> <PATH_TO_SQL_FILE>", file=sys.stderr)
        sys.exit(1)
    
    initialize_database(sys.argv[1], sys.argv[2])