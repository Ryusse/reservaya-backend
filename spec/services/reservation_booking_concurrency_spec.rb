require "rails_helper"

RSpec.describe ReservationBooking, "concurrency", type: :model do
  self.use_transactional_tests = false

  let(:day) { Date.current + 1.day }
  let(:space) { Space.create!(name: "Concurrencia", location: "Piso 1", capacity: 1, space_type: :private_space, start_time: "08:00", end_time: "18:00", status: :active) }
  let(:users) { Array.new(2) { |i| User.create!(name: "Concurrente #{i}", email: "concurrente-#{i}-#{SecureRandom.hex(4)}@test.com", password: "Secret123", role: :user) } }

  after do
    Reservation.where(space: space).delete_all
    space.delete
    users.each(&:delete)
  end

  def race(attempts)
    start = Queue.new
    threads = attempts.map do |attributes|
      Thread.new do
        start.pop
        ActiveRecord::Base.connection_pool.with_connection do
          reservation = attributes.fetch(:user).reservations.new
          described_class.new(reservation, attributes.fetch(:attrs)).call
        end
      end
    end
    attempts.size.times { start << :go }
    threads.map(&:value)
  end

  it "lets exactly one of two simultaneous bookings of the same slot succeed" do
    attrs = { space_id: space.id, date: day, start_time: "10:00", end_time: "11:00", seats_reserved: 1 }

    results = race(users.map { |user| { user: user, attrs: attrs } })

    expect(results.count(true)).to eq(1)
    expect(Reservation.confirmed.where(space: space, date: day).count).to eq(1)
  end

  it "keeps a single confirmed booking when one user moves while another books the same slot" do
    existing = users.first.reservations.create!(space: space, date: day, start_time: "13:00", end_time: "14:00", seats_reserved: 1)
    attrs = { space_id: space.id, date: day, start_time: "10:00", end_time: "11:00", seats_reserved: 1 }

    start = Queue.new
    booking = Thread.new do
      start.pop
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.new(users.last.reservations.new, attrs).call
      end
    end
    moving = Thread.new do
      start.pop
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.new(existing, { start_time: "10:00", end_time: "11:00" }).call
      end
    end
    2.times { start << :go }
    results = [ booking.value, moving.value ]

    expect(results.count(true)).to eq(1)
    overlapping = Reservation.confirmed.where(space: space, date: day).where("start_time < ? AND end_time > ?", "11:00", "10:00")
    expect(overlapping.count).to eq(1)
  end
end
