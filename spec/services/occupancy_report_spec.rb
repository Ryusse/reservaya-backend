require "rails_helper"

RSpec.describe OccupancyReport do
  let(:day) { Date.current + 1.day }

  def rate_for(report, space)
    report[:spaces].find { |row| row[:id] == space.id }[:occupancy_rate]
  end

  def row_for(report, space)
    report[:spaces].find { |row| row[:id] == space.id }
  end

  describe "hour range" do
    let(:space) { create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00") }

    before { create(:reservation, space: space, date: day, start_time: "09:00", end_time: "10:00") }

    it "keeps only the requested hours in the breakdown" do
      report = described_class.new(from: day, to: day, from_hour: 9, to_hour: 12).call
      row = report[:spaces].find { |current| current[:id] == space.id }

      expect(row[:hours].map { |hour| hour[:hour] }).to eq([ 9, 10, 11, 12 ])
      expect(row[:hours].first[:occupancy_rate]).to eq(1.0)
    end

    it "measures occupancy against the availability inside the requested hours only" do
      report = described_class.new(from: day, to: day, from_hour: 9, to_hour: 12).call
      row = report[:spaces].find { |current| current[:id] == space.id }

      expect(row[:occupancy_rate]).to eq(0.25)
      expect(report[:summary][:occupancy_rate]).to eq(0.25)
    end

    it "rejects an inverted hour range" do
      expect { described_class.new(from: day, to: day, from_hour: 15, to_hour: 9) }
        .to raise_error(OccupancyReport::InvalidPeriod, "La hora inicial no puede ser posterior a la final")
    end

    it "rejects hours outside 0 to 23" do
      expect { described_class.new(from: day, to: day, from_hour: 0, to_hour: 24) }
        .to raise_error(OccupancyReport::InvalidPeriod, "Las horas deben estar entre 0 y 23")
    end
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

    it "excludes inactive spaces, which cannot be booked" do
      active = create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00")
      inactive = create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00", status: :inactive)

      report = described_class.new(from: day, to: day).call

      expect(report[:spaces].map { |row| row[:id] }).to include(active.id)
      expect(report[:spaces].map { |row| row[:id] }).not_to include(inactive.id)
    end

    it "skips spaces without an operating window" do
      space = create(:space, space_type: :private_space, capacity: 1)
      space.update_columns(start_time: nil, end_time: nil)

      report = described_class.new(from: day, to: day).call

      expect(report[:spaces].map { |row| row[:id] }).not_to include(space.id)
    end
  end
end
