import os
import redis
from flask import Flask, jsonify

app = Flask(__name__)

ALERT_THRESHOLD = 25


def alert_threshold():
    """Seuil d'alerte au-dessus duquel une notification est declenchee."""
    return ALERT_THRESHOLD


def sanitize_input(value):
    """Echappe les caracteres dangereux d'une entree utilisateur."""
    return value.replace("<", "&lt;").replace(">", "&gt;")


def get_redis_client():
    """Cree et retourne un client Redis connecte au service 'redis'."""
    host = os.getenv("REDIS_HOST", "redis")
    port = int(os.getenv("REDIS_PORT", 6379))
    return redis.Redis(host=host, port=port, decode_responses=True)


@app.route("/health")
def health():
    try:
        client = get_redis_client()
        # Test actif de la dependance critique
        if client.ping():
            return jsonify(status="ok", redis="connected"), 200
        else:
            return jsonify(status="error", error="redis ping failed"), 503
    except Exception as e:
        return jsonify(status="error", error=str(e)), 503


@app.route("/status")
def status():
    return jsonify(service="projet-devops-groupe-demo", version="1.0"), 200


@app.route("/visits")
def visits():
    client = get_redis_client()
    count = client.incr("visits_counter")
    return jsonify(visits=count), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)
