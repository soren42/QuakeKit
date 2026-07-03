#!/bin/sh
set -eu

cat >/dev/null

location="${QUAKEKIT_WEATHER_LOCATION:-Charlotte, NC}"
units="${QUAKEKIT_WEATHER_UNITS:-fahrenheit}"

case "$location" in
  "Raleigh, NC")
    lat="35.7796"
    lon="-78.6382"
    label="Raleigh"
    ;;
  "New York, NY")
    lat="40.7128"
    lon="-74.0060"
    label="New York"
    ;;
  "San Francisco, CA")
    lat="37.7749"
    lon="-122.4194"
    label="San Francisco"
    ;;
  "Custom")
    lat="${QUAKEKIT_WEATHER_LAT:-35.2271}"
    lon="${QUAKEKIT_WEATHER_LON:--80.8431}"
    label="${QUAKEKIT_WEATHER_LABEL:-Custom}"
    ;;
  *)
    lat="35.2271"
    lon="-80.8431"
    label="Charlotte"
    ;;
esac

case "$units" in
  celsius) temp_unit="celsius" ;;
  *) temp_unit="fahrenheit" ;;
esac

url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&temperature_unit=${temp_unit}&wind_speed_unit=mph"

payload="$(curl -fsSL --max-time 1 "$url" 2>/dev/null || true)"
if [ -n "$payload" ]; then
  temp="$(printf '%s' "$payload" | sed -n 's/.*"temperature_2m":\([-0-9.]*\).*/\1/p')"
  humidity="$(printf '%s' "$payload" | sed -n 's/.*"relative_humidity_2m":\([-0-9.]*\).*/\1/p')"
  wind="$(printf '%s' "$payload" | sed -n 's/.*"wind_speed_10m":\([-0-9.]*\).*/\1/p')"
  code="$(printf '%s' "$payload" | sed -n 's/.*"weather_code":\([-0-9.]*\).*/\1/p')"
  if [ -n "$temp" ]; then
    printf '{"location":"%s","temperature":%s,"units":"%s","humidity":%s,"windMph":%s,"weatherCode":%s,"source":"open-meteo"}\n' \
      "$label" "$temp" "$temp_unit" "${humidity:-0}" "${wind:-0}" "${code:-0}"
    exit 0
  fi
fi

printf '{"location":"%s","temperature":72,"units":"%s","humidity":50,"windMph":5,"weatherCode":0,"source":"fallback"}\n' "$label" "$temp_unit"
