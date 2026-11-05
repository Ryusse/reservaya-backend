require "rails_helper"

RSpec.describe Reservation, type: :model do
  let(:space) { create(:space, capacity: 5, start_time: "08:00", end_time: "18:00", space_type: :private_space) }
  let(:user) { create(:user) }

  subject(:reservation) do
    build(:reservation, space: space, user: user, date: Date.current + 1.day,
                         start_time: "09:00", end_time: "10:00", seats_reserved: 1)
  end

  it "has a valid factory" do
    expect(reservation).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:date) }
    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }
    it { is_expected.to validate_presence_of(:seats_reserved) }
    it { is_expected.to validate_numericality_of(:seats_reserved).is_greater_than(0) }

    it { is_expected.to belong_to(:space) }
    it { is_expected.to belong_to(:user) }

    it { is_expected.to define_enum_for(:status).with_values(confirmed: 0, cancelled: 1) }

    it "is invalid when end_time is not after start_time" do
      reservation.start_time = "10:00"
      reservation.end_time = "09:00"
      expect(reservation).not_to be_valid
      expect(reservation.errors[:end_time]).to include("Debe ser después de la hora de inicio")
    end

    it "is invalid when the date is in the past" do
      reservation.date = Date.current - 1.day
      expect(reservation).not_to be_valid
      expect(reservation.errors[:date]).to include("No puede estar en el pasado")
    end

    it "is invalid when the date is more than 7 days ahead" do
      reservation.date = Date.current + 8.days
      expect(reservation).not_to be_valid
      expect(reservation.errors[:date]).to include("Solo puede reservar con un máximo de 7 días de anticipación")
    end

    it "is valid exactly at the 7 day boundary" do
      reservation.date = Date.current + 7.days
      expect(reservation).to be_valid
    end

    it "is invalid when the space is not active" do
      space.update!(status: :inactive)
      expect(reservation).not_to be_valid
      expect(reservation.errors[:space]).to include("No está activo")
    end

    it "is invalid when the reservation starts before the space opens" do
      reservation.start_time = "07:00"
      expect(reservation).not_to be_valid
      expect(reservation.errors[:base]).to include("La reserva debe estar dentro del horario disponible del espacio")
    end

    it "is invalid when the reservation ends after the space closes" do
      reservation.end_time = "19:00"
      expect(reservation).not_to be_valid
      expect(reservation.errors[:base]).to include("La reserva debe estar dentro del horario disponible del espacio")
    end

    it "is invalid when seats_reserved exceeds the space capacity" do
      reservation.seats_reserved = space.capacity + 1
      expect(reservation).not_to be_valid
      expect(reservation.errors[:seats_reserved]).to include("No puede exceder la capacidad del espacio")
    end

    it "is invalid when the user already has 3 active (confirmed, future) reservations" do
      3.times do |i|
        create(:reservation, user: user, space: create(:space, capacity: 5), status: :confirmed,
                              date: Date.current + (i + 2).days, start_time: "09:00", end_time: "10:00")
      end

      expect(reservation).not_to be_valid
      expect(reservation.errors[:base]).to include("Solo puede tener un máximo de 3 reservas activas")
    end

    it "does not count cancelled reservations toward the active reservation limit" do
      3.times do |i|
        create(:reservation, user: user, space: create(:space, capacity: 5), status: :cancelled,
                              date: Date.current + (i + 2).days, start_time: "09:00", end_time: "10:00")
      end

      expect(reservation).to be_valid
    end

    it "is invalid when the same user has overlapping confirmed reservations at the same time" do
      create(:reservation, user: user, space: create(:space, capacity: 5), date: Date.current + 1.day,
                            start_time: "09:30", end_time: "10:30", status: :confirmed)

      expect(reservation).not_to be_valid
      expect(reservation.errors[:base]).to include("No puede tener reservas cruzadas en el mismo horario")
    end
  end

  describe "lifecycle rules" do
    it "skips availability rules for cancelled reservations" do
      reservation.status = :cancelled
      space.update!(status: :inactive)
      reservation.date = Date.current - 1.day

      expect(reservation).to be_valid
    end

    it "is modifiable only while confirmed and not started" do
      expect(reservation).to be_modifiable

      reservation.status = :cancelled
      expect(reservation).not_to be_modifiable
    end

    it "is not started when its start time is in the future" do
      expect(reservation).not_to be_started
    end

    it "is started when its start time has already passed" do
      reservation.date = Date.current
      reservation.start_time = "00:00"

      expect(reservation).to be_started
    end

    it "cancels a confirmed reservation that has not started" do
      reservation.save!

      expect(reservation.cancel).to be(true)
      expect(reservation.reload).to be_cancelled
    end

    it "cancels even when the space was deactivated after booking" do
      reservation.save!
      space.update!(status: :inactive)

      expect(reservation.cancel).to be(true)
      expect(reservation.reload).to be_cancelled
    end

    it "refuses to cancel a reservation that already started" do
      started_space = create(:space, start_time: "00:00", end_time: "23:59", capacity: 10, space_type: :shared_space)
      started = create(:reservation, user: user, space: started_space, date: Date.current + 1.day,
                                     start_time: "00:00", end_time: "00:30")
      started.update_columns(date: Date.current)

      expect(started.cancel).to be(false)
      expect(started.errors[:base]).to include("No se puede cancelar una reserva que ya comenzó")
      expect(started.reload).to be_confirmed
    end

    it "refuses to cancel a reservation that is already cancelled" do
      reservation.save!
      reservation.cancel

      expect(reservation.cancel).to be(false)
      expect(reservation.errors[:base]).to include("La reserva ya está cancelada")
    end
  end

  describe "availability by space type" do
    context "when the space is a private_space" do
      let(:private_space) { create(:space, capacity: 5, space_type: :private_space, start_time: "08:00", end_time: "18:00") }

      it "is invalid when the space is already reserved for an overlapping interval" do
        create(:reservation, space: private_space, user: create(:user), date: Date.current + 1.day,
                              start_time: "09:00", end_time: "10:00", status: :confirmed)

        other_reservation = build(:reservation, space: private_space, user: user, date: Date.current + 1.day,
                                                 start_time: "09:30", end_time: "10:30")

        expect(other_reservation).not_to be_valid
        expect(other_reservation.errors[:base]).to include("Este espacio ya está reservado para ese intervalo de tiempo")
      end

      it "is valid when a different, non-overlapping interval is requested" do
        create(:reservation, space: private_space, user: create(:user), date: Date.current + 1.day,
                              start_time: "09:00", end_time: "10:00", status: :confirmed)

        other_reservation = build(:reservation, space: private_space, user: user, date: Date.current + 1.day,
                                                 start_time: "10:00", end_time: "11:00")

        expect(other_reservation).to be_valid
      end
    end

    context "when the space is a shared_space" do
      let(:shared_space) { create(:space, capacity: 5, space_type: :shared_space, start_time: "08:00", end_time: "18:00") }

      it "is valid while there is still capacity left for the overlapping interval" do
        create(:reservation, space: shared_space, user: create(:user), date: Date.current + 1.day,
                              start_time: "09:00", end_time: "10:00", seats_reserved: 3, status: :confirmed)

        other_reservation = build(:reservation, space: shared_space, user: user, date: Date.current + 1.day,
                                                 start_time: "09:30", end_time: "10:30", seats_reserved: 2)

        expect(other_reservation).to be_valid
      end

      it "is invalid when the overlapping seats would exceed the space capacity" do
        create(:reservation, space: shared_space, user: create(:user), date: Date.current + 1.day,
                              start_time: "09:00", end_time: "10:00", seats_reserved: 4, status: :confirmed)

        other_reservation = build(:reservation, space: shared_space, user: user, date: Date.current + 1.day,
                                                 start_time: "09:30", end_time: "10:30", seats_reserved: 2)

        expect(other_reservation).not_to be_valid
        expect(other_reservation.errors[:base]).to include("No hay cupos disponibles para ese intervalo de tiempo")
      end
    end
  end
end
