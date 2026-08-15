#!/bin/dash

# Next prayer/event for the Mac's current timezone, calculated offline with the
# Muslim World League method. Coordinates come from the system timezone database.
system_timezone()
{
    if [ -n "${PRAYER_TIMEZONE-}" ]; then
        printf '%s\n' "$PRAYER_TIMEZONE"
        return
    fi

    timezone_path=$(readlink /etc/localtime) || return 1
    case $timezone_path in
        */zoneinfo/*) printf '%s\n' "${timezone_path##*/zoneinfo/}" ;;
        *) return 1 ;;
    esac
}

system_coordinates()
{
    selected_timezone=$1
    for zone_file in \
        /var/db/timezone/zoneinfo/zone.tab \
        /usr/share/zoneinfo/zone.tab
    do
        [ -r "$zone_file" ] && break
    done
    [ -r "$zone_file" ] || return 1

    awk -F '	' -v timezone="$selected_timezone" '
        $3 == timezone {
            coordinates = $2
            latitude_sign = substr(coordinates, 1, 1) == "-" ? -1 : 1
            remainder = substr(coordinates, 2)
            match(remainder, /[+-]/)
            latitude_digits = substr(remainder, 1, RSTART - 1)
            longitude_sign = substr(remainder, RSTART, 1) == "-" ? -1 : 1
            longitude_digits = substr(remainder, RSTART + 1)
            latitude = latitude_sign * decimal_coordinate(latitude_digits)
            longitude = longitude_sign * decimal_coordinate(longitude_digits)
            printf "%.6f %.6f\n", latitude, longitude
            found = 1
            exit
        }

        function decimal_coordinate(digits, degree_length, degrees,
                                    minutes, seconds) {
            if (length(digits) <= 5) {
                degree_length = length(digits) - 2
                degrees = substr(digits, 1, degree_length)
                minutes = substr(digits, degree_length + 1, 2)
                seconds = 0
            } else {
                degree_length = length(digits) - 4
                degrees = substr(digits, 1, degree_length)
                minutes = substr(digits, degree_length + 1, 2)
                seconds = substr(digits, degree_length + 3, 2)
            }
            return degrees + minutes / 60 + seconds / 3600
        }

        END {
            if (!found)
                exit 1
        }
    ' "$zone_file"
}

selected_timezone=$(system_timezone) || exit 1
export TZ=$selected_timezone
coordinates=$(system_coordinates "$selected_timezone") || exit 1
set -- $coordinates
latitude=$1
longitude=$2

prayer_minutes()
{
    prayer_day=$1
    zone=$(
        date -j -f '%Y-%m-%d %H:%M:%S' \
            "$prayer_day 12:00:00" '+%z'
    ) || return 1

    awk -v day="$prayer_day" -v zone="$zone" \
        -v latitude="$latitude" -v longitude="$longitude" '
        BEGIN {
            pi = atan2(0, -1)

            split(day, date_parts, "-")
            year = date_parts[1] + 0
            month = date_parts[2] + 0
            day_of_month = date_parts[3] + 0

            sign = substr(zone, 1, 1) == "-" ? -1 : 1
            zone_hours = substr(zone, 2, 2) + 0
            zone_minutes = substr(zone, 4, 2) + 0
            utc_offset = sign * (zone_hours + zone_minutes / 60)

            julian = julian_day(year, month, day_of_month)
            julian -= longitude / (15 * 24)

            hours["Fajr"] = 5
            hours["Sunrise"] = 6
            hours["Dhuhr"] = 12
            hours["Asr"] = 13
            hours["Maghrib"] = 18
            hours["Isha"] = 18

            for (iteration = 0; iteration < 2; iteration++) {
                for (name in hours)
                    scaled[name] = hours[name] / 24

                hours["Fajr"] = angle_time(18, scaled["Fajr"], 0)
                hours["Sunrise"] = angle_time(0.833, scaled["Sunrise"], 0)
                hours["Dhuhr"] = midday(scaled["Dhuhr"])
                hours["Asr"] = asr_time(scaled["Asr"])
                hours["Maghrib"] = angle_time(0.833, scaled["Maghrib"], 1)
                hours["Isha"] = angle_time(17, scaled["Isha"], 1)
            }

            adjustment = utc_offset - longitude / 15
            print_prayer("Fajr", adjustment)
            print_prayer("Sunrise", adjustment)
            print_prayer("Dhuhr", adjustment)
            print_prayer("Asr", adjustment)
            print_prayer("Maghrib", adjustment)
            print_prayer("Isha", adjustment)
        }

        function degrees_sin(value) {
            return sin(value * pi / 180)
        }

        function degrees_cos(value) {
            return cos(value * pi / 180)
        }

        function degrees_tan(value) {
            return sin(value * pi / 180) / cos(value * pi / 180)
        }

        function degrees_asin(value) {
            return atan2(value, sqrt(1 - value * value)) * 180 / pi
        }

        function degrees_acos(value) {
            if (value > 1)
                value = 1
            if (value < -1)
                value = -1
            return atan2(sqrt(1 - value * value), value) * 180 / pi
        }

        function degrees_acot(value) {
            return atan2(1, value) * 180 / pi
        }

        function fix_angle(value) {
            value %= 360
            return value < 0 ? value + 360 : value
        }

        function fix_hour(value) {
            value %= 24
            return value < 0 ? value + 24 : value
        }

        function julian_day(y, m, d, century, correction, value) {
            if (m <= 2) {
                y--
                m += 12
            }
            century = int(y / 100)
            correction = 2 - century + int(century / 4)
            value = int(365.25 * (y + 4716))
            value += int(30.6001 * (m + 1))
            return value + d + correction - 1524.5
        }

        function sun_position(value, result, days, anomaly, sun_longitude,
                              obliquity, right_ascension, equation, declination) {
            days = value - 2451545
            anomaly = fix_angle(357.529 + 0.98560028 * days)
            sun_longitude = 280.459 + 0.98564736 * days
            sun_longitude += 1.915 * degrees_sin(anomaly)
            sun_longitude += 0.020 * degrees_sin(2 * anomaly)
            sun_longitude = fix_angle(sun_longitude)
            obliquity = 23.439 - 0.00000036 * days
            right_y = degrees_cos(obliquity) * degrees_sin(sun_longitude)
            right_x = degrees_cos(sun_longitude)
            right_ascension = atan2(right_y, right_x) * 180 / pi / 15
            right_ascension = fix_hour(right_ascension)
            equation = (280.459 + 0.98564736 * days) / 15 - right_ascension
            declination = degrees_sin(obliquity)
            declination *= degrees_sin(sun_longitude)
            declination = degrees_asin(declination)
            result["equation"] = equation
            result["declination"] = declination
        }

        function midday(hour, position) {
            sun_position(julian + hour / 24, position)
            return fix_hour(12 - position["equation"])
        }

        function angle_time(angle, hour, after_midday, position,
                            declination, noon, cosine, delta) {
            sun_position(julian + hour / 24, position)
            declination = position["declination"]
            noon = midday(hour)
            cosine = -degrees_sin(angle)
            cosine -= degrees_sin(declination) * degrees_sin(latitude)
            cosine /= degrees_cos(declination) * degrees_cos(latitude)
            delta = degrees_acos(cosine) / 15
            return after_midday ? noon + delta : noon - delta
        }

        function asr_time(hour, position, declination, angle) {
            sun_position(julian + hour / 24, position)
            declination = position["declination"]
            angle = degrees_acot(1 + degrees_tan(abs(latitude - declination)))
            return angle_time(-angle, hour, 1)
        }

        function abs(value) {
            return value < 0 ? -value : value
        }

        function print_prayer(name, adjustment, hour, minutes) {
            hour = fix_hour(hours[name] + adjustment)
            minutes = int(hour * 60 + 0.5)
            print name, minutes
        }
    '
}

print_upcoming()
{
    prayer_minute=$1
    printf '%02d:%02d\n' \
        "$((prayer_minute / 60))" "$((prayer_minute % 60))"
}

today=$(date '+%Y-%m-%d')
tomorrow=$(date -v+1d '+%Y-%m-%d')
current_hour=$(date '+%H')
current_minute=$(date '+%M')
current_hour=$((1$current_hour - 100))
current_minute=$((1$current_minute - 100))
current_minutes=$((current_hour * 60 + current_minute))

schedule=$(prayer_minutes "$today") || exit 1
while read -r prayer minutes
do
    if [ "$minutes" -gt "$current_minutes" ]; then
        print_upcoming "$minutes"
        exit
    fi
done <<EOF
$schedule
EOF

schedule=$(prayer_minutes "$tomorrow") || exit 1
set -- $schedule
minutes=$2
print_upcoming "$minutes"
