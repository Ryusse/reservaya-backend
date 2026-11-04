require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }

  def auth_headers(account)
    { "Authorization" => "Bearer #{JsonWebToken.encode(user_id: account.id)}" }
  end

  def json_headers(account)
    auth_headers(account).merge("Accept" => "application/json")
  end

  describe "GET /dashboard" do
    it "responds 200 with the metrics of the signed-in user" do
      get "/dashboard", headers: json_headers(user)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["role"]).to eq("user")
    end

    it "responds 200 with the admin metrics for administrators" do
      get "/dashboard", headers: json_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["role"]).to eq("admin")
    end
  end

  describe "GET /dashboard/occupancy" do
    let(:space) { create(:space, space_type: :private_space, capacity: 1, start_time: "08:00", end_time: "18:00") }
    let(:today) { Date.current.to_s }

    before do
      create(:reservation, space: space, user: user, date: Date.current, start_time: "09:00", end_time: "10:00")
    end

    it "responds 200 with the occupancy report for administrators" do
      get "/dashboard/occupancy", params: { from: today, to: today }, headers: json_headers(admin)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["from"]).to eq(today)
      expect(body["spaces"].find { |row| row["id"] == space.id }["reservations"]).to eq(1)
      expect(body["summary"]).to include("occupancy_rate", "underused_spaces", "high_demand_spaces")
    end

    it "defaults to the current month when no period is given" do
      get "/dashboard/occupancy", headers: json_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["from"]).to eq(Date.current.beginning_of_month.to_s)
    end

    it "responds 403 for regular users" do
      get "/dashboard/occupancy", headers: json_headers(user)

      expect(response).to have_http_status(:forbidden)
    end

    it "responds 401 without a session" do
      get "/dashboard/occupancy", headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "responds 422 when the start date is after the end date" do
      get "/dashboard/occupancy", params: { from: today, to: (Date.current - 1).to_s }, headers: json_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("La fecha inicial no puede ser posterior a la final")
    end

    it "responds 422 when the period is longer than 92 days" do
      get "/dashboard/occupancy", params: { from: "2026-01-01", to: "2026-06-01" }, headers: json_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "responds 422 when a date is malformed" do
      get "/dashboard/occupancy", params: { from: "no-es-fecha", to: today }, headers: json_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("Fecha inválida. Usa el formato AAAA-MM-DD")
    end

    it "responds 404 when the requested space does not exist" do
      get "/dashboard/occupancy", params: { from: today, to: today, space_id: 0 }, headers: json_headers(admin)

      expect(response).to have_http_status(:not_found)
    end
  end
end
