class OccupancyReport
  class InvalidPeriod < StandardError; end

  MAX_DAYS = 92
  LOW_OCCUPANCY = 0.25
  HIGH_OCCUPANCY = 0.75
  SECONDS_PER_HOUR = 3600
  LAST_HOUR = 23
  OPERATING_HOURS = (0..LAST_HOUR).to_a.freeze

  USAGE_SQL = <<~SQL.freeze
    SELECT r.space_id,
           r.date,
           h.hour,
           SUM(
             (LEAST(EXTRACT(EPOCH FROM r.end_time), (h.hour + 1) * :seconds_per_hour)
              - GREATEST(EXTRACT(EPOCH FROM r.start_time), h.hour * :seconds_per_hour))
             * CASE WHEN s.space_type = :private_type THEN 1 ELSE r.seats_reserved END
           ) AS used_seconds
    FROM reservations r
    INNER JOIN spaces s ON s.id = r.space_id
    CROSS JOIN generate_series(0, :last_hour) AS h(hour)
    WHERE r.status = :confirmed
      AND r.date BETWEEN :from AND :to
      AND r.space_id IN (:space_ids)
      AND EXTRACT(EPOCH FROM r.start_time) < (h.hour + 1) * :seconds_per_hour
      AND EXTRACT(EPOCH FROM r.end_time) > h.hour * :seconds_per_hour
    GROUP BY r.space_id, r.date, h.hour
  SQL

  class Usage
    def initialize(rows)
      @by_space = Hash.new(0.0)
      @by_space_hour = Hash.new(0.0)
      @by_space_day = Hash.new(0.0)

      rows.each do |space_id, date, hour, seconds|
        @by_space[space_id] += seconds
        @by_space_hour[[ space_id, hour ]] += seconds
        @by_space_day[[ space_id, date ]] += seconds
      end
    end

    def for_space(space_id)
      @by_space[space_id]
    end

    def for_hour(space_id, hour)
      @by_space_hour[[ space_id, hour ]]
    end

    def for_day(space_id, date)
      @by_space_day[[ space_id, date ]]
    end
  end

  attr_reader :from, :to, :space

  def initialize(from:, to:, space: nil)
    @from = from
    @to = to
    @space = space

    validate_period!
  end

  def call
    spaces = operating_spaces
    usage = Usage.new(usage_rows(spaces))
    counts = reservation_counts(spaces)

    rows = spaces.map { |current| space_report(current, usage, counts.fetch(current.id, 0)) }

    {
      from: from,
      to: to,
      days: days,
      summary: summary(spaces, usage, rows),
      spaces: rows
    }
  end

  private

  def validate_period!
    raise InvalidPeriod, "La fecha inicial no puede ser posterior a la final" if from > to
    raise InvalidPeriod, "El periodo no puede superar #{MAX_DAYS} días" if days > MAX_DAYS
  end

  def days
    (to - from).to_i + 1
  end

  def operating_spaces
    scope = Space.active.where.not(start_time: nil).where.not(end_time: nil).order(:name)
    scope = scope.where(id: space.id) if space
    scope.to_a
  end

  def usage_rows(spaces)
    return [] if spaces.empty?

    sql = Reservation.sanitize_sql_array([ USAGE_SQL, usage_binds(spaces) ])
    Reservation.connection.select_all(sql).cast_values
  end

  def usage_binds(spaces)
    {
      from: from,
      to: to,
      confirmed: Reservation.statuses[:confirmed],
      private_type: Space.space_types[:private_space],
      space_ids: spaces.map(&:id),
      last_hour: LAST_HOUR,
      seconds_per_hour: SECONDS_PER_HOUR
    }
  end

  def reservation_counts(spaces)
    Reservation.confirmed
               .where(date: from..to, space_id: spaces.map(&:id))
               .group(:space_id)
               .count
  end

  def space_report(current, usage, reservations)
    occupancy = rate(usage.for_space(current.id), available_seconds(current))

    {
      id: current.id,
      name: current.name,
      space_type: current.space_type,
      capacity: current.capacity,
      occupancy_rate: occupancy,
      reservations: reservations,
      classification: classify(occupancy),
      hours: hour_breakdown(current, usage),
      days: day_breakdown(current, usage)
    }
  end

  def summary(spaces, usage, rows)
    available = spaces.sum { |current| available_seconds(current) }
    used = spaces.sum { |current| usage.for_space(current.id) }

    {
      occupancy_rate: rate(used, available),
      reservations: rows.sum { |row| row[:reservations] },
      underused_spaces: rows.count { |row| row[:classification] == "underused" },
      high_demand_spaces: rows.count { |row| row[:classification] == "high_demand" }
    }
  end

  def hour_breakdown(current, usage)
    opening = current.start_time.seconds_since_midnight
    closing = current.end_time.seconds_since_midnight

    OPERATING_HOURS.filter_map do |hour|
      hour_start = hour * SECONDS_PER_HOUR
      hour_end = hour_start + SECONDS_PER_HOUR
      overlap = [ closing, hour_end ].min - [ opening, hour_start ].max
      next unless overlap.positive?

      available = capacity_units(current) * overlap * days
      { hour: hour, occupancy_rate: rate(usage.for_hour(current.id, hour), available) }
    end
  end

  def day_breakdown(current, usage)
    per_day = capacity_units(current) * window_seconds(current)

    (from..to).map do |date|
      { date: date, occupancy_rate: rate(usage.for_day(current.id, date), per_day) }
    end
  end

  def available_seconds(current)
    capacity_units(current) * window_seconds(current) * days
  end

  def window_seconds(current)
    current.end_time.seconds_since_midnight - current.start_time.seconds_since_midnight
  end

  def capacity_units(current)
    current.private_space? ? 1 : current.capacity
  end

  def rate(used, available)
    return 0.0 if available.zero?

    (used.to_f / available).round(4)
  end

  def classify(occupancy)
    if occupancy < LOW_OCCUPANCY
      "underused"
    elsif occupancy >= HIGH_OCCUPANCY
      "high_demand"
    else
      "normal"
    end
  end
end
