require "rails_helper"

RSpec.describe Reservation, "start-time boundaries", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:space) { create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00") }
  let(:day) { Date.current + 1.day }
  let!(:reservation) do
    create(:reservation, user: user, space: space, date: day, start_time: "10:00", end_time: "11:00")
  end

  def at(hour, minute = 0, second = 0)
    day.in_time_zone.change(hour: hour, min: minute, sec: second)
  end

  it "can be cancelled up to the last second before it starts" do
    travel_to(at(9, 59, 59)) do
      expect(reservation).to be_cancellable
      expect(reservation.cancel).to be(true)
      expect(reservation.reload).to be_cancelled
    end
  end

  it "cannot be cancelled from the exact moment it starts" do
    travel_to(at(10)) do
      expect(reservation).not_to be_cancellable
      expect(reservation.cancel).to be(false)
      expect(reservation.errors[:base]).to include("No se puede cancelar una reserva que ya comenzó")
      expect(reservation.reload).to be_confirmed
    end
  end

  it "can be modified only before it starts" do
    travel_to(at(9, 59, 59)) { expect(reservation).to be_modifiable }
    travel_to(at(10)) { expect(reservation).not_to be_modifiable }
  end

  it "keeps a cancelled reservation cancelled after its start time has passed" do
    travel_to(at(9)) { reservation.cancel }

    travel_to(at(12)) do
      expect(reservation.reload).to be_cancelled
      expect(reservation).not_to be_cancellable
    end
  end
end
