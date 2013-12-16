module VCAP
  module Services
    module Swift
      class Storage
        
        attr_reader :connection
        
        def initialize(logger, fog_options = {
             :provider                => 'HP',
             :hp_access_key           => "admin",
             :hp_secret_key           => "your_pass",
             :hp_tenant_id            => "dee1ce4691e84ee6e5ea22b624c22a2e",
             :hp_auth_uri             =>  'https://auth.hydranodes.de:5000/v2.0/',
             :hp_use_upass_auth_style => true,
             :hp_avl_zone             => 'nova',
             :hp_auth_version         => :v2,
             :self_signed_ssl         => false
          })

          @logger                     = logger
          @fog_options                = fog_options
          connect
        end

        def connect
          Excon.defaults[:ssl_verify_peer] = false if @fog_options[:self_signed_ssl]
          @connection = Fog::Storage.new(@fog_options)
        rescue Excon::Errors::Unauthorized => e
          @logger.error "Couldn't connect to Fog, possibly due to missing _member_ role for user #{@fog_options[:hp_access_key]} and tenant: #{@fog_options[:hp_tenant_id]}"
        end

        def set_meta_key_and_quotas(meta_key, quotas)
          set_meta_headers({
            'X-Account-Meta-Temp-URL-Key' => meta_key,
            'X-Account-Meta-Quota-Bytes' => quotas
          })
        end

        def get_account_meta_data
          @connection.request({
            :method => 'GET'
          })
        end

        # Warning this deletes all directories and files!!!
        def delete_account
          @connection.request({
            :method => 'DELETE'
          })
        end

        private

        #TODO Move to fog and make pull request.
        # http://www.rackspace.com/blog/rackspace-cloud-files-how-to-create-temporary-urls/
        #
        # Further reading: http://docs.openstack.org/api/openstack-object-storage/1.0/content/create-update-account-metadata.html
        def set_meta_headers(headers)
          @logger.info "Setting #{headers.keys.join(', ')} for tenant #{@fog_options[:hp_tenant_id]}..."
          response = @connection.request({
            :method => 'POST',
            :headers => headers
          })

          # Confirm meta data changes
          response = @connection.request({
            :method => 'HEAD'
          })

          @logger.info "Done setting account meta key."
        end

      end
    end
  end
end
