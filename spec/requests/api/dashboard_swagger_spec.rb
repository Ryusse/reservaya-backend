require 'swagger_helper'

RSpec.describe 'Dashboard API', type: :request do
  path '/dashboard/occupancy' do
    get 'Ocupación de espacios por día y hora (solo administradores)' do
      tags 'Dashboard'
      produces 'application/json'
      security [ bearer_auth: [], cookie_auth: [] ]

      parameter name: :from, in: :query, type: :string, required: false, example: '2026-11-01',
                description: 'Fecha inicial (AAAA-MM-DD). Por defecto, inicio del mes actual.'
      parameter name: :to, in: :query, type: :string, required: false, example: '2026-11-30',
                description: 'Fecha final (AAAA-MM-DD). Por defecto, fin del mes actual. Máximo 92 días de rango.'
      parameter name: :space_id, in: :query, type: :integer, required: false,
                description: 'Limita el reporte a un espacio.'

      response '200', 'Reporte de ocupación' do
        let(:admin) { User.create!(name: 'Admin', email: 'occupancy-admin@test.com', password: 'Password123', role: :admin) }
        let(:from) { (Date.current + 1).to_s }
        let(:to) { (Date.current + 1).to_s }

        before do
          post '/session', params: { email: admin.email, password: 'Password123' }, as: :json
        end

        run_test!
      end

      response '422', 'Periodo inválido (fechas mal formadas, rango invertido o mayor a 92 días)' do
        let(:admin) { User.create!(name: 'Admin', email: 'occupancy-admin2@test.com', password: 'Password123', role: :admin) }
        let(:from) { '2026-12-31' }
        let(:to) { '2026-01-01' }

        before do
          post '/session', params: { email: admin.email, password: 'Password123' }, as: :json
        end

        run_test!
      end

      response '403', 'Usuario sin rol de administrador' do
        let(:user) { User.create!(name: 'Usuario', email: 'occupancy-user@test.com', password: 'Password123', role: :user) }

        before do
          post '/session', params: { email: user.email, password: 'Password123' }, as: :json
        end

        run_test!
      end
    end
  end
end
