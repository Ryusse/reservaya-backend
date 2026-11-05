require "rails_helper"

RSpec.describe Reservation, "start time already passed", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:space) { create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00") }
  let(:day) { Date.new(2026, 11, 3) }

  def lima(hour, minute = 0)
    Time.zone.local(2026, 11, 3, hour, minute)
  end

  it "rejects a new reservation whose start time already passed today" do
    travel_to(lima(10, 0)) do
      reservation = build(:reservation, space: space, user: user, date: day, start_time: "09:00", end_time: "10:00")

      expect(reservation).not_to be_valid
      expect(reservation.errors[:base]).to include("No puede reservar un horario que ya comenzó")
    end
  end

  it "rejects a start time that equals the current instant" do
    travel_to(lima(10, 0)) do
      reservation = build(:reservation, space: space, user: user, date: day, start_time: "10:00", end_time: "11:00")

      expect(reservation).not_to be_valid
    end
  end

  it "accepts a start time later today" do
    travel_to(lima(10, 0)) do
      reservation = build(:reservation, space: space, user: user, date: day, start_time: "10:30", end_time: "11:30")

      expect(reservation).to be_valid
    end
  end

  it "rejects moving a future reservation to a start time that already passed" do
    reservation = nil
    travel_to(lima(9, 0)) do
      reservation = create(:reservation, space: space, user: user, date: day, start_time: "11:00", end_time: "12:00")
    end

    travel_to(lima(10, 30)) do
      reservation.start_time = "10:00"
      reservation.end_time = "11:00"

      expect(reservation).not_to be_valid
      expect(reservation.errors[:base]).to include("No puede reservar un horario que ya comenzó")
    end
  end

  it "does not block saving an already started reservation for unrelated changes" do
    reservation = nil
    travel_to(lima(9, 0)) do
      reservation = create(:reservation, space: space, user: user, date: day, start_time: "09:30", end_time: "10:00")
    end

    travel_to(lima(10, 0)) do
      reservation.seats_reserved = 1

      expect(reservation).to be_valid
    end
  end

  it "reports past dates without an attribute prefix" do
    travel_to(lima(10, 0)) do
      reservation = build(:reservation, space: space, user: user, date: day - 1, start_time: "09:00", end_time: "10:00")

      expect(reservation).not_to be_valid
      expect(reservation.errors.full_messages).to include("No puede estar en el pasado")
    end
  end
end
