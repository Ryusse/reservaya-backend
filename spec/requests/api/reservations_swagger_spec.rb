require 'swagger_helper'

RSpec.describe 'Reservations API', type: :request do
  path '/reservations' do
    post 'Crear una reserva' do
      tags 'Reservas'
      consumes 'application/json'
      produces 'application/json'
      security [ bearer_auth: [], cookie_auth: [] ]

      parameter name: :reservation, in: :body, schema: {
        type: :object,
        properties: {
          reservation: {
            type: :object,
            properties: {
              space_id: { type: :integer },
              date: { type: :string, example: '2026-10-10' },
              start_time: { type: :string, example: '10:00' },
              end_time: { type: :string, example: '12:00' },
              seats_reserved: { type: :integer }
            },
            required: [ 'space_id', 'date', 'start_time', 'end_time', 'seats_reserved' ]
          }
        }
      }

      response '201', 'Reserva creada' do
        let(:space) { create(:space, capacity: 10, start_time: '08:00', end_time: '18:00') }
        let(:reservation) do
          {
            reservation: {
              space_id: space.id,
              date: Date.tomorrow.to_s,
              start_time: '10:00',
              end_time: '12:00',
              seats_reserved: 5
            }
          }
        end

        before do
          user = User.create!(name: 'Test', email: 'test@test.com', password: 'Password123', role: :user)
          post '/session', params: { email: user.email, password: 'Password123' }, as: :json
        end

        run_test!
      end

      response '422', 'El espacio no existe' do
        let(:reservation) do
          {
            reservation: {
              space_id: 99999,
              date: Date.tomorrow.to_s,
              start_time: '10:00',
              end_time: '12:00',
              seats_reserved: 1
            }
          }
        end

        before do
          user = User.create!(name: 'Test', email: 'test@test.com', password: 'Password123', role: :user)
          post '/session', params: { email: user.email, password: 'Password123' }, as: :json
        end

        run_test!
      end

      response '422', 'El horario ya está reservado' do
        let(:space) { create(:space, space_type: :private_space, capacity: 1, start_time: '08:00', end_time: '18:00') }
        let(:reservation) do
          {
            reservation: {
              space_id: space.id,
              date: Date.tomorrow.to_s,
              start_time: '10:00',
              end_time: '12:00',
              seats_reserved: 1
            }
          }
        end

        before do
          create(:reservation, space: space, date: Date.tomorrow, start_time: '10:00', end_time: '12:00')

          user = User.create!(name: 'Test', email: 'test@test.com', password: 'Password123', role: :user)
          post '/session', params: { email: user.email, password: 'Password123' }, as: :json
        end

        run_test!
      end

      response '401', 'No autenticado' do
        let(:space) { create(:space) }
        let(:reservation) do
          {
            reservation: {
              space_id: space.id,
              date: Date.tomorrow.to_s,
              start_time: '10:00',
              end_time: '12:00',
              seats_reserved: 1
            }
          }
        end

        run_test!
      end
    end
  end

  path '/reservations/{id}/cancel' do
    patch 'Cancelar una reserva propia' do
      tags 'Reservas'
      produces 'application/json'
      security [ bearer_auth: [], cookie_auth: [] ]

      parameter name: :id, in: :path, type: :integer, required: true

      response '200', 'Reserva cancelada' do
        let(:user) { User.create!(name: 'Test', email: 'cancel@test.com', password: 'Password123', role: :user) }
        let(:space) { create(:space, capacity: 10, start_time: '08:00', end_time: '18:00') }
        let(:id) { create(:reservation, user: user, space: space, date: Date.tomorrow, start_time: '10:00', end_time: '12:00').id }

        before do
          post '/session', params: { email: user.email, password: 'Password123' }, as: :json
        end

        run_test!
      end

      response '422', 'La reserva ya fue cancelada o ya comenzó' do
        let(:user) { User.create!(name: 'Test', email: 'cancel2@test.com', password: 'Password123', role: :user) }
        let(:space) { create(:space, capacity: 10, start_time: '08:00', end_time: '18:00') }
        let(:id) { create(:reservation, user: user, space: space, date: Date.tomorrow, start_time: '10:00', end_time: '12:00', status: :cancelled).id }

        before do
          post '/session', params: { email: user.email, password: 'Password123' }, as: :json
        end

        run_test!
      end

      response '404', 'La reserva no existe' do
        let(:user) { User.create!(name: 'Test', email: 'cancel3@test.com', password: 'Password123', role: :user) }
        let(:id) { 0 }

        before do
          post '/session', params: { email: user.email, password: 'Password123' }, as: :json
        end

        run_test!
      end
    end
  end
end
