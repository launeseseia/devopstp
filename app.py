import os
import time
from flask import Flask, jsonify, request, Response
import redis
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST


app = Flask(__name__)


REQUEST_COUNT = Counter(
    "http_requests_total",
    "Nombre total de requetes HTTP recues",
    ["method", "endpoint", "status"],
)


REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "Duree de traitement d'une requete HTTP, en secondes",
    ["method", "endpoint"],
)


@app.before_request
def start_timer():
    request._metrics_start = time.perf_counter()


@app.after_request
def record_metrics(response):
    if request.path == "/metrics":
        return response

    endpoint = request.url_rule.rule if request.url_rule else "unmatched"
    duration = time.perf_counter() - getattr(request, "_metrics_start", time.perf_counter())
    status = response.status_code

    REQUEST_COUNT.labels(method=request.method, endpoint=endpoint, status=status).inc()
    REQUEST_DURATION.labels(method=request.method, endpoint=endpoint).observe(duration)

    return response


@app.route("/metrics")
def metrics():
    return Response(
        generate_latest(),
        mimetype=CONTENT_TYPE_LATEST
    )


@app.route("/simulate-error")
def simulate_error():
    return jsonify(
        status="error",
        message="Erreur 500 simulee pour declenchement d'alerte"
    ), 500


COMMIT_SHA = os.environ.get("COMMIT_SHA", "unknown")
DEPLOY_COLOR = os.environ.get("DEPLOY_COLOR", "unknown")


def sanitize_input(value):
    return value.replace("<", "&lt;").replace(">", "&gt;")


def get_redis_client():
    host = os.getenv("REDIS_HOST", "redis")
    port = int(os.getenv("REDIS_PORT", 6379))
    return redis.Redis(host=host, port=port, decode_responses=True)


@app.route("/health")
def health():
    try:
        client = get_redis_client()
        if client.ping():
            return jsonify(status="ok", redis="connected"), 200
        else:
            return jsonify(status="error", error="redis ping failed"), 503
    except Exception as e:
        return jsonify(status="error", error=str(e)), 503


@app.route("/status")
def status():
    return jsonify({
        "status": "ok",
        "service": "projet-devops-groupe-demo",
        "version": "1.0",
        "deploy_color": DEPLOY_COLOR,
        "commit_sha": COMMIT_SHA,
    }), 200


@app.route("/visits")
def visits():
    client = get_redis_client()
    count = client.incr("visits_counter")
    return jsonify(visits=count), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)
