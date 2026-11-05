json.id reservation.id
json.date reservation.date
json.start_time reservation.start_time&.strftime("%H:%M")
json.end_time reservation.end_time&.strftime("%H:%M")
json.status reservation.status
json.seats_reserved reservation.seats_reserved
json.cancellable reservation.cancellable?

json.space do
  json.id reservation.space.id
  json.name reservation.space.name
  json.location reservation.space.location
  json.space_type reservation.space.space_type
  json.status reservation.space.status
end

json.user do
  json.id reservation.user.id
  json.name reservation.user.name
  json.email reservation.user.email
end