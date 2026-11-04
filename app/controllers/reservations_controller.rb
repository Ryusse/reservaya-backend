class ReservationsController < ApplicationController
  before_action :require_login
  before_action :set_reservation, only: [:show, :update, :cancel]
  before_action :authorize_owner_or_admin, only: [:show, :update, :cancel]

  def index
    @reservations =
      if current_user.admin?
        Reservation.includes(:space, :user).order(date: :desc, start_time: :desc)
      else
        current_user.reservations.includes(:space).order(date: :desc, start_time: :desc)
      end
  end

  def show
    render :show, status: :ok
  end

  def create
    @space = Space.find_by(id: reservation_params[:space_id])

    unless @space
      return render json: { errors: ["Espacio no encontrado"] }, status: :unprocessable_entity
    end

    @reservation = current_user.reservations.new(reservation_params)

    success = false
    Space.transaction do
      @space.lock!
      success = @reservation.save
    end

    if success
      notify_reservation_created
      render :create, status: :created
    else
      render json: { errors: @reservation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @reservation.update(reservation_params)
      render :update, status: :ok
    else
      render json: { errors: @reservation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def cancel
    if @reservation.cancel
      render :cancel, status: :ok
    else
      render json: { errors: @reservation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  # El correo es secundario: si falla el encolado (p. ej. cola o SMTP sin configurar),
  # la reserva ya está guardada y no debe responder 500.
  def notify_reservation_created
    NotificationMailer.reservation_created(current_user, @reservation).deliver_later
  rescue StandardError => e
    Rails.logger.error("[reservations] No se pudo encolar el correo de la reserva #{@reservation.id}: #{e.class}: #{e.message}")
  end

  def set_reservation
    @reservation = Reservation.find(params[:id])
  end

  def authorize_owner_or_admin
    return if current_user.admin?
    return if @reservation.user_id == current_user.id

    render json: { error: "No autorizado" }, status: :forbidden
  end

  def reservation_params
    params.require(:reservation).permit(:space_id, :date, :start_time, :end_time, :seats_reserved)
  end
end
