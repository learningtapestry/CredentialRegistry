require 'spec_helper'

RSpec.describe API::V1::Ctdl do
  context 'POST /ctdl' do
    let(:auth_token) { create(:auth_token).value }

    let(:query) do
      {
      	'@type' => 'ceterms:Certificate',
      	'search:termGroup' => [
      		{
      			'ceterms:name' => 'accounting',
      			'ceterms:description' => 'accounting'
      		},
      		{
      			'ceterms:keyword' => 'finance'
      		}
      	]
      }
    end

    context 'invalid token' do
      let(:auth_token) { Faker::Lorem.characters }

      it 'returns a 401' do
        post '/ctdl',
             query.to_json,
             'Authorization' => "Token #{auth_token}",
             'Content-Type' => 'application/json'

        expect_status(:unauthorized)
      end
    end

    context 'failure' do
      let(:ctdl_query) { double('ctdl_query') }
      let(:error) { Faker::Lorem.sentence }

      before do
        expect(CtdlQuery).to receive(:new)
          .at_least(:once).times
          .and_return(ctdl_query)

        expect(ctdl_query).to receive(:execute).and_raise(error)
      end

      it 'returns the error' do
        expect {
          post '/ctdl',
               query.to_json,
               'Authorization' => "Token #{auth_token}",
               'Content-Type' => 'application/json'
        }.to change { QueryLog.count }.by(1)

        expect_status(:internal_server_error)
        expect_json('error', error)

        query_log = QueryLog.last
        expect(query_log.completed_at).to be
        expect(query_log.ctdl).to eq(query.to_json)
        expect(query_log.engine).to eq('ctdl')
        expect(query_log.error).to eq(error)
        expect(query_log.query).to eq(nil)
        expect(query_log.result).to eq(nil)
        expect(query_log.started_at).to be
      end
    end

    context 'success' do
      let(:count) { rand(100..1_000) }
      let(:count_query) { double('count_query') }
      let(:data_query) { double('data_query') }
      let(:payload1) { JSON(Faker::Json.shallow_json).symbolize_keys }
      let(:payload2) { JSON(Faker::Json.shallow_json).symbolize_keys }
      let(:payload3) { JSON(Faker::Json.shallow_json).symbolize_keys }
      let(:sql) { Faker::Lorem.paragraph }

      before do
        allow(CtdlQuery).to receive(:new) do |*args|
          expect(args.first).to eq(query)

          options = args.last
          projection = options.fetch(:projection)

          if projection == 'COUNT(*) AS count'
            expect(options.key?(:skip)).to eq(false)
            expect(options.key?(:take)).to eq(false)
            count_query
          elsif projection == 'payload'
            expect(options.fetch(:skip)).to eq(skip)
            expect(options.fetch(:take)).to eq(take)
            data_query
          else
            raise "Unexpected projection: #{projection}"
          end
        end

        allow(count_query).to receive(:execute)
          .and_return([{ 'count' => count }])

        allow(data_query).to receive(:execute)
          .and_return([
            { 'payload' => payload1.to_json },
            { 'payload' => payload2.to_json },
            { 'payload' => payload3.to_json }
          ])

        allow(data_query).to receive(:to_sql).and_return(sql)
      end

      context 'default params' do
        let(:skip) { 0 }
        let(:take) { 10 }

        it 'returns query results with a total count' do
          expect {
            post '/ctdl',
                 query.to_json,
                 'Authorization' => "Token #{auth_token}",
                 'Content-Type' => 'application/json'
          }.to change { QueryLog.count }.by(1)

          expect_status(:ok)
          expect_json('data', [payload1, payload2, payload3])
          expect_json('total', count)
          expect_json('sql', sql)

          query_log = QueryLog.last
          expect(query_log.completed_at).to be
          expect(query_log.ctdl).to eq(query.to_json)
          expect(query_log.engine).to eq('ctdl')
          expect(query_log.error).to eq(nil)
          expect(query_log.query).to eq(sql)
          expect(query_log.result).to eq(response.body)
          expect(query_log.started_at).to be
        end
      end

      context 'custom params' do
        let(:skip) { 50 }
        let(:take) { 25 }

        it 'returns query results with a total count' do
          expect {
            post "/ctdl?log=no&skip=#{skip}&take=#{take}",
                 query.to_json,
                 'Authorization' => "Token #{auth_token}",
                 'Content-Type' => 'application/json'
          }.not_to change { QueryLog.count }

          expect_status(:ok)
          expect_json('data', [payload1, payload2, payload3])
          expect_json('total', count)
          expect_json('sql', sql)
        end
      end
    end
  end
end
