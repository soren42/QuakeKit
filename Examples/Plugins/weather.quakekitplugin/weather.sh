#!/bin/sh
set -eu

cat >/dev/null

layout="${QUAKEKIT_WEATHER_LAYOUT:-single_fullscreen}"
primary="${QUAKEKIT_WEATHER_PRIMARY_LOCATION:-${QUAKEKIT_WEATHER_LOCATION:-Charlotte, NC}}"
secondary="${QUAKEKIT_WEATHER_SECONDARY_LOCATION:-Raleigh, NC}"
location_set="${QUAKEKIT_WEATHER_LOCATION_SET:-carolinas}"
units="${QUAKEKIT_WEATHER_UNITS:-fahrenheit}"
forecast_days="${QUAKEKIT_WEATHER_FORECAST_DAYS:-5}"
show_radar="${QUAKEKIT_WEATHER_SHOW_RADAR:-true}"

case "$forecast_days" in
  3) forecast_days=3 ;;
  *) forecast_days=5 ;;
esac

case "$units" in
  celsius) temp_unit="celsius"; unit_symbol="C" ;;
  *) temp_unit="fahrenheit"; unit_symbol="F" ;;
esac

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

location_parts() {
  case "$1" in
    "Raleigh, NC") printf 'Raleigh|35.7796|-78.6382|Heat Advisory' ;;
    "New York, NY") printf 'New York|40.7128|-74.0060|Air Quality Moderate' ;;
    "San Francisco, CA") printf 'San Francisco|37.7749|-122.4194|Marine Layer' ;;
    "Custom") printf '%s|%s|%s|Custom Forecast' "${QUAKEKIT_WEATHER_LABEL:-Custom}" "${QUAKEKIT_WEATHER_LAT:-35.2271}" "${QUAKEKIT_WEATHER_LON:--80.8431}" ;;
    *) printf 'Charlotte|35.2271|-80.8431|Heat Advisory' ;;
  esac
}

locations_for_layout() {
  case "$layout" in
    two_location_halves)
      printf '%s\n%s\n' "$primary" "$secondary"
      ;;
    multi_location_widgets)
      case "$location_set" in
        travel) printf 'Charlotte, NC\nNew York, NY\nSan Francisco, CA\nRaleigh, NC\n' ;;
        coasts) printf 'New York, NY\nSan Francisco, CA\nCharlotte, NC\nRaleigh, NC\n' ;;
        custom) printf '%s\n%s\n' "$primary" "$secondary" ;;
        *) printf 'Charlotte, NC\nRaleigh, NC\nNew York, NY\nSan Francisco, CA\n' ;;
      esac
      ;;
    *)
      printf '%s\n' "$primary"
      ;;
  esac
}

condition_for_code() {
  code="$1"
  case "$code" in
    0) printf 'Clear' ;;
    1|2) printf 'Mostly Clear' ;;
    3) printf 'Mostly Cloudy' ;;
    45|48) printf 'Fog' ;;
    51|53|55|56|57) printf 'Drizzle' ;;
    61|63|65|66|67|80|81|82) printf 'Rain' ;;
    71|73|75|77|85|86) printf 'Snow' ;;
    95|96|99) printf 'Thunderstorms' ;;
    *) printf 'Cloudy' ;;
  esac
}

icon_for_code() {
  code="$1"
  case "$code" in
    0) printf 'sun.max.fill' ;;
    1|2) printf 'cloud.sun.fill' ;;
    3) printf 'cloud.fill' ;;
    45|48) printf 'cloud.fog.fill' ;;
    51|53|55|56|57) printf 'cloud.drizzle.fill' ;;
    61|63|65|66|67|80|81|82) printf 'cloud.rain.fill' ;;
    71|73|75|77|85|86) printf 'cloud.snow.fill' ;;
    95|96|99) printf 'cloud.bolt.rain.fill' ;;
    *) printf 'cloud.fill' ;;
  esac
}

emit_fallback_location() {
  raw="$1"
  parts="$(location_parts "$raw")"
  label="$(printf '%s' "$parts" | awk -F'|' '{print $1}')"
  lat="$(printf '%s' "$parts" | awk -F'|' '{print $2}')"
  lon="$(printf '%s' "$parts" | awk -F'|' '{print $3}')"
  alert="$(printf '%s' "$parts" | awk -F'|' '{print $4}')"
  base=81
  case "$label" in
    Raleigh) base=83 ;;
    "New York") base=76 ;;
    "San Francisco") base=62 ;;
  esac
  high=$((base + 14))
  low=$((base - 5))
  days='{"day":"Sun","icon":"cloud.bolt.rain.fill","condition":"Storms","low":76,"high":95},{"day":"Mon","icon":"cloud.bolt.rain.fill","condition":"Storms","low":75,"high":93},{"day":"Tue","icon":"cloud.rain.fill","condition":"Rain","low":74,"high":91},{"day":"Wed","icon":"cloud.sun.fill","condition":"Partly Cloudy","low":74,"high":87},{"day":"Thu","icon":"sun.max.fill","condition":"Clear","low":72,"high":88}'
  hourly='{"time":"03","icon":"cloud.moon.fill","temperature":78},{"time":"04","icon":"cloud.fill","temperature":77},{"time":"05","icon":"cloud.fill","temperature":76},{"time":"06","icon":"cloud.fill","temperature":76},{"time":"06:13","icon":"sunrise.fill","temperature":77},{"time":"07","icon":"cloud.fill","temperature":77}'
  printf '{"name":"%s","latitude":%s,"longitude":%s,"temperature":%s,"high":%s,"low":%s,"condition":"Mostly Cloudy","icon":"cloud.fill","alert":"%s","humidity":64,"windMph":7,"radarURL":"https://open-meteo.com/","hourly":[%s],"daily":[%s]}' \
    "$(json_escape "$label")" "$lat" "$lon" "$base" "$high" "$low" "$(json_escape "$alert")" "$hourly" "$days"
}

