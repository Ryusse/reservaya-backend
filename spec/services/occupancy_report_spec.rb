require "rails_helper"

RSpec.describe OccupancyReport do
  let(:day) { Date.current + 1.day }

  def rate_for(report, space)
    report[:spaces].find { |row| row[:id] == space.id }[:occupancy_rate]
  end

  def row_for(report, space)
    report[:spaces].find { |row| row[:id] == space.id }
  end

  describe "validation" do
    it "rejects a start date after the end date" do
      expect { described_class.new(from: day, to: day - 1) }
        .to raise_error(OccupancyReport::InvalidPeriod, "La fecha inicial no puede ser posterior a la final")
    end

    it "accepts exactly 92 days" do
      expect { described_class.new(from: day, to: day + 91) }.not_to raise_error
    end

    it "rejects a period longer than 92 days" do
      expect { described_class.new(from: day, to: day + 92) }
        .to raise_error(OccupancyReport::InvalidPeriod, "El periodo no puede superar 92 días")
    end
  end

  describe "#call" do
    context "with a private space" do
      let(:space) { create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00") }

      it "computes occupancy over the operating window of every day in the period" do
        create(:reservation, space: space, date: day, start_time: "09:00", end_time: "11:00")
        create(:reservation, space: space, date: day + 1.day, start_time: "09:00", end_time: "11:00")

        report = described_class.new(from: day, to: day + 1.day).call

        expect(rate_for(report, space)).to eq(0.2)
        expect(row_for(report, space)[:reservations]).to eq(2)
        expect(row_for(report, space)[:classification]).to eq("underused")
      end

      it "reports occupancy by hour and by day" do
        create(:reservation, space: space, date: day, start_time: "09:00", end_time: "10:00")

        report = described_class.new(from: day, to: day).call
        hours = row_for(report, space)[:hours].index_by { |hour| hour[:hour] }
        days = row_for(report, space)[:days]

        expect(hours[9][:occupancy_rate]).to eq(1.0)
        expect(hours[10][:occupancy_rate]).to eq(0.0)
        expect(days.first[:occupancy_rate]).to eq(0.1)
      end

      it "ignores cancelled reservations" do
        create(:reservation, space: space, date: day, start_time: "09:00", end_time: "11:00", status: :cancelled)

        report = described_class.new(from: day, to: day).call

        expect(rate_for(report, space)).to eq(0.0)
        expect(row_for(report, space)[:reservations]).to eq(0)
      end

      it "classifies a fully booked space as high demand" do
        create(:reservation, space: space, date: day, start_time: "08:00", end_time: "18:00")

        report = described_class.new(from: day, to: day).call

        expect(rate_for(report, space)).to eq(1.0)
        expect(row_for(report, space)[:classification]).to eq("high_demand")
        expect(report[:summary][:high_demand_spaces]).to eq(1)
      end
    end

    context "with a shared space" do
      let(:space) { create(:space, space_type: :shared_space, capacity: 4, start_time: "08:00", end_time: "18:00") }

      it "weights occupancy by the seats reserved against the capacity" do
        create(:reservation, space: space, date: day, start_time: "09:00", end_time: "10:00", seats_reserved: 2)

        report = described_class.new(from: day, to: day).call

        expect(rate_for(report, space)).to eq(0.05)
      end
    end

    it "returns zero occupancy for a period without reservations" do
      space = create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00")

      report = described_class.new(from: day, to: day + 2.days).call

      expect(rate_for(report, space)).to eq(0.0)
      expect(report[:summary][:occupancy_rate]).to eq(0.0)
      expect(report[:summary][:reservations]).to eq(0)
    end

    it "limits the report to one space when a space is given" do
      space = create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00")
      create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00")

      report = described_class.new(from: day, to: day, space: space).call

      expect(report[:spaces].map { |row| row[:id] }).to eq([ space.id ])
    end

    it "skips spaces without an operating window" do
      space = create(:space, space_type: :private_space, capacity: 1)
      space.update_columns(start_time: nil, end_time: nil)

      report = described_class.new(from: day, to: day).call

      expect(report[:spaces].map { |row| row[:id] }).not_to include(space.id)
    end
  end
end
