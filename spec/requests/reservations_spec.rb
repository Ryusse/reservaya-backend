require "rails_helper"

RSpec.describe "Reservations", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{JsonWebToken.encode(user_id: user.id)}" } }
  let(:space) { create(:space, start_time: "08:00", end_time: "18:00", capacity: 10, space_type: :shared_space) }
  let(:payload) do
    { reservation: { space_id: space.id, date: Date.tomorrow.to_s, start_time: "08:00", end_time: "18:00", seats_reserved: 1 } }
  end

  describe "POST /reservations" do
    it "creates the reservation" do
      expect { post "/reservations", params: payload, headers: headers, as: :json }
        .to change(Reservation, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "still responds 201 when the notification email cannot be enqueued" do
      allow(NotificationMailer).to receive(:reservation_created).and_raise(StandardError, "queue down")

      expect { post "/reservations", params: payload, headers: headers, as: :json }
        .to change(Reservation, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "responds 422 with errors for an invalid reservation" do
      post "/reservations", params: payload.deep_merge(reservation: { end_time: "07:00" }), headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).not_to be_empty
    end
  end

  describe "PATCH /reservations/:id" do
    let(:private_space) { create(:space, capacity: 1, space_type: :private_space, start_time: "08:00", end_time: "18:00") }
    let(:reservation) do
      create(:reservation, user: user, space: private_space, date: Date.current + 1.day, start_time: "09:00", end_time: "10:00")
    end
    let(:update_payload) { { reservation: { start_time: "11:00", end_time: "12:00" } } }

    it "updates the user's own reservation keeping its id" do
      patch "/reservations/#{reservation.id}", params: update_payload, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(reservation.reload.start_time.strftime("%H:%M")).to eq("11:00")
    end

    it "responds 422 and keeps the original when the new slot is taken" do
      create(:reservation, space: private_space, user: create(:user), date: Date.current + 1.day,
                           start_time: "11:00", end_time: "12:00")

      patch "/reservations/#{reservation.id}", params: { reservation: { start_time: "11:30", end_time: "12:30" } },
                                               headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).not_to be_empty
      expect(reservation.reload.start_time.strftime("%H:%M")).to eq("09:00")
    end

    it "responds 403 when the reservation belongs to another user" do
      other_reservation = create(:reservation, space: private_space, date: Date.current + 1.day,
                                               start_time: "13:00", end_time: "14:00")

      patch "/reservations/#{other_reservation.id}", params: update_payload, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "responds 404 with a JSON error when the reservation does not exist" do
      patch "/reservations/0", params: update_payload, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("No encontrado")
    end
  end

  describe "PATCH /reservations/:id/cancel" do
    let(:reservation) do
      create(:reservation, user: user, space: space, date: Date.current + 1.day, start_time: "09:00", end_time: "10:00")
    end

    it "cancels the user's own reservation" do
      patch "/reservations/#{reservation.id}/cancel", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("cancelled")
      expect(reservation.reload).to be_cancelled
    end

    it "responds 404 with a JSON error when the reservation does not exist" do
      patch "/reservations/0/cancel", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("No encontrado")
    end

    it "responds 403 when the reservation belongs to another user" do
      other_reservation = create(:reservation, space: space, date: Date.current + 1.day, start_time: "11:00", end_time: "12:00")

      patch "/reservations/#{other_reservation.id}/cancel", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(other_reservation.reload).to be_confirmed
    end

    it "responds 422 when the reservation is already cancelled" do
      reservation.update!(status: :cancelled)

      patch "/reservations/#{reservation.id}/cancel", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to include("Solo se pueden cancelar reservas confirmadas")
    end

    it "responds 422 when the reservation already started" do
      started_space = create(:space, start_time: "00:00", end_time: "23:59", capacity: 10, space_type: :shared_space)
      started = create(:reservation, user: user, space: started_space, date: Date.current,
                                     start_time: "00:00", end_time: "00:30")

      patch "/reservations/#{started.id}/cancel", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(started.reload).to be_confirmed
    end
  end
end
