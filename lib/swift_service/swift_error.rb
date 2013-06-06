# Copyright (c) 2009-2011 VMware, Inc.
module VCAP
  module Services
    module Swift
      class SwiftError < VCAP::Services::Base::Error::ServiceError
        SWIFT_SAVE_INSTANCE_FAILED        = [32100, HTTP_INTERNAL, "Could not save instance: %s"]
        SWIFT_DESTORY_INSTANCE_FAILED     = [32101, HTTP_INTERNAL, "Could not destroy instance: %s"]
        SWIFT_FIND_INSTANCE_FAILED        = [32102, HTTP_NOT_FOUND, "Could not find instance: %s"]
        SWIFT_START_INSTANCE_FAILED       = [32103, HTTP_INTERNAL, "Could not start instance: %s"]
        SWIFT_STOP_INSTANCE_FAILED        = [32104, HTTP_INTERNAL, "Could not stop instance: %s"]
        SWIFT_INVALID_PLAN                = [32105, HTTP_INTERNAL, "Invalid plan: %s"]
        SWIFT_CLEANUP_INSTANCE_FAILED     = [32106, HTTP_INTERNAL, "Could not cleanup instance, the reasons: %s"]
      end
    end
  end
end
