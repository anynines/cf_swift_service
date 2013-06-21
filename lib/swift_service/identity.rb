require 'fog'


module VCAP
  module Services
    module Swift
      class Identity
        
        attr_reader :keystone

        # Options as passed into SwiftNode
        def initialize(logger, fog_options)
          @logger = logger

          @keystone = Fog::Identity.new(fog_options)
        end

        def find_tenant(id)
          @keystone.tenants.find_by_id(id)
        end

        def delete_tenant(id)
          @logger.info "Deleting tenant #{id}..."
          tenant = find_tenant(id)
          ret = tenant.destroy
          @logger.info "Done deleting tenant  ."
          ret
        end

        def create_tenant(name)
          @logger.info "Creating tenant..."
          tenant = @keystone.tenants.create :name        => name,
                                            :description => 'Cloud Foundry Swift Tenant'
          @logger.info "Done creating tenant."
          tenant
        end

        def create_user(tenant, name, password)
          @logger.info "Creating user..."          
          user = @keystone.users.create :name       => name,
                                        :tenant_id  => tenant.id,
                                        :password   => password,
                                        :email      => name
          @logger.info "Done creating user."
          user
        end

        def find_user(id)
          @keystone.users.find_by_id(id)
        end

        def delete_user(id)
          @logger.info "Deleting user #{id}..."
          user = find_user(id)
          user.destroy
          @logger.info "Done deleting user."
        end

        def find_role(id)
          # Sadly roles.get doesn't work
          # TODO Create fog pull request so that roles.get returns a Role instead
          # of a response object
          # roles.get(id) should be enough.
          @keystone.roles.each do |role|
            return role if role.id.eql?(id)
          end
          nil
        end
        
        #
        # === Params 
        # +role_id+:: Role id as string
        # +user+:: Fog user object
        # +tenant+:: Fog tenant object
        def assign_role_to_user_for_tenant(role_id, user, tenant)
          @logger.info "Assigning role #{role_id} to user #{user.name} (#{user.id}) for tenant #{tenant.name} (#{tenant.id})..."
          role = find_role(role_id)
          role.add_to_user(user, tenant)    
          @logger.info "Done assigning role."
        end
      end
    end
  end
end