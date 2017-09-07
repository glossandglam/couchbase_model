class CouchbaseModel
  module Core
    module Encrypt
      def self.included(base)
        base.extend(ClassMethods)
      end
      
      module ClassMethods
        def encrypt_value_for(attr, value)
          options = attributes(false)[attr.to_sym]
          options[:encrypt] ? CouchbaseModel::Core::Encrypt.hash_attribute(value, options[:encrypt]) : value
        end
      end
      
      def self.hash_attribute(value, alg = true, opts = {})
        return value if opts[:is_encrypted]
        return value if value.nil?
        
        value = value.is_a?(CouchbaseModel) ? value.id : value
        case alg
        when :md5
          Digest::MD5.hexdigest value.to_s
        when :sha256
          Digest::SHA256.hexdigest value.to_s
        when :sha1
          Digest::SHA1.hexdigest value.to_s
        else
          Digest::SHA256.hexdigest value.to_s
        end
      end

    end
  end
end