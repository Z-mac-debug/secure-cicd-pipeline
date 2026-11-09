"""Minimal Flask API used as the workload for the DevSecOps pipeline.

The app is deliberately small: the point of this repository is the pipeline
around it. It still follows the basics the scanners look for: strict input
validation, no debug mode, no secrets in code and hardened response headers.
"""

import os
import re

from flask import Flask, jsonify, request

APP_VERSION = os.environ.get("APP_VERSION", "dev")
NAME_PATTERN = re.compile(r"^[A-Za-z][A-Za-z \-']{0,49}$")

SECURITY_HEADERS = {
    "Content-Security-Policy": (
        "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    ),
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Permissions-Policy": "geolocation=(), camera=(), microphone=(), payment=()",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    "Cross-Origin-Resource-Policy": "same-origin",
    "Cache-Control": "no-store",
    "Pragma": "no-cache",
}


def create_app() -> Flask:
    app = Flask(__name__)
    app.config.update(MAX_CONTENT_LENGTH=16 * 1024)  # reject oversized request bodies

    @app.after_request
    def add_security_headers(response):
        for header, value in SECURITY_HEADERS.items():
            response.headers.setdefault(header, value)
        response.headers.pop("Server", None)
        return response

    @app.get("/")
    def index():
        return jsonify(service="secure-cicd-pipeline", version=APP_VERSION)

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/api/greet")
    def greet():
        name = request.args.get("name", "").strip()
        if not NAME_PATTERN.fullmatch(name):
            return jsonify(error="name must be 1-50 letters, spaces, hyphens or apostrophes"), 400
        return jsonify(message=f"Hello, {name}!")

    @app.errorhandler(404)
    def not_found(_error):
        return jsonify(error="not found"), 404

    @app.errorhandler(405)
    def method_not_allowed(_error):
        return jsonify(error="method not allowed"), 405

    return app


app = create_app()
