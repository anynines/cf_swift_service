# Copyright (c) 2009-2011 VMware, Inc.
require "fileutils"
require "logger"
require "datamapper"
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

#TODO Error case - Swift endpoint is not available
#TODO Error case - User creation fails during provision (tenant then exists)
#TODO Role assignment tenant, user, swiftoperator
class VCAP::Services::Swift::Node

  include VCAP::Services::Swift::Common
  include VCAP::Services::Swift

  class ProvisionedService
    include DataMapper::Resource
    property :name,         String,   :key => true
    property :tenant_id,    String
    property :tenant_name,  Text  
  end
  
  def initialize(options)
    super(options)

    @local_db = options[:local_db]
    @port = options[:port]
    @base_dir = options[:base_dir]
    @supported_versions = options[:supported_versions]
    
    @fog_options = load_fog_options
    @identity = VCAP::Services::Swift::Identity.new(options[:logger], @fog_options)    
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
    @logger.debug("Unprovision swift service: #{name}")
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
  
  def save_instance(instance)          
    @logger.info("Saving instance #{instance.name}...")      
    tenant = @identity.create_tenant(instance.tenant_name)      
    instance.tenant_id = tenant.id
    
    raise SwiftError.new(SwiftError::SWIFT_SAVE_INSTANCE_FAILED, instance.inspect) unless instance.save
    instance
  end

  def destroy_instance(instance)
    @identity.delete_tenant(instance.tenant_id)
    raise SwiftError.new(SwiftError::SWIFT_DESTROY_INSTANCE_FAILED, instance.inspect) unless instance.destroy
  end

  def get_instance(name)
    instance = ProvisionedService.get(name)
    raise SwiftError.new(SwiftError::SWIFT_FIND_INSTANCE_FAILED, name) if instance.nil?
    instance
  end

  def gen_credential(instance)
    tenant    = @identity.find_tenant(instance.tenant_id)    
    username  = "#{UUIDTools::UUID.random_create.to_s}.swift.user@#{@fog_options[:name_suffix]}"
    user      = @identity.create_user(tenant, username, generate_password)    
    swift_operator_role = @identity.find_role(@fog_options[:swift_operator_role_id])
    swift_operator_role.add_to_user(user, tenant)
    
    credential = {
      "name"                    => instance.name,
      "authentication_uri"      => @fog_options[:storage][:hp_auth_uri],
      "user_name"               => user.name,
      "user_id"                 => user.id,
      "password"                => user.password,
      "tenant_name"             => tenant.name,
      "tenant_id"               => tenant.id,
      "availability_zone"       => @fog_options[:storage][:hp_avl_zone],
      "authentication_version"  => @fog_options[:storage][:hp_auth_version]
    }
  end
  
  protected
  
  def build_instance_from_scratch
    instance = ProvisionedService.new
    instance.name = UUIDTools::UUID.random_create.to_s
    instance.tenant_name  = "#{instance.name}.swift.tenant@#{@fog_options[:name_suffix]}"
    instance
  end
  
  def generate_password(length = 20)
    ([nil]*length).map { ((48..57).to_a+(65..90).to_a+(97..122).to_a).sample.chr }.join
  end
  
  def load_fog_options
    fog_options = nil
    file_path   = File.join(File.dirname(File.expand_path(__FILE__)), "..", "..", "config", "fog.yml")
    if File.exists?(file_path) then
      fog_options = YAML::load(File.open(file_path))
    else
      @logger.fatal("Fog configuration not found. Should be at: #{file_path}")
    end
    fog_options
  end
end
