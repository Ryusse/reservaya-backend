class ApplicationController < ActionController::API
  include ActionController::Cookies

  SESSION_COOKIE = :reservaya_session

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  before_action :ensure_json_request, if: -> { request.post? || request.put? || request.patch? || request.delete? }

  private

  def render_not_found
    render json: { error: "No encontrado" }, status: :not_found
  end

  def ensure_json_request
    return if request.format.json? || request.content_type == "application/json"

    render json: { error: "Tipo de contenido no soportado. Se requiere application/json para mitigar CSRF." }, status: :unsupported_media_type
  end

  def current_user
    @current_user
  end

  def require_login
    token = session_token

    return render json: { error: "No autorizado" }, status: :unauthorized unless token

    decoded = JsonWebToken.decode(token)

    return render json: { error: "No autorizado" }, status: :unauthorized unless decoded

    @current_user = User.find_by(id: decoded[:user_id])
    render json: { error: "No autorizado" }, status: :unauthorized unless @current_user
  end

  def require_admin
    render json: { error: "Acceso solo para administradores" }, status: :forbidden unless current_user&.admin?
  end

  def session_token
    cookies.encrypted[SESSION_COOKIE].presence ||
      request.headers["Authorization"]&.split(" ")&.last
  end

  def set_session_cookie(token)
    cookies.encrypted[SESSION_COOKIE] = {
      value: token,
      httponly: true,
      secure: Rails.env.production?,
      same_site: Rails.env.production? ? :none : :lax,
      expires: 24.hours
    }
  end

  def clear_session_cookie
    cookies.delete(SESSION_COOKIE, secure: true, same_site: :none)
  end
end
