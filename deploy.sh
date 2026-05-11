#!/bin/bash

echo "Building Flutter Web application for production..."
flutter build web --dart-define=BACKEND_URL=https://smartdukan-voice-billing-production.up.railway.app
