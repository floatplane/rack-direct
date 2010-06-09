#
# Guid - Ruby library for portable GUID/UUID generation.
#
# Copyright (c) 2004 David Garamond <davegaramond at icqmail com>
# 
# This library is free software; you can redistribute it and/or modify it
# under the same terms as Ruby itself.
#

if RUBY_PLATFORM =~ /mswin32|mingw|cygwin|bccwin32/i
  module Guid_Win32_
    require 'Win32API'
          
    PROV_RSA_FULL       = 1
    CRYPT_VERIFYCONTEXT = 0xF0000000
    FORMAT_MESSAGE_IGNORE_INSERTS  = 0x00000200
    FORMAT_MESSAGE_FROM_SYSTEM     = 0x00001000
  
    CryptAcquireContext = Win32API.new("advapi32", "CryptAcquireContext",
                                       'PPPII', 'L')
    CryptGenRandom = Win32API.new("advapi32", "CryptGenRandom", 
                                  'LIP', 'L')
    CryptReleaseContext = Win32API.new("advapi32", "CryptReleaseContext",
                                       'LI', 'L')
    GetLastError = Win32API.new("kernel32", "GetLastError", '', 'L')
    FormatMessageA = Win32API.new("kernel32", "FormatMessageA",
                                  'LPLLPLPPPPPPPP', 'L')
  
    def lastErrorMessage
      code = GetLastError.call
      msg = "\0" * 1024
      len = FormatMessageA.call(FORMAT_MESSAGE_IGNORE_INSERTS +
                                FORMAT_MESSAGE_FROM_SYSTEM, 0,
                                code, 0, msg, 1024, nil, nil,
                                nil, nil, nil, nil, nil, nil)
      msg[0, len].tr("\r", '').chomp
    end
  
    def initialize
      hProvStr = " " * 4
      if CryptAcquireContext.call(hProvStr, nil, nil, PROV_RSA_FULL,
                                  CRYPT_VERIFYCONTEXT) == 0
        raise SystemCallError, "CryptAcquireContext failed: #{lastErrorMessage}"
      end
      hProv, = hProvStr.unpack('L')
      @bytes = " " * 16
      if CryptGenRandom.call(hProv, 16, @bytes) == 0
        raise SystemCallError, "CryptGenRandom failed: #{lastErrorMessage}"
      end
      if CryptReleaseContext.call(hProv, 0) == 0
        raise SystemCallError, "CryptReleaseContext failed: #{lastErrorMessage}"
      end
    end
  end
end

module Guid_Unix_
  @@random_device = nil
  
  def initialize
    if !@@random_device
      if File.exists? "/dev/urandom"
        @@random_device = File.open "/dev/urandom", "r"
      elsif File.exists? "/dev/random"
        @@random_device = File.open "/dev/random", "r"
      else
        raise RuntimeError, "Can't find random device"
      end
    end

    @bytes = @@random_device.read(16)
  end
end
  
