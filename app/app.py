import os
import json
import boto3
import psycopg2
from flask import Flask, jsonify, render_template, request, redirect, url_for, session, flash

app = Flask(__name__)
# WARNING: Use a more secure, randomly generated secret key and store it outside the code.
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "a-very-insecure-default-key")


def get_db_connection():
    """Connects to the database using credentials from AWS Secrets Manager."""
    try:
        secret_name = os.environ.get("DB_SECRET_ARN")
        if not secret_name:
            raise ValueError("DB_SECRET_ARN environment variable not set.")

        session_boto = boto3.session.Session()
        client = session_boto.client(service_name='secretsmanager')
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(get_secret_value_response['SecretString'])

        conn = psycopg2.connect(
            host=secret['host'],
            dbname=secret['dbname'],
            user=secret['username'],
            password=secret['password'],
            port=secret.get('port', 5432)
        )
        return conn
    except Exception as e:
        print(f"Database connection failed: {e}")
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

        with conn.cursor() as cur:
            # WARNING: This is vulnerable to SQL injection and stores passwords in plaintext.
            # In a real app, use parameterized queries and hash passwords.
            cur.execute("SELECT id, customer_id FROM users WHERE username = %s AND password = %s", (username, password))
            user = cur.fetchone()

        conn.close()
        if user:
            session["user_id"] = user[0]
            session["customer_id"] = user[1]
            return redirect(url_for("dashboard"))
        else:
            flash("Invalid username or password.", "error")

    return render_template("login.html")


@app.route("/dashboard")
def dashboard():
    if "user_id" not in session:
        return redirect(url_for("login"))

    conn = get_db_connection()
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
    return jsonify({"status": "ok"})


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)
