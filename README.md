# symmetric-encryption [![Build Status](https://secure.travis-ci.org/reidmorrison/symmetric-encryption.png?branch=master)](http://travis-ci.org/reidmorrison/symmetric-encryption) ![](http://ruby-gem-downloads-badge.herokuapp.com/symmetric-encryption?type=total)

* http://github.com/reidmorrison/symmetric-encryption

Transparently encrypt ActiveRecord, Mongoid, and MongoMapper attributes. Encrypt passwords in configuration files. Encrypt entire files at rest.

## Introduction

Any project that wants to meet PCI compliance has to ensure that the data is encrypted
whilst in flight and at rest. Amongst many other other requirements all passwords
in configuration files have to be encrypted.

Symmetric Encryption helps achieve compliance by supporting encryption of data in a simple
and consistent way.

Symmetric Encryption uses OpenSSL to encrypt and decrypt data, and can therefore
expose all the encryption algorithms supported by OpenSSL.

## Documentation

For complete documentation see: http://reidmorrison.github.io/symmetric-encryption/

## Dependencies

Symmetric Encryption works with the following Ruby interpreters:

* Ruby 1.9.3, 2.0, 2.1, 2.2, or greater
* JRuby 1.7, 9.0.0, or greater
* Rubinius 2.5, or greater

## New features in V1.1 and V2

* Ability to randomly generate a new initialization vector (iv) with every
  encryption and put the iv in the encrypted data as its header, without having
  to use SymmetricEncryption::Writer

* With file encryption randomly generate a new key and initialization vector (iv) with every
  file encryption and put the key and iv in the encrypted data as its header which
  is encrypted using the global key and iv

* Support for compression via SymmetricEncryption.encrypt, attr_encrypted and Mongoid
  fields

* SymmetricEncryption.encrypt has two additional optional parameters:
```
   random_iv [true|false]
     Whether the encypted value should use a random IV every time the
     field is encrypted.
     It is recommended to set this to true where feasible. If the encrypted
     value could be used as part of a SQL where clause, or as part
     of any lookup, then it must be false.
     Setting random_iv to true will result in a different encrypted output for
     the same input string.
     Note: Only set to true if the field will never be used as part of
       the where clause in an SQL query.
     Note: When random_iv is true it will add a 8 byte header, plus the bytes
       to store the random IV in every returned encrypted string, prior to the
       encoding if any.
     Default: false
     Highly Recommended where feasible: true

   compress [true|false]
     Whether to compress str before encryption
     Should only be used for large strings since compression overhead and
     the overhead of adding the 'magic' header may exceed any benefits of
     compression
     Note: Adds a 6 byte header prior to encoding, only if :random_iv is false
     Default: false
```

## Upgrading from earlier versions to SymmetricEncryption V3

In version 3 of SymmetricEncryption, the following changes have been made that
may have backward compatibility issues:

* SymmetricEncryption.decrypt no longer rotates through all the decryption keys
  when previous ciphers fail to decrypt the encrypted string.
  In a very small, yet significant number of cases it was possible to decrypt data
  using the incorrect key. Clearly the data returned was garbage, but it still
  returned a string of data instead of throwing an exception.
  See SymmetricEncryption.select_cipher to supply your own custom logic to
  determine the correct cipher to use when the encrypted string does not have a
  header and multiple ciphers are defined.

* Configuration file format prior to V1 is no longer supported

* New configuration option has been added to support setting encryption keys
  from environment variables

* Cipher.parse_magic_header! now returns a Struct instead of an Array

* New config options :encrypted_key and :encrypted_iv to support setting
  the encryption key in environment variables

## Versioning

This project uses [Semantic Versioning](http://semver.org/).

## Author

[Reid Morrison](https://github.com/reidmorrison)

## Contributors

* [M. Scott Ford](https://github.com/mscottford)
* [Adam St. John](https://github.com/astjohn)

## Disclaimer

Although this library has assisted in meeting PCI Compliance and has passed
previous PCI audits, it in no way guarantees that PCI Compliance will be
achieved by anyone using this library.
