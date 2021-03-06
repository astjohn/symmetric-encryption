# Used for compression
require 'zlib'
# Used to coerce data types between string and their actual types
require 'coercible'

require 'symmetric_encryption/version'
require 'symmetric_encryption/cipher'
require 'symmetric_encryption/symmetric_encryption'
require 'symmetric_encryption/exception'

module SymmetricEncryption
  autoload :Coerce,    'symmetric_encryption/coerce'
  autoload :Config,    'symmetric_encryption/config'
  autoload :Reader,    'symmetric_encryption/reader'
  autoload :Writer,    'symmetric_encryption/writer'
  autoload :Generator, 'symmetric_encryption/generator'
end

# Add support for other libraries only if they have already been loaded
require 'symmetric_encryption/railtie' if defined?(Rails)
if defined?(ActiveRecord::Base) && !defined?(AttrEncrypted::Version)
  require 'symmetric_encryption/extensions/active_record/base'
end
require 'symmetric_encryption/railties/symmetric_encryption_validator' if defined?(ActiveModel)
require 'symmetric_encryption/extensions/mongoid/encrypted' if defined?(Mongoid)
require 'symmetric_encryption/extensions/mongo_mapper/plugins/encrypted_key' if defined?(MongoMapper)
