import os
import json
import boto3
import psycopg2
import time # Import time for sleep
from flask import Flask, jsonify, render_template, request, redirect, url_for, session, flash
from prometheus_client import make_wsgi_app
from werkzeug.middleware.dispatcher import DispatcherMiddleware

app = Flask(__name__)
# WARNING: Use a more secure, randomly generated secret key and store it outside the code.
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "a-very-insecure-default-key")

# Add prometheus wsgi middleware to route /metrics requests
app.wsgi_app = DispatcherMiddleware(app.wsgi_app, {
    '/metrics': make_wsgi_app()
})


def get_db_connection():
    """Connects to the database using credentials from AWS Secrets Manager."""
    max_retries = 5
    retry_delay_seconds = 5
    
    secret_name = os.environ.get("DB_SECRET_ARN")
    if not secret_name:
        print("ERROR: DB_SECRET_ARN environment variable not set.")
        return None

    for i in range(max_retries):
        try:
            session_boto = boto3.session.Session()
            client = session_boto.client(service_name='secretsmanager')
            get_secret_value_response = client.get_secret_value(SecretId=secret_name)
            secret = json.loads(get_secret_value_response['SecretString'])

            conn = psycopg2.connect(
                host=secret['host'],
                dbname=secret['dbname'],
                user=secret['username'],
                password=secret['password'],
                port=secret.get('port', 5432),
                connect_timeout=5 # Add a connection timeout
            )
            print("Successfully connected to the database.")
            return conn
        except Exception as e:
            print(f"Database connection attempt {i+1}/{max_retries} failed: {e}")
            if i < max_retries - 1:
                print(f"Retrying in {retry_delay_seconds} seconds...")
                time.sleep(retry_delay_seconds)
            else:
                print("Max database connection retries reached. Giving up.")
                return None


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"]
        password = request.form["password"]
        conn = get_db_connection()
        if not conn:
            flash("Could not connect to the database.", "error")
            return render_template("login.html")

        with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
            # The query is parameterized, which prevents SQL injection.
            # WARNING: This still checks a plaintext password. In a real app, use hashed passwords.
            cur.execute("SELECT id, customer_id FROM users WHERE username = %s AND password = %s", (username, password))
            user = cur.fetchone()

        conn.close()
        if user:
            session["user_id"] = user["id"]
            session["customer_id"] = user["customer_id"]
            return redirect(url_for("dashboard"))
        else:
            flash("Invalid username or password.", "error")

    return render_template("login.html")


@app.route("/dashboard")
def dashboard():
    if "user_id" not in session:
        return redirect(url_for("login"))

    conn = get_db_connection()
    if not conn:
        flash("Could not connect to the database to load dashboard.", "error")
        # Clear the potentially invalid session and redirect to login
        session.clear()
        return redirect(url_for("login"))

    with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute("SELECT * FROM customers WHERE id = %s", (session["customer_id"],))
        customer = cur.fetchone()
        cur.execute("SELECT * FROM accounts WHERE customer_id = %s", (session["customer_id"],))
        accounts = cur.fetchall()
    conn.close()
    return render_template("dashboard.html", customer=customer, accounts=accounts)


@app.get("/")
def index():
    if "user_id" in session:
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))


@app.get("/health")
def health():
    """Performs a health check on the application and its dependencies."""
    try:
        conn = get_db_connection()
        if conn:
            # Perform a simple, fast query to check the connection is alive
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
            conn.close()
            return jsonify({"status": "ok", "database": "connected"})
        else:
            # The get_db_connection function returned None
            return jsonify({"status": "unhealthy", "reason": "Database connection could not be established after retries"}), 503
    except Exception as e:
        # Any other exception during the check (e.g., failed query)
        return jsonify({"status": "unhealthy", "reason": f"Database check failed: {e}"}), 503

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))
