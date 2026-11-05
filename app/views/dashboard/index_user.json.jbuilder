current_month_range = Date.current.beginning_of_month..Date.current.end_of_month
my_confirmed_reservations = @current_user.reservations.confirmed
my_current_month_reservations = my_confirmed_reservations.where(date: current_month_range)

total_seconds = my_current_month_reservations.sum do |reservation|
  reservation.end_time.seconds_since_midnight - reservation.start_time.seconds_since_midnight
end

json.role "user"

json.user do
  json.id @current_user.id
  json.name @current_user.name
  json.email @current_user.email
end

json.metrics do
  json.my_active_reservations my_confirmed_reservations.where("date >= ?", Date.current).count
  json.available_spaces Space.active.count
  json.total_spaces Space.count
  json.reserved_hours_this_month (total_seconds / 3600.0).round(2)
end