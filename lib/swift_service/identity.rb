require 'fog'


module VCAP
  module Services
    module Swift
      class Identity

        # Options as passed into SwiftNode
        def initialize(logger, fog_options)
          @logger = logger

          @keystone = Fog::Identity.new(fog_options[:identity])
        end

        def find_tenant(id)
          @keystone.tenants.find_by_id(id)
        end

        def delete_tenant(id)
          @logger.info "Deleting tenant #{id}..."
          tenant = find_tenant(id)
          ret = tenant.destroy
          @logger.info "done."
          ret
        end

        def create_tenant(name)
          @logger.info "Creating tenant..."
          tenant = @keystone.tenants.create :name        => name,
                                            :description => 'Cloud Foundry Swift Tenant'
          @logger.info "done."
          tenant
        end

        def create_user(tenant, name, password)
          @logger.info "Creating user..."
          user = @keystone.users.create :name       => name,
                                        :tenant_id  => tenant.id,
                                        :password   => password,
                                        :email      => name
          @logger.info "done."
          user
        end

        def find_user(id)
          @keystone.users.find_by_id(id)
        end

        def delete_user(id)
          @logger.info "Deleting user #{id}..."
          user = find_user(id)
          user.destroy
          @logger.info "done."
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
      end
    end
  end
end