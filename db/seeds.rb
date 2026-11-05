# Usuarios
admin = User.find_or_create_by!(email: "admin@reservaya.local") do |user|
  user.name = "Admin"
  user.password = "Password123"
  user.role = :admin
end
admin.update!(role: :admin) unless admin.admin?

user1 = User.find_or_create_by!(email: "usuario1@reservaya.local") do |user|
  user.name = "Usuario Uno"
  user.password = "Password123"
  user.role = :user
end

user2 = User.find_or_create_by!(email: "usuario2@reservaya.local") do |user|
  user.name = "Usuario Dos"
  user.password = "Password123"
  user.role = :user
end

user3 = User.find_or_create_by!(email: "usuario3@reservaya.local") do |user|
  user.name = "Usuario Tres"
  user.password = "Password123"
  user.role = :user
end

# Espacios
private_space = Space.find_or_create_by!(name: "Sala Privada Demo") do |space|
  space.capacity = 4
  space.location = "Piso 1"
  space.start_time = "08:00"
  space.end_time = "18:00"
  space.status = :active
  space.space_type = :private_space
end

shared_space = Space.find_or_create_by!(name: "Sala Compartida Demo") do |space|
  space.capacity = 10
  space.location = "Piso 2"
  space.start_time = "08:00"
  space.end_time = "18:00"
  space.status = :active
  space.space_type = :shared_space
end

Space.find_or_create_by!(name: "Sala Inactiva Demo") do |space|
  space.capacity = 6
  space.location = "Piso 3"
  space.start_time = "08:00"
  space.end_time = "18:00"
  space.status = :inactive
  space.space_type = :shared_space
end

# Reservas de prueba para mañana (las de hoy ya pueden haber comenzado)
seed_day = Date.current + 1.day

# Bloquear la sala privada de 10:00 a 12:00
Reservation.find_or_create_by!(space: private_space, date: seed_day, start_time: "10:00", end_time: "12:00", user: user1) do |r|
  r.seats_reserved = 4
  r.status = :confirmed
end

# Uso parcial de la sala compartida de 09:00 a 11:00 (4 asientos)
Reservation.find_or_create_by!(space: shared_space, date: seed_day, start_time: "09:00", end_time: "11:00", user: user2) do |r|
  r.seats_reserved = 4
  r.status = :confirmed
end

# Uso parcial de la sala compartida de 10:00 a 13:00 (5 asientos)
# En el lapso de 10:00 a 11:00 estarán ocupados 4 + 5 = 9 asientos (quedará 1 libre)
Reservation.find_or_create_by!(space: shared_space, date: seed_day, start_time: "10:00", end_time: "13:00", user: user3) do |r|
  r.seats_reserved = 5
  r.status = :confirmed
end
