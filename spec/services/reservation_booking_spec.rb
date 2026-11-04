require "rails_helper"

RSpec.describe ReservationBooking do
  let(:user) { create(:user) }
  let(:space) { create(:space, capacity: 1, space_type: :private_space, start_time: "08:00", end_time: "18:00") }
  let(:other_space) { create(:space, capacity: 1, space_type: :private_space, start_time: "08:00", end_time: "18:00") }
  let(:reservation) do
    create(:reservation, user: user, space: space, date: Date.current + 1.day, start_time: "09:00", end_time: "10:00")
  end

  def stored_start_time(record)
    record.reload.start_time.strftime("%H:%M")
  end

  describe "creating" do
    it "persists a new reservation when the slot is free" do
      new_reservation = user.reservations.new

      result = described_class.new(new_reservation, {
        space_id: space.id, date: Date.current + 1.day, start_time: "10:00", end_time: "11:00", seats_reserved: 1
      }).call

      expect(result).to be(true)
      expect(new_reservation).to be_persisted
    end

    it "reports an unknown space" do
      new_reservation = user.reservations.new

      result = described_class.new(new_reservation, {
        space_id: 0, date: Date.current + 1.day, start_time: "10:00", end_time: "11:00", seats_reserved: 1
      }).call

      expect(result).to be(false)
      expect(new_reservation.errors[:base]).to include("Espacio no encontrado")
    end
  end

  describe "updating" do
    it "keeps the reservation id and applies the new time when the slot is free" do
      original_id = reservation.id

      result = described_class.new(reservation, { start_time: "11:00", end_time: "12:00" }).call

      expect(result).to be(true)
      expect(reservation.id).to eq(original_id)
      expect(stored_start_time(reservation)).to eq("11:00")
    end

    it "keeps the stored reservation untouched when the new slot is already taken" do
      create(:reservation, space: space, user: create(:user), date: Date.current + 1.day,
                           start_time: "11:00", end_time: "12:00")

      result = described_class.new(reservation, { start_time: "11:30", end_time: "12:30" }).call

      expect(result).to be(false)
      expect(reservation.errors[:base]).to include("Este espacio ya está reservado para ese intervalo de tiempo")
      expect(stored_start_time(reservation)).to eq("09:00")
    end

    it "checks availability of the target space when moving to another space" do
      create(:reservation, space: other_space, user: create(:user), date: Date.current + 1.day,
                           start_time: "09:00", end_time: "10:00")

      result = described_class.new(reservation, { space_id: other_space.id }).call

      expect(result).to be(false)
      expect(reservation.reload.space_id).to eq(space.id)
    end

    it "moves the reservation to another space when that slot is free" do
      result = described_class.new(reservation, { space_id: other_space.id }).call

      expect(result).to be(true)
      expect(reservation.reload.space_id).to eq(other_space.id)
    end

    it "reports an unknown target space and keeps the original" do
      result = described_class.new(reservation, { space_id: 0 }).call

      expect(result).to be(false)
      expect(reservation.errors[:base]).to include("Espacio no encontrado")
      expect(reservation.reload.space_id).to eq(space.id)
    end

    it "refuses to change a cancelled reservation" do
      reservation.update!(status: :cancelled)

      result = described_class.new(reservation, { start_time: "11:00", end_time: "12:00" }).call

      expect(result).to be(false)
      expect(reservation.errors[:base]).to include("Solo se pueden modificar reservas confirmadas que aún no han comenzado")
      expect(stored_start_time(reservation)).to eq("09:00")
    end

    it "refuses to change a reservation that already started" do
      started_space = create(:space, start_time: "00:00", end_time: "23:59", capacity: 10, space_type: :shared_space)
      started = create(:reservation, user: user, space: started_space, date: Date.current,
                                     start_time: "00:00", end_time: "00:30")

      result = described_class.new(started, { end_time: "00:45" }).call

      expect(result).to be(false)
      expect(started.errors[:base]).to include("Solo se pueden modificar reservas confirmadas que aún no han comenzado")
    end
  end
end
