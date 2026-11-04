# == Schema Information
#
# Table name: spaces
#
#  id         :bigint           not null, primary key
#  capacity   :integer
#  end_time   :time
#  location   :string
#  name       :string
#  space_type :integer          default(0), not null
#  start_time :time
#  status     :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Space < ApplicationRecord
  has_many :reservations, dependent: :restrict_with_error

  enum :status, { active: 0, inactive: 1 }
  enum :space_type, { private_space: 0, shared_space: 1 }

  validates :name, :location, :start_time, :end_time, :space_type, :status, presence: true
  validates :capacity, presence: true, numericality: { greater_than: 0 }

  validate :end_time_after_start_time

  def availability_blocks(date, now: Time.current)
    blocks = schedule_blocks(date)
    return blocks unless date == now.to_date

    cutoff = next_bookable_time(now)

    blocks.filter_map do |block|
      next if block[:end_time] <= cutoff

      block.merge(start_time: [ block[:start_time], cutoff ].max)
    end
  end

  def schedule_blocks(date)
    return [] unless active? && start_time.present? && end_time.present?

    reserved = reservations.confirmed.where(date: date)

    # 1. Recopilar todos los puntos de tiempo relevantes
    time_points = [ start_time, end_time ]
    reserved.each do |r|
      time_points << r.start_time
      time_points << r.end_time
    end
    time_points = time_points.sort.uniq.select { |t| t >= start_time && t <= end_time }

    blocks = []
    # 2. Construir bloques entre cada par de puntos adyacentes
    (0...time_points.length - 1).each do |i|
      t1 = time_points[i]
      t2 = time_points[i + 1]

      # Calcular capacidad usada en este intervalo [t1, t2]
      # Una reserva cubre este bloque si r.start_time <= t1 y r.end_time >= t2
      overlapping = reserved.select { |r| r.start_time <= t1 && r.end_time >= t2 }

      used_capacity = if private_space?
                        overlapping.any? ? capacity : 0
      else
                        overlapping.sum(&:seats_reserved)
      end

      available = capacity - used_capacity
      status = if available == capacity
                 "free"
      elsif available <= 0
                 "full"
      else
                 "partial"
      end

      # Evitar bloques con 0 duración
      next if t1 == t2

      blocks << {
        start_time: t1.strftime("%H:%M"),
        end_time: t2.strftime("%H:%M"),
        status: status,
        seats_available: available
      }
    end

    # 3. Consolidar bloques adyacentes que tengan el mismo estado y asientos disponibles
    consolidate_blocks(blocks)
  end

  private

  def next_bookable_time(now)
    (now.beginning_of_minute + 1.minute).strftime("%H:%M")
  end

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    errors.add(:end_time, "Debe ser después de la hora de inicio") if end_time <= start_time
  end

  def consolidate_blocks(blocks)
    return [] if blocks.empty?

    consolidated = [ blocks.first ]

    blocks[1..-1].each do |block|
      last_block = consolidated.last
      if last_block[:status] == block[:status] && last_block[:seats_available] == block[:seats_available] && last_block[:end_time] == block[:start_time]
        last_block[:end_time] = block[:end_time]
      else
        consolidated << block
      end
    end

    consolidated
  end
end
