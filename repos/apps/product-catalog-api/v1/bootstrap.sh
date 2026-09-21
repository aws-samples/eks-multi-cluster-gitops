#!/bin/sh
export FLASK_APP=./app.py
exec gunicorn --bind 0.0.0.0:8080 app:flask_app
