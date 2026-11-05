class Dashboard::OccupanciesController < ApplicationController
  before_action :require_login
  before_action :require_admin

  def show
    @report = OccupancyReport.new(
      from: period_start,
      to: period_end,
      space: requested_space,
      from_hour: hour_param(:from_hour, 0),
      to_hour: hour_param(:to_hour, OccupancyReport::LAST_HOUR)
    ).call
    render :show, status: :ok
  rescue Date::Error
    render json: { error: "Fecha inválida. Usa el formato AAAA-MM-DD" }, status: :unprocessable_entity
  rescue OccupancyReport::InvalidPeriod => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def period_start
    params[:from].present? ? Date.iso8601(params[:from]) : Date.current.beginning_of_month
  end

  def period_end
    params[:to].present? ? Date.iso8601(params[:to]) : Date.current.end_of_month
  end

  def hour_param(key, default)
    return default if params[key].blank?

    Integer(params[key], 10)
  rescue ArgumentError, TypeError
    raise OccupancyReport::InvalidPeriod, "Las horas deben estar entre 0 y #{OccupancyReport::LAST_HOUR}"
  end

  def requested_space
    Space.find(params[:space_id]) if params[:space_id].present?
  end
end