class Guid
  if RUBY_PLATFORM =~ /mswin32|mingw|cygwin|bccwin32/
    include Guid_Win32_
  else
    include Guid_Unix_
  end

  def hexdigest
    @bytes.unpack("h*")[0]
  end

  alias_method :to_hex , :hexdigest
  
  def to_s
    @bytes.unpack("h8 h4 h4 h4 h12").join "-"
  end
  
  def inspect
    to_s
  end
  
  def raw
    @bytes
  end
  
  def self.from_s(s)
    raise ArgumentError, "Invalid GUID hexstring" unless
      s =~ /\A[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}\z/i
    guid = Guid.allocate
    guid.instance_eval { @bytes = [s.gsub(/[^0-9a-f]+/i, '')].pack "h*" }
    guid
  end

  def self.from_raw(bytes)
    raise ArgumentError, "Invalid GUID raw bytes, length must be 16 bytes" unless
      bytes.length == 16
    guid = Guid.allocate
    guid.instance_eval { @bytes = bytes }
    guid
  end
  
  def ==(other)
    @bytes == other.raw
  end

  # ------------------------------------------------------------------------
  # jambool updates from:
  # http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/124607
  @@d36 = ('a'..'z').to_a + ('0'..'9').to_a
  @@rd36 = {}
  @@d36.each_with_index {|d, i| @@rd36[d[0]] = i}

  def Guid.from_base36(val)
    val = val.downcase
    raise ArgumentError unless val =~ /\A[a-z][a-z0-9]{24}\z/
    n = 0
    mult = 1
    val.reverse.each_byte {|c|
      n += @@rd36[c] * mult
      mult *= 36
    }
    Guid.from_i(n)
  end

  def Guid.from_hex(s)
    raise ArgumentError, "Invalid GUID hexstring" unless
      s =~ /\A[0-9a-f]{32}\z/i
    guid = Guid.allocate
    guid.instance_eval { @bytes = [s.gsub(/[^0-9a-f]+/i, '')].pack "h*" }
    guid
  end


  def Guid.from_i(val)
    bytes = [
        (val & 0xffffffff000000000000000000000000) >> 96,
        (val & 0x00000000ffffffff0000000000000000) >> 64,
        (val & 0x0000000000000000ffffffff00000000) >> 32,
        (val & 0x000000000000000000000000ffffffff)
      ].pack('NNNN')
    guid = Guid.allocate
    guid.instance_eval { @bytes = bytes }
    guid
  end

  def to_i
     (@bytes[ 0 ..  3].unpack('N')[0] << 96) +
     (@bytes[ 4 ..  7].unpack('N')[0] << 64) +
     (@bytes[ 8 .. 11].unpack('N')[0] << 32) +
     (@bytes[12 .. 15].unpack('N')[0])
  end

  def to_base36
    self.to_i.to_s(36).tr('0-9a-z', 'a-z0-9').rjust(25, 'a')
    # self.to_s.tr('0-9a-z', 'a-z0-9').rjust(25, 'a')
  end
  # ------------------------------------------------------------------------
end

if __FILE__ == $0
  require 'test/unit'
  
  class GuidTest < Test::Unit::TestCase
    def test_new
      g = Guid.new
      
      # different representations of guid: hexdigest, hex+dashes, raw bytes
      assert_equal(0, g.to_s =~ /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      assert_equal(16, g.raw.length)
      assert_equal(0, g.hexdigest =~ /\A[0-9a-f]{32}\z/)
      assert_equal(g.hexdigest, g.to_s.gsub(/-/, ''))

      # must be different each time we produce (this is just a simple test)
      g2 = Guid.new
      assert_equal(true, g != g2)
      assert_equal(true, g.to_s != g2.to_s)
      assert_equal(true, g.raw != g2.raw)
      assert_equal(true, g.hexdigest != g2.hexdigest)
      assert_equal(1000, (1..1000).select { |i| g != Guid.new }.length)
    end
    
    def test_from_s
      g = Guid.new
      g2 = Guid.from_s(g.to_s)
      assert_equal(g, g2)
    end
    
    def test_from_raw
      g = Guid.new
      g2 = Guid.from_raw(g.raw)
      assert_equal(g, g2)
    end

    def test_from_i
      g = Guid.new
      g2 = Guid.from_i(g.to_i)
      assert_equal(g, g2)
    end
    
    def test_from_base36
      g = Guid.new
      g2 = Guid.from_base36(g.to_base36)
      assert_equal(g, g2)
    end

    def test_from_hex
      g = Guid.new
      g2 = Guid.from_hex(g.to_hex)
      assert_equal(g, g2)
    end

    def test_harder
      g1 = Guid.new
      g2 = g1
      assert_equal(g1, g2)
      g1a = Guid.from_hex(Guid.from_s(Guid.from_i(g1.to_i).to_s).to_hex)
      assert_equal(g1, g1a)
      g2a = Guid.from_base36(Guid.from_i(g1.to_i).to_base36)
      assert_equal(g2, g2a)
      assert_equal(g1a, g2a)
    end
  end
end