emit_location() {
  raw="$1"
  parts="$(location_parts "$raw")"
  label="$(printf '%s' "$parts" | awk -F'|' '{print $1}')"
  lat="$(printf '%s' "$parts" | awk -F'|' '{print $2}')"
  lon="$(printf '%s' "$parts" | awk -F'|' '{print $3}')"
  alert="$(printf '%s' "$parts" | awk -F'|' '{print $4}')"
  url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&hourly=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=5&temperature_unit=${temp_unit}&wind_speed_unit=mph&timezone=auto"
  payload="$(curl -fsSL --max-time 2 "$url" 2>/dev/null || true)"
  if [ -z "$payload" ]; then
    emit_fallback_location "$raw"
    return
  fi

  temp="$(printf '%s' "$payload" | sed -n 's/.*"temperature_2m":\([-0-9.]*\).*/\1/p' | head -n 1)"
  humidity="$(printf '%s' "$payload" | sed -n 's/.*"relative_humidity_2m":\([-0-9.]*\).*/\1/p' | head -n 1)"
  wind="$(printf '%s' "$payload" | sed -n 's/.*"wind_speed_10m":\([-0-9.]*\).*/\1/p' | head -n 1)"
  code="$(printf '%s' "$payload" | sed -n 's/.*"weather_code":\([-0-9.]*\).*/\1/p' | head -n 1)"
  if [ -z "$temp" ]; then
    emit_fallback_location "$raw"
    return
  fi

  daily_max="$(printf '%s' "$payload" | sed -n 's/.*"temperature_2m_max":\[\([^]]*\)\].*/\1/p' | head -n 1)"
  daily_min="$(printf '%s' "$payload" | sed -n 's/.*"temperature_2m_min":\[\([^]]*\)\].*/\1/p' | head -n 1)"
  daily_codes="$(printf '%s' "$payload" | sed -n 's/.*"daily":.*"weather_code":\[\([^]]*\)\].*/\1/p' | head -n 1)"

  daily=''
  i=1
  while [ "$i" -le "$forecast_days" ]; do
    day_name="$(date -v+"$((i - 1))"d +%a 2>/dev/null || printf 'Day %s' "$i")"
    high="$(printf '%s' "$daily_max" | awk -F, -v i="$i" '{print int($i + 0.5)}')"
    low="$(printf '%s' "$daily_min" | awk -F, -v i="$i" '{print int($i + 0.5)}')"
    day_code="$(printf '%s' "$daily_codes" | awk -F, -v i="$i" '{gsub(/[^0-9-]/,"",$i); print $i + 0}')"
    day_condition="$(condition_for_code "$day_code")"
    day_icon="$(icon_for_code "$day_code")"
    daily="${daily}${daily:+,}{\"day\":\"$(json_escape "$day_name")\",\"icon\":\"$day_icon\",\"condition\":\"$(json_escape "$day_condition")\",\"low\":${low:-0},\"high\":${high:-0}}"
    i=$((i + 1))
  done

  rounded_temp="$(awk -v value="${temp:-0}" 'BEGIN { printf "%.0f", value }')"
  high_today="$(printf '%s' "$daily_max" | awk -F, '{print int($1 + 0.5)}')"
  low_today="$(printf '%s' "$daily_min" | awk -F, '{print int($1 + 0.5)}')"
  condition="$(condition_for_code "${code:-3}")"
  icon="$(icon_for_code "${code:-3}")"
  hourly='{"time":"03","icon":"cloud.moon.fill","temperature":78},{"time":"04","icon":"cloud.fill","temperature":77},{"time":"05","icon":"cloud.fill","temperature":76},{"time":"06","icon":"cloud.fill","temperature":76},{"time":"06:13","icon":"sunrise.fill","temperature":77},{"time":"07","icon":"cloud.fill","temperature":77}'
  printf '{"name":"%s","latitude":%s,"longitude":%s,"temperature":%s,"high":%s,"low":%s,"condition":"%s","icon":"%s","alert":"%s","humidity":%s,"windMph":%s,"radarURL":"https://open-meteo.com/","hourly":[%s],"daily":[%s]}' \
    "$(json_escape "$label")" "$lat" "$lon" "$rounded_temp" "${high_today:-0}" "${low_today:-0}" "$(json_escape "$condition")" "$icon" "$(json_escape "$alert")" "${humidity:-0}" "${wind:-0}" "$hourly" "$daily"
}

locations_json=''
while IFS= read -r location_name; do
  [ -n "$location_name" ] || continue
  locations_json="${locations_json}${locations_json:+,}$(emit_location "$location_name")"
done <<EOF_LOCATIONS
$(locations_for_layout)
EOF_LOCATIONS

printf '{"layout":"%s","units":"%s","unitSymbol":"%s","forecastDays":%s,"showRadar":%s,"updatedAt":"%s","source":"weather.sh","locations":[%s]}\n' \
  "$(json_escape "$layout")" "$(json_escape "$temp_unit")" "$unit_symbol" "$forecast_days" "$show_radar" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$locations_json"
