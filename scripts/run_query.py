#!/usr/bin/env python3
import os
import sys
import json
import time
import boto3
import psycopg2
from psycopg2.extras import DictCursor

def run_query(secret_arn, query):
    """Connects to the database and executes a given SQL query."""
    try:
        print(f"Fetching database credentials from Secrets Manager using ARN: {secret_arn}")
        session = boto3.session.Session()
        # Explicitly set region from environment if available, for robustness
        client = session.client(
            service_name='secretsmanager',
            region_name=os.environ.get('AWS_REGION')
        )
        get_secret_value_response = client.get_secret_value(SecretId=secret_arn)
        secret = json.loads(get_secret_value_response['SecretString'])
        print("Successfully fetched credentials.")

        conn = None
        for i in range(5): # Retry for up to 50 seconds
            try:
                print(f"Connecting to database host: {secret['host']} (Attempt {i+1}/5)")
                conn = psycopg2.connect(
                    host=secret['host'],
                    dbname=secret['dbname'],
                    user=secret['username'],
                    password=secret['password'],
                    port=secret.get('port', 5432),
                    connect_timeout=10
                )
                break # Exit loop on success
            except psycopg2.OperationalError as e:
                print(f"Connection attempt failed: {e}. Retrying in 10 seconds...")
                time.sleep(10)

        if not conn:
            print("ERROR: Could not connect to the database after multiple retries.", file=sys.stderr)
            sys.exit(1)

        with conn.cursor(cursor_factory=DictCursor) as cur:
            print(f"\nExecuting query: {query}\n")
            cur.execute(query)

            if cur.description:
                rows = cur.fetchall()
                if not rows:
                    print("Query executed successfully, but returned no rows.")
                    return

                colnames = [desc[0] for desc in cur.description]
                col_widths = {col: len(col) for col in colnames}
                for row in rows:
                    for col in colnames:
                        col_widths[col] = max(col_widths[col], len(str(row[col])))

                header = " | ".join(f"{col.ljust(col_widths[col])}" for col in colnames)
                print(header)
                print("-" * len(header))

                for row in rows:
                    print(" | ".join(f"{str(row[col]).ljust(col_widths[col])}" for col in colnames))
            else:
                print(f"Query executed successfully. {cur.rowcount} rows affected.")

        conn.close()
        print("\nQuery execution complete.")

    except Exception as e:
        print(f"ERROR: Query execution failed: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python run_query.py <DB_SECRET_ARN> \"<SQL_QUERY>\"", file=sys.stderr)
        sys.exit(1)

    run_query(sys.argv[1], sys.argv[2])