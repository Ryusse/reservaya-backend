current_month_range = Date.current.beginning_of_month..Date.current.end_of_month
previous_month = Date.current.prev_month
previous_month_range = previous_month.beginning_of_month..previous_month.end_of_month

current_month_reservations = Reservation.confirmed.where(date: current_month_range)
previous_month_reservations = Reservation.confirmed.where(date: previous_month_range)

total_current = current_month_reservations.count
total_previous = previous_month_reservations.count

percentage_change =
  if total_previous.zero?
    total_current.positive? ? 100.0 : 0.0
  else
    (((total_current - total_previous).to_f / total_previous) * 100).round(2)
  end

total_seconds = current_month_reservations.sum do |reservation|
  reservation.end_time.seconds_since_midnight - reservation.start_time.seconds_since_midnight
end

json.role "admin"

json.user do
  json.id @current_user.id
  json.name @current_user.name
  json.email @current_user.email
end

json.metrics do
  json.reservations_this_month total_current
  json.reservations_vs_previous_month_percent percentage_change
  json.available_spaces Space.active.count
  json.total_spaces Space.count
  json.reserved_hours_this_month (total_seconds / 3600.0).round(2)
end