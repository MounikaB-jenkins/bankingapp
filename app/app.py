import os
from flask import Flask, jsonify

app = Flask(__name__)


@app.get("/")
def index():
    return jsonify({
        "service": "BankingApp",
        "status": "running",
        "environment": os.getenv("ENVIRONMENT", "dev"),
    })


@app.get("/health")
def health():
    return jsonify({"status": "ok"})


@app.get("/customers")
def customers():
    return jsonify({"customers": []})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
