#!/bin/sh
set -eu

cat >/dev/null

lat="${QUAKEKIT_WEATHER_LAT:-35.7796}"
lon="${QUAKEKIT_WEATHER_LON:--78.6382}"
label="${QUAKEKIT_WEATHER_LABEL:-Raleigh}"
url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph"

payload="$(curl -fsSL --max-time 1 "$url" 2>/dev/null || true)"
if [ -n "$payload" ]; then
  temp="$(printf '%s' "$payload" | sed -n 's/.*"temperature_2m":\([-0-9.]*\).*/\1/p')"
  humidity="$(printf '%s' "$payload" | sed -n 's/.*"relative_humidity_2m":\([-0-9.]*\).*/\1/p')"
  wind="$(printf '%s' "$payload" | sed -n 's/.*"wind_speed_10m":\([-0-9.]*\).*/\1/p')"
  code="$(printf '%s' "$payload" | sed -n 's/.*"weather_code":\([-0-9.]*\).*/\1/p')"
  if [ -n "$temp" ]; then
    printf '{"location":"%s","temperature":%s,"humidity":%s,"windMph":%s,"weatherCode":%s,"source":"open-meteo"}\n' \
      "$label" "$temp" "${humidity:-0}" "${wind:-0}" "${code:-0}"
    exit 0
  fi
fi

printf '{"location":"%s","temperature":72,"humidity":50,"windMph":5,"weatherCode":0,"source":"fallback"}\n' "$label"
