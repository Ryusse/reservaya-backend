class ReservationBooking
  def initialize(reservation, attributes)
    @reservation = reservation
    @attributes = attributes
  end

  def call
    return false unless modifiable?

    space = target_space

    unless space
      @reservation.errors.add(:base, "Espacio no encontrado")
      return false
    end

    Space.transaction do
      space.lock!
      @reservation.assign_attributes(@attributes)
      @reservation.save
    end
  end

  private

  def modifiable?
    return true if @reservation.modifiable?

    @reservation.errors.add(:base, "Solo se pueden modificar reservas confirmadas que aún no han comenzado")
    false
  end

  def target_space
    Space.find_by(id: @attributes.fetch(:space_id, @reservation.space_id))
  end
end
