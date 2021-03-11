module API
  module V1
    # Purges a given publisher's envelopes
    class BulkPurge < Grape::API
      namespace 'envelopes' do
        before do
          authenticate!
        end

        desc "Purges a given publisher's envelopes"
        params do
          requires :published_by, type: String
          optional :resource_type, type: String
          optional :from, type: DateTime
          optional :until, type: DateTime
        end
        delete do
          publisher = Organization.find_by!(_ctid: params[:published_by])
          envelopes = publisher.published_envelopes

          if params[:resource_type]
            envelopes = envelopes.where(resource_type: params[:resource_type])
          end

          if params[:from]
            envelopes = envelopes.where('created_at >= ?', params[:from])
          end

          if params[:until]
            envelopes = envelopes.where('created_at <= ?', params[:until])
          end

          { purged: envelopes.delete_all }
        end
      end
    end
  end
end
