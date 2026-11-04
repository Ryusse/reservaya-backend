# == Schema Information
#
# Table name: reservations
#
#  id             :bigint           not null, primary key
#  date           :date             not null
#  end_time       :time             not null
#  seats_reserved :integer          default(1), not null
#  start_time     :time             not null
#  status         :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  space_id       :bigint           not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_reservations_on_space_id  (space_id)
#  index_reservations_on_user_id   (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (space_id => spaces.id)
#  fk_rails_...  (user_id => users.id)
#
class Reservation < ApplicationRecord
  belongs_to :space
  belongs_to :user

  enum :status, { confirmed: 0, cancelled: 1 }

  validates :date, :start_time, :end_time, :seats_reserved, presence: true
  validates :seats_reserved, numericality: { greater_than: 0 }

  validate :end_time_after_start_time

  with_options if: :confirmed? do
    validate :date_not_in_the_past
    validate :date_within_allowed_range
    validate :space_is_active
    validate :within_space_schedule
    validate :seats_reserved_within_space_capacity
    validate :user_max_active_reservations
    validate :user_has_no_overlapping_reservations
    validate :availability_by_space_type
  end

  validate :start_not_in_the_past, if: -> { confirmed? && schedule_changed? }

  def cancel
    unless confirmed?
      errors.add(:base, "Solo se pueden cancelar reservas confirmadas")
      return false
    end

    if started?
      errors.add(:base, "No se puede cancelar una reserva que ya comenzó")
      return false
    end

    update(status: :cancelled)
  end

  def started?
    return false if date.blank? || start_time.blank?

    starts_at <= Time.current
  end

  def modifiable?
    confirmed? && !started?
  end

  def cancellable?
    modifiable?
  end

  private

  def starts_at
    date.in_time_zone + start_time.seconds_since_midnight
  end

  def schedule_changed?
    new_record? || will_save_change_to_date? || will_save_change_to_start_time?
  end

  def start_not_in_the_past
    return if date.blank? || start_time.blank?

    errors.add(:base, "No puede reservar un horario que ya comenzó") if started?
  end

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    errors.add(:end_time, "Debe ser después de la hora de inicio") if end_time <= start_time
  end

  def date_not_in_the_past
    return if date.blank?

    errors.add(:date, "No puede estar en el pasado") if date < Date.current
  end

  def date_within_allowed_range
    return if date.blank?

    if date > Date.current + 7.days
      errors.add(:date, "Solo puede reservar con un máximo de 7 días de anticipación")
    end
  end

  def space_is_active
    return if space.blank?

    errors.add(:space, "No está activo") unless space.active?
  end

  def within_space_schedule
    return if space.blank? || start_time.blank? || end_time.blank?
    return if space.start_time.blank? || space.end_time.blank?

    if start_time < space.start_time || end_time > space.end_time
      errors.add(:base, "La reserva debe estar dentro del horario disponible del espacio")
    end
  end

  def seats_reserved_within_space_capacity
    return if space.blank? || seats_reserved.blank?

    if seats_reserved > space.capacity
      errors.add(:seats_reserved, "No puede exceder la capacidad del espacio")
    end
  end

  def user_max_active_reservations
    return if user.blank?

    active_count = user.reservations.confirmed
                       .where("date >= ?", Date.current)
                       .where.not(id: id)
                       .count

    if active_count >= 3
      errors.add(:base, "Solo puede tener un máximo de 3 reservas activas")
    end
  end

  def user_has_no_overlapping_reservations
    return if user.blank? || date.blank? || start_time.blank? || end_time.blank?

    overlapping_user_reservations = user.reservations.confirmed
                                        .where(date: date)
                                        .where.not(id: id)
                                        .where("start_time < ? AND end_time > ?", end_time, start_time)

    if overlapping_user_reservations.exists?
      errors.add(:base, "No puede tener reservas cruzadas en el mismo horario")
    end
  end

  def availability_by_space_type
    return if space.blank? || date.blank? || start_time.blank? || end_time.blank?

    if space.private_space?
      validate_private_space_overlap
    elsif space.shared_space?
      validate_shared_space_capacity
    end
  end

  def validate_private_space_overlap
    if overlapping_confirmed_reservations.exists?
      errors.add(:base, "Este espacio ya está reservado para ese intervalo de tiempo")
    end
  end

  def validate_shared_space_capacity
    used_capacity = overlapping_confirmed_reservations.sum(:seats_reserved)

    if used_capacity + seats_reserved > space.capacity
      errors.add(:base, "No hay cupos disponibles para ese intervalo de tiempo")
    end
  end

  def overlapping_confirmed_reservations
    Reservation.confirmed
               .where(space_id: space_id, date: date)
               .where.not(id: id)
               .where("start_time < ? AND end_time > ?", end_time, start_time)
  end
end
