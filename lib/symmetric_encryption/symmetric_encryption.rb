require 'base64'
require 'openssl'
require 'zlib'
require 'yaml'
require 'erb'

# Encrypt using 256 Bit AES CBC symmetric key and initialization vector
# The symmetric key is protected using the private key below and must
# be distributed separately from the application
module SymmetricEncryption

  # Defaults
  @@cipher            = nil
  @@secondary_ciphers = []
  @@select_cipher     = nil

  # List of types supported when encrypting or decrypting data
  #
  # Each type maps to the built-in Ruby types as follows:
  #   :string    => String
  #   :integer   => Integer
  #   :float     => Float
  #   :decimal   => BigDecimal
  #   :datetime  => DateTime
  #   :time      => Time
  #   :date      => Date
  #   :json      => Uses JSON serialization, useful for hashes and arrays
  #   :yaml      => Uses YAML serialization, useful for hashes and arrays
  COERCION_TYPES      = [:string, :integer, :float, :decimal, :datetime, :time, :date, :boolean, :json, :yaml]

  # Set the Primary Symmetric Cipher to be used
  #
  # Example: For testing purposes the following test cipher can be used:
  #
  #   SymmetricEncryption.cipher = SymmetricEncryption::Cipher.new(
  #     key:    '1234567890ABCDEF1234567890ABCDEF',
  #     iv:     '1234567890ABCDEF',
  #     cipher: 'aes-128-cbc'
  #   )
  def self.cipher=(cipher)
    raise(ArgumentError, 'Cipher must respond to :encrypt and :decrypt') unless cipher.nil? || (cipher.respond_to?(:encrypt) && cipher.respond_to?(:decrypt))
    @@cipher = cipher
  end

  # Returns the Primary Symmetric Cipher being used
  # If a version is supplied
  #   Returns the primary cipher if no match was found and version == 0
  #   Returns nil if no match was found and version != 0
  def self.cipher(version = nil)
    raise(SymmetricEncryption::ConfigError, 'Call SymmetricEncryption.load! or SymmetricEncryption.cipher= prior to encrypting or decrypting data') unless @@cipher
    return @@cipher if version.nil? || (@@cipher.version == version)
    secondary_ciphers.find { |c| c.version == version } || (@@cipher if version == 0)
  end

  # Returns whether a primary cipher has been set
  def self.cipher?
    !@@cipher.nil?
  end

  # Set the Secondary Symmetric Ciphers Array to be used
  def self.secondary_ciphers=(secondary_ciphers)
    raise(ArgumentError, 'secondary_ciphers must be a collection') unless secondary_ciphers.respond_to? :each
    secondary_ciphers.each do |cipher|
      raise(ArgumentError, 'secondary_ciphers can only consist of SymmetricEncryption::Ciphers') unless cipher.respond_to?(:encrypt) && cipher.respond_to?(:decrypt)
    end
    @@secondary_ciphers = secondary_ciphers
  end

  # Returns the Primary Symmetric Cipher being used
  def self.secondary_ciphers
    @@secondary_ciphers
  end

  # AES Symmetric Decryption of supplied string
  #  Returns decrypted value
  #  Returns nil if the supplied value is nil
  #  Returns "" if it is a string and it is empty
  #
  #  Parameters
  #    str
  #      Encrypted string to decrypt
  #    version
  #      Specify which cipher version to use if no header is present on the
  #      encrypted string
  #    type [:string|:integer|:float|:decimal|:datetime|:time|:date|:boolean]
  #      If value is set to something other than :string, then the coercible gem
  #      will be use to coerce the unencrypted string value into the specified
  #      type. This assumes that the value was stored using the same type.
  #      Note: If type is set to something other than :string, it's expected
  #        that the coercible gem is available in the path.
  #      Default: :string
  #
  #  If the supplied string has an encryption header then the cipher matching
  #  the version number in the header will be used to decrypt the string
  #
  #  When no header is present in the encrypted data, a custom Block/Proc can
  #  be supplied to determine which cipher to use to decrypt the data.
  #  see #cipher_selector=
  #
  # Raises: OpenSSL::Cipher::CipherError when 'str' was not encrypted using
  # the primary key and iv
  #
  # NOTE: #decrypt will _not_ attempt to use a secondary cipher if it fails
  #       to decrypt the current string. This is because in a very small
  #       yet significant number of cases it is possible to decrypt data using
  #       the incorrect key. Clearly the data returned is garbage, but it still
  #       successfully returns a string of data
  def self.decrypt(encrypted_and_encoded_string, version=nil, type=:string)
    raise(SymmetricEncryption::ConfigError, 'Call SymmetricEncryption.load! or SymmetricEncryption.cipher= prior to encrypting or decrypting data') unless @@cipher
    return encrypted_and_encoded_string if encrypted_and_encoded_string.nil? || (encrypted_and_encoded_string == '')

    str     = encrypted_and_encoded_string.to_s

    # Decode before decrypting supplied string
    decoded = @@cipher.decode(str)
    return unless decoded
    return decoded if decoded.empty?

    decrypted =
      if header = Cipher.parse_header!(decoded)
        header.decryption_cipher.binary_decrypt(decoded, header)
      else
        # Use cipher_selector if present to decide which cipher to use
        c = @@select_cipher.nil? ? cipher(version) : @@select_cipher.call(str, decoded)
        c.binary_decrypt(decoded)
      end

    # Try to force result to UTF-8 encoding, but if it is not valid, force it back to Binary
    unless decrypted.force_encoding(SymmetricEncryption::UTF8_ENCODING).valid_encoding?
      decrypted.force_encoding(SymmetricEncryption::BINARY_ENCODING)
    end
    Coerce.coerce_from_string(decrypted, type)
  end

  # AES Symmetric Encryption of supplied string
  #  Returns result as a Base64 encoded string
  #  Returns nil if the supplied str is nil
  #  Returns "" if it is a string and it is empty
  #
  # Parameters
  #   value [Object]
  #     String to be encrypted. If str is not a string, #to_s will be called on it
  #     to convert it to a string
  #
  #   random_iv [true|false]
  #     Whether the encypted value should use a random IV every time the
  #     field is encrypted.
  #     It is recommended to set this to true where feasible. If the encrypted
  #     value could be used as part of a SQL where clause, or as part
  #     of any lookup, then it must be false.
  #     Setting random_iv to true will result in a different encrypted output for
  #     the same input string.
  #     Note: Only set to true if the field will never be used as part of
  #       the where clause in an SQL query.
  #     Note: When random_iv is true it will add a 8 byte header, plus the bytes
  #       to store the random IV in every returned encrypted string, prior to the
  #       encoding if any.
  #     Default: false
  #     Highly Recommended where feasible: true
  #
  #   compress [true|false]
  #     Whether to compress str before encryption
  #     Should only be used for large strings since compression overhead and
  #     the overhead of adding the 'magic' header may exceed any benefits of
  #     compression
  #     Note: Adds a 6 byte header prior to encoding, only if :random_iv is false
  #     Default: false
  #
  #   type [:string|:integer|:float|:decimal|:datetime|:time|:date|:boolean]
  #     Expected data type of the value to encrypt
  #     Uses the coercible gem to coerce non-string values into string values.
  #     When type is set to :string (the default), uses #to_s to convert
  #     non-string values to string values.
  #     Note: If type is set to something other than :string, it's expected that
  #       the coercible gem is available in the path.
  #     Default: :string
  def self.encrypt(str, random_iv=false, compress=false, type=:string)
    raise(SymmetricEncryption::ConfigError, 'Call SymmetricEncryption.load! or SymmetricEncryption.cipher= prior to encrypting or decrypting data') unless @@cipher

    # Encrypt and then encode the supplied string
    @@cipher.encrypt(Coerce.coerce_to_string(str, type), random_iv, compress)
  end

  # Invokes decrypt
  #  Returns decrypted String
  #  Return nil if it fails to decrypt a String
  #
  # Useful for example when decoding passwords encrypted using a key from a
  # different environment. I.e. We cannot decode production passwords
  # in the test or development environments but still need to be able to load
  # YAML config files that contain encrypted development and production passwords
  #
  # WARNING: It is possible to decrypt data using the wrong key, so the value
  #          returned should not be relied upon
  def self.try_decrypt(str)
    raise(SymmetricEncryption::ConfigError, 'Call SymmetricEncryption.load! or SymmetricEncryption.cipher= prior to encrypting or decrypting data') unless @@cipher
    begin
      decrypt(str)
    rescue OpenSSL::Cipher::CipherError, SymmetricEncryption::CipherError
      nil
    end
  end

  # Returns [true|false] as to whether the data could be decrypted
  #   Parameters:
  #     encrypted_data: Encrypted string
  #
  # WARNING: This method can only be relied upon if the encrypted data includes the
  #          symmetric encryption header. In some cases data decrypted using the
  #          wrong key will decrypt and return garbage
  def self.encrypted?(encrypted_data)
    raise(SymmetricEncryption::ConfigError, 'Call SymmetricEncryption.load! or SymmetricEncryption.cipher= prior to encrypting or decrypting data') unless @@cipher

    # For now have to decrypt it fully
    result = try_decrypt(encrypted_data)
    !(result.nil? || result == '')
  end

  # When no header is present in the encrypted data, this custom Block/Proc is
  # used to determine which cipher to use to decrypt the data.
  #
  # The Block must return a valid cipher
  #
  # Parameters
  #   encoded_str
  #     The original encoded string
  #
  #   decoded_str
  #     The string after being decoded using the global encoding
  #
  # NOTE: Do _not_ attempt to use a secondary cipher if the previous fails
  #       to decrypt due to an OpenSSL::Cipher::CipherError exception.
  #       This is because in a very small, yet significant number of cases it is
  #       possible to decrypt data using the incorrect key.
  #       Clearly the data returned is garbage, but it still successfully
  #       returns a string of data
  #
  # Example:
  #   SymmetricEncryption.select_cipher do |encoded_str, decoded_str|
  #     # Use cipher version 0 if the encoded string ends with "\n" otherwise
  #     # use the current default cipher
  #     encoded_str.end_with?("\n") ? SymmetricEncryption.cipher(0) : SymmetricEncryption.cipher
  #   end
  def self.select_cipher(&block)
    @@select_cipher = block ? block : nil
  end

  # Load the Encryption Configuration from a YAML file
  #  filename:
  #    Name of file to read.
  #        Mandatory for non-Rails apps
  #        Default: Rails.root/config/symmetric-encryption.yml
  #  environment:
  #    Which environments config to load. Usually: production, development, etc.
  #    Default: Rails.env
  def self.load!(filename=nil, environment=nil)
    Config.load!(filename, environment)
  end

  # Generate new random symmetric keys for use with this Encryption library
  #
  # Note: Only the current Encryption key settings are used
  #
  # Creates Symmetric Key .key
  #   and initialization vector .iv
  #       which is encrypted with the above Public key
  #
  # Existing key files will be renamed if present
  def self.generate_symmetric_key_files(filename=nil, environment=nil)
    config        = Config.read_config(filename, environment)

    # Only regenerating the first configured cipher
    cipher_config = config[:ciphers].first
    Cipher.generate_random_keys({environment: environment, private_rsa_key: config[:private_rsa_key]}.merge(cipher_config))
  end

  # Generate a 22 character random password
  def self.random_password
    Base64.encode64(OpenSSL::Cipher.new('aes-128-cbc').random_key)[0..-4].strip
  end

  # Binary encrypted data includes this magic header so that we can quickly
  # identify binary data versus base64 encoded data that does not have this header
  unless defined? MAGIC_HEADER
    MAGIC_HEADER        = '@EnC'
    MAGIC_HEADER_SIZE   = MAGIC_HEADER.size
    MAGIC_HEADER_UNPACK = "a#{MAGIC_HEADER_SIZE}v"
  end

  BINARY_ENCODING = Encoding.find('binary')
  UTF8_ENCODING   = Encoding.find('UTF-8')
end
