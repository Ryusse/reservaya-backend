require "rails_helper"

RSpec.describe Space, "availability at a given instant", type: :model do
  let(:space) { create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00") }
  let(:day) { Date.new(2026, 11, 3) }
  let(:now) { Time.zone.local(2026, 11, 3, 10, 30, 15) }

  include ActiveSupport::Testing::TimeHelpers

  it "drops hours that already passed today and starts the current block at the next full minute" do
    blocks = space.availability_blocks(day, now: now)

    expect(blocks).to eq([ { start_time: "10:31", end_time: "18:00", status: "free", seats_available: 1 } ])
  end

  it "returns nothing when the operating window has already closed today" do
    expect(space.availability_blocks(day, now: Time.zone.local(2026, 11, 3, 18, 30))).to eq([])
  end

  it "does not change availability for a future day" do
    blocks = space.availability_blocks(day + 1, now: now)

    expect(blocks.first[:start_time]).to eq("08:00")
  end

  it "shows reserved hours as full while still hiding the past" do
    travel_to(now) { create(:reservation, space: space, user: create(:user), date: day, start_time: "12:00", end_time: "13:00") }

    blocks = space.availability_blocks(day, now: now)

    expect(blocks.map { |block| [ block[:start_time], block[:end_time], block[:status] ] }).to eq([
      [ "10:31", "12:00", "free" ], [ "12:00", "13:00", "full" ], [ "13:00", "18:00", "free" ]
    ])
  end
end
