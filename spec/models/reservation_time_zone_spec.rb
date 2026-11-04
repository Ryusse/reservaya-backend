require "rails_helper"

RSpec.describe "Application time zone", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:space) { create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "23:00") }

  it "uses Bogota as the application time zone" do
    expect(Time.zone.name).to eq("Bogota")
  end

  it "counts the current day in Bogota, not in UTC" do
    travel_to(Time.utc(2026, 11, 4, 3, 0)) do
      expect(Date.current).to eq(Date.new(2026, 11, 3))
    end
  end

  it "stores time-of-day columns as wall-clock values, without shifting them to UTC" do
    reservation = create(:reservation, space: space, date: Date.current + 1.day, start_time: "10:00", end_time: "12:00")

    raw = ActiveRecord::Base.connection.select_one("SELECT start_time, end_time FROM reservations WHERE id = #{reservation.id}")

    expect(raw).to eq("start_time" => "10:00:00", "end_time" => "12:00:00")
  end

  it "considers a reservation started at its Bogota wall-clock start time" do
    travel_to(Time.utc(2026, 11, 4, 3, 0)) do
      reservation = build(:reservation, space: space, date: Date.new(2026, 11, 3), start_time: "21:00", end_time: "22:00")

      expect(reservation).to be_started
    end
  end

  it "does not consider a reservation started before its Bogota start time" do
    travel_to(Time.utc(2026, 11, 4, 3, 0)) do
      reservation = build(:reservation, space: space, date: Date.new(2026, 11, 3), start_time: "23:00", end_time: "23:30")

      expect(reservation).not_to be_started
    end
  end
end
