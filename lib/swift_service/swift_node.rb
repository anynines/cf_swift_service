# Copyright (c) 2009-2011 VMware, Inc.
require "fileutils"
require "logger"
require "data_mapper"
require "uuidtools"

module VCAP
  module Services
    module Swift
      class Node < VCAP::Services::Base::Node
      end
    end
  end
end

require "swift_service/common"
require "swift_service/swift_error"
require "swift_service/identity"
require "swift_service/storage"


#TODO Error case - Swift endpoint is not available
#TODO Error case - User creation fails during provision (tenant then exists)
class VCAP::Services::Swift::Node

  include VCAP::Services::Swift::Common
  include VCAP::Services::Swift

  class ProvisionedService
    include DataMapper::Resource
    property :name,         String,   :key => true
    property :tenant_id,    String
    property :tenant_name,  Text
    property :account_meta_key, String
  end

  def initialize(options)
    super(options)

    @local_db = options[:local_db]
    @port     = options[:port]
    @base_dir = options[:base_dir]
    @supported_versions = options[:supported_versions]

    # load fog_options from the config files
    @fog_options  = load_fog_options(options[:fog_config_file])

    @identity     = VCAP::Services::Swift::Identity.new(options[:logger], @fog_options[:identity])
  end

  # When the node is started it calculated
  # its capacity.
  # The swift service actually does not have a capacity itself
  # as the capacity is determined by OpenStack Swift not this
  # node implementation.
  def pre_send_announcement
    super
    FileUtils.mkdir_p(@base_dir) if @base_dir
    start_db
    @capacity_lock.synchronize do
      ProvisionedService.all.each do |instance|
        @capacity -= capacity_unit
      end
    end
  end

  def announcement
    @capacity_lock.synchronize do
      { :available_capacity => @capacity,
        :capacity_unit => capacity_unit }
    end
  end

  def provision(plan, credential = nil, version=nil)    
    @logger.info("Provisioning plan: #{plan}, credential: #{credential.inspect}, version: #{version}")      
    instance = build_instance_from_scratch
       
    begin
      save_instance(instance)
    rescue => e1
      @logger.error("Could not save instance: #{instance.name}, cleanning up")
      begin
        destroy_instance(instance)
      rescue => e2
        @logger.error("Could not clean up instance: #{instance.name}")
      end
      raise e1
    end

    gen_credential(instance)
  end

  def unprovision(name, credentials = [])
    return if name.nil?
    @logger.debug("Unprovision swift service: #{name} with credentials #{credentials.inspect}")
    instance = get_instance(name)
    destroy_instance(instance)
    true
  end

  def bind(name, binding_options, credential = nil)
    instance = get_instance(name)
    gen_credential(instance)
  end

  def unbind(credential)
    @logger.debug("Unbind service: #{credential.inspect}")
    @identity.delete_user(credential["user_id"])
    true
  end

  def start_db
    DataMapper.setup(:default, @local_db)
    DataMapper::auto_upgrade!
  end

  # An instance contains a tenant.
  # This function creates a tenant for the instance, sets the account_meta_key and saves it.
  def save_instance(instance)
    begin
      @logger.info("Saving instance #{instance.name}...")
      fog_options                 = @fog_options[:storage]
      tenant                      = @identity.create_tenant(instance.tenant_name)
      instance.tenant_id          = tenant.id
      fog_options[:hp_tenant_id]  = tenant.id

      cf_service_admin_user       = @identity.find_user(@identity.keystone.current_user["id"])

      account_meta_key            = generate_password
      instance.account_meta_key   = account_meta_key
    # Don't eat up error messages and provide a backtrace (workaround for flaws in the base class).
    rescue StandardError => e
      @logger.error "An error occured: #{e.class.name}: #{e.message}\n#{e.backtrace}"
      raise e
    end

    raise SwiftError.new(SwiftError::SWIFT_SAVE_INSTANCE_FAILED, instance.inspect) unless instance.save
    instance
  end

  # When destroying an instance, the instance's tenant and the tenant's users are completely deleted.
  def destroy_instance(instance)
    fog_options                 = @fog_options[:storage]

    # FIXME: For some reasons the admin user is not allowed to delete a swift account.
    # As a workaround we create a temporary user to delete the swift account and then
    # delete all users (incl. the newly created one).
    tenant  = @identity.find_tenant(instance.tenant_id)
    user_hash    = create_user_with_swiftoperator_role(tenant)
    user = user_hash[:user]
    username = user_hash[:username]
    password = user_hash[:password]

    fog_options[:hp_tenant_id]    = instance.tenant_id
    fog_options[:hp_access_key]   = username
    fog_options[:hp_secret_key]   = password
    storage                       = VCAP::Services::Swift::Storage.new(@logger, fog_options)

    storage.delete_account

    @logger.debug "Account meta data (should be 'Recently deleted'): " + storage.get_account_meta_data.body.to_s

    @identity.delete_users_by_tenant_id(instance.tenant_id, @fog_options[:name_suffix])
    @identity.delete_tenant(instance.tenant_id)
    raise SwiftError.new(SwiftError::SWIFT_DESTROY_INSTANCE_FAILED, instance.inspect) unless instance.destroy
  end

  def get_instance(name)
    instance = ProvisionedService.get(name)
    raise SwiftError.new(SwiftError::SWIFT_FIND_INSTANCE_FAILED, name) if instance.nil?
    instance
  end

  def gen_credential(instance)
    tenant      = @identity.find_tenant(instance.tenant_id)        
    user_hash        = create_user_with_swiftoperator_role(tenant)
    user = user_hash[:user]
    username = user_hash[:username]
    password = user_hash[:password]
    
    credentials = {
      "name"                    => instance.name,
      "authentication_uri"      => @fog_options[:storage][:hp_auth_uri],
      "user_name"               => username,
      "user_id"                 => user.id,
      "password"                => password,
      "tenant_name"             => tenant.name,
      "tenant_id"               => tenant.id,
      "availability_zone"       => @fog_options[:storage][:hp_avl_zone] || "nova",
      "authentication_version"  => @fog_options[:storage][:hp_auth_version],
      "account_meta_key"        => instance.account_meta_key,
      "self_signed_ssl"         => @fog_options[:storage][:self_signed_ssl] || false
      "service_type"            => @fog_options[:storage][:hp_service_type],
    }

    storage                     = VCAP::Services::Swift::Storage.new(@logger, fog_credentials_from_cf_swift_credentials(credentials))
    storage.set_account_meta_key(instance.account_meta_key)

    credentials
  end

  protected

  def create_user_with_swiftoperator_role(tenant)
    username    = "#{UUIDTools::UUID.random_create.to_s}.swift.user@#{@fog_options[:name_suffix]}"
    password  = generate_password
    user      = @identity.create_user(tenant, username, password)
    
    @identity.assign_role_to_user_for_tenant(@fog_options[:swift_operator_role_id], user, tenant)
    result_hash = {}
    result_hash[:username] = username
    result_hash[:password] = password
    result_hash[:user] = user
    result_hash
  end

  def fog_credentials_from_cf_swift_credentials(cf_swift_credentials)
    {
           :provider => 'HP',
           :hp_access_key => cf_swift_credentials["user_name"],
           :hp_secret_key => cf_swift_credentials["password"],
           :hp_tenant_id => cf_swift_credentials["tenant_id"],
           :hp_auth_uri =>  cf_swift_credentials["authentication_uri"],
           :hp_use_upass_auth_style => true,
           :hp_avl_zone => cf_swift_credentials["availability_zone"],
           :hp_auth_version => cf_swift_credentials["authentication_version"].to_sym,
           :self_signed_ssl => cf_swift_credentials["self_signed_ssl"]
           :hp_service_type => cf_swift_credentials["service_type"]
    }
  end

  def build_instance_from_scratch
    instance = ProvisionedService.new
    instance.name = UUIDTools::UUID.random_create.to_s
    instance.tenant_name  = "#{instance.name}.swift.tenant@#{@fog_options[:name_suffix]}"
    instance
  end

  def generate_password(length = 20)
    ([nil]*length).map { ((48..57).to_a+(65..90).to_a+(97..122).to_a).sample.chr }.join
  end

  def load_fog_options(fog_config_file)
    fog_options = nil
    file_path   = fog_config_file ||= File.join(File.dirname(File.expand_path(__FILE__)), "..", "..", "config", "fog.yml")
    if File.exists?(file_path) then
      fog_options = YAML::load(File.open(file_path))
    else
      @logger.fatal("Fog configuration not found. Should be at: #{file_path}")
    end
    fog_options
  end
end
