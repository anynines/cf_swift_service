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
             :hp_auth_version         => :v2
          })
          
          @logger                     = logger
          @fog_options                = fog_options
          connect
        end
        
        def connect
          @connection = Fog::Storage.new(@fog_options)
        rescue Excon::Errors::Unauthorized => e
          @logger.error "Couldn't connect to Fog, possibly due to missing _member_ role for user #{fog_options[:hp_access_key]} and tenant: #{fog_options[:hp_tenant_id]}"
        end
  
        def create_dir(dir)
          @logger.info "Creating dir #{dir}..."
          dir = @connection.directories.create(:key => dir)
          @logger.info "done."
          dir
        end
  
        # === Params
        # +dir_name+:: Directory name (String) as given by directory.key (fog Directory)
        # +file+:: File (Ruby) object pointing to the file to be uploaded (File.open(...))
        def upload_file(dir_name, file, filename = File.basename(file.to_path))
          file = nil

          # Upload
          dir = @connection.directories.get(dir_name)
          if dir then
            file = dir.files.create(:key => filename, :body => file)      
          else
            @logger.info "\nWarning: #{dir_name} does not exist.\n"
          end    
          file
        end

        def delete_file(id, dir = test)
          file = @connection.directories.get(dir).files.get(id)
          file.destroy
        end
  
        #TODO Move to fog and make pull request.
        # http://www.rackspace.com/blog/rackspace-cloud-files-how-to-create-temporary-urls/
        #
        # Further reading: http://docs.openstack.org/api/openstack-object-storage/1.0/content/create-update-account-metadata.html
        def set_account_meta_key(account_meta_key)
          @logger.info "Setting account meta key for tenant #{@fog_options[:hp_tenant_id]}..."
          response = @connection.request({
            :method => 'POST',
            :headers => { 
              'X-Account-Meta-Temp-URL-Key' => account_meta_key
             }
          })
          
          # Confirm meta data changes
          response = @connection.request({
            :method => 'HEAD'
          })
                    
          @logger.info "Done setting account meta key."
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
    
        #TODO Move to fog and make pull request.
        # === Params
        # +file+:: Fog File object
        # +expires+:: time in seconds the temp url shall remain valid
        # +account_meta_key+:: Tenant wide account meta key as set by set_account_meta_key
        def create_temp_url(file, expires = Time.now.to_i + 600, account_meta_key = @account_meta_key)
    
          # Generate tempURL
          method      = 'GET'
    
          public_url  = URI(file.public_url)
          base        = "#{public_url.scheme}://#{public_url.host}/"
          path        = public_url.path

          hmac_body   = "#{method}\n#{expires}\n#{path}"
          sig         = Digest::HMAC.hexdigest(hmac_body, account_meta_key, Digest::SHA1)

          "#{file.public_url}?temp_url_sig=#{sig}&temp_url_expires=#{expires}"
        end
        
        def make_directory_public(directory)
          unless directory.public?
            directory.public = true
            return directory.save
          end
          true
        end
  
        def make_directory_private(directory)
          if directory.public?
            directory.public = false
            return directory.save
          end
          true
        end
      end
    end
  end
end