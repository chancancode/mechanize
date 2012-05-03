##
# This class is used to manage the Cookies that have been returned from
# any particular website.

class Mechanize::CookieJar
  include Enumerable

  # add_cookie wants something resembling a URI.

  attr_reader :jar

  def initialize
    @jar = {}
  end

  def initialize_copy other # :nodoc:
    @jar = Marshal.load Marshal.dump other.jar
  end

  # Add a +cookie+ to the jar if it is considered acceptable from
  # +uri+.  Return nil if the cookie was not added, otherwise return
  # the cookie added.
  def add(uri, cookie)
    return nil unless cookie.acceptable_from_uri?(uri)
    add!(cookie)
    cookie
  end

  # Add a +cookie+ to the jar and return self.
  def add!(cookie)
    normal_domain = cookie.domain.downcase

    @jar[normal_domain] ||= {} unless @jar.has_key?(normal_domain)

    @jar[normal_domain][cookie.path] ||= {}
    @jar[normal_domain][cookie.path][cookie.name] = cookie

    self
  end
  alias << add!

  # Fetch the cookies that should be used for the URI object passed in.
  def cookies(url)
    cleanup
    url.path = '/' if url.path.empty?
    now = Time.now

    select { |cookie|
      !cookie.expired? && cookie.valid_for_uri?(url) && (cookie.accessed_at = now)
    }.sort_by { |cookie|
      # RFC 6265 5.4
      # Precedence: 1. longer path  2. older creation
      [-cookie.path.length, cookie.created_at]
    }
  end

  def empty?(url)
    cookies(url).length > 0 ? false : true
  end

  def each
    block_given? or return enum_for(__method__)
    cleanup
    @jar.each { |domain, paths|
      paths.each { |path, hash|
        hash.each_value { |cookie|
          yield cookie
        }
      }
    }
  end

  # Serialize and return the cookie jar using the given serializer.
  # 
  # Built-in serializers:
  # :yaml  <- YAML structure
  # :cookiestxt  <- Mozilla's cookies.txt format
  #
  # Or it could be any ruby object that respond_to dump(jar)
  def serialize(serializer = :yaml)
    if serializer == :yaml
      serializer = Mechanize::CookieJar::Serialization::YAMLCoder.new
    elsif serializer == :cookiestxt
      serializer = Mechanize::CookieJar::Serialization::CookietxtCoder.new
    end

    raise ArgumentError, "Invalid serializer #{serializer.inspect}" unless serializer.respond_to? :dump

    jar = dup
    jar.cleanup true

    serializer.dump(jar.jar)
  end

  # Deserialize a cookie jar using the given deserializer and assign it to self.
  # 
  # Built-in deserializers:
  # :yaml  <- YAML structure
  # :cookiestxt  <- Mozilla's cookies.txt format
  #
  # Or it could be any ruby object that respond_to load(serialized_jar)
  def deserialize(serialized_jar, deserializer = :yaml)
    if deserializer == :yaml
      deserializer = Mechanize::CookieJar::Serialization::YAMLCoder.new
    elsif deserializer == :cookiestxt
      deserializer = Mechanize::CookieJar::Serialization::CookietxtCoder.new
    end

    raise ArgumentError, "Invalid serializer #{serializer.inspect}" unless deserializer.respond_to? :load

    @jar = deserializer.load(serialized_jar)

    cleanup

    self
  end

  # Serialize the cookie jar using the given serializer and save it to a file.
  # 
  # Built-in serializers:
  # :yaml  <- YAML structure
  # :cookiestxt  <- Mozilla's cookies.txt format
  #
  # Or it could be any ruby object that respond_to dump(jar)
  def save_as(file, serializer = :yaml)
    open(file, 'w') do |f|
      f.write serialize(serializer)
    end

    self
  end

  # Deserialize a cookie jar from a file using the given deserializer.
  # 
  # Built-in deserializers:
  # :yaml  <- YAML structure
  # :cookiestxt  <- Mozilla's cookies.txt format
  #
  # Or it could be any ruby object that respond_to load(jar)
  def load(file, format = :yaml)
    open(file) do |f|
      deserialize(f.read, format)
    end

    self
  end

  # Clear the cookie jar
  def clear!
    @jar = {}
  end

  # Move these into CookiestxtCoder

  # Read cookies from Mozilla cookies.txt-style IO stream
  def load_cookiestxt(io)
    now = Time.now

    io.each_line do |line|
      line.chomp!
      line.gsub!(/#.+/, '')
      fields = line.split("\t")

      next if fields.length != 7

      expires_seconds = fields[4].to_i
      expires = (expires_seconds == 0) ? nil : Time.at(expires_seconds)
      next if expires and (expires < now)

      c = Mechanize::Cookie.new(fields[5], fields[6])
      c.domain = fields[0]
      c.for_domain = (fields[1] == "TRUE") # Whether this cookie is for domain
      c.path = fields[2]               # Path for which the cookie is relevant
      c.secure = (fields[3] == "TRUE") # Requires a secure connection
      c.expires = expires             # Time the cookie expires.
      c.version = 0                   # Conforms to Netscape cookie spec.

      add!(c)
    end

    @jar
  end

  # Write cookies to Mozilla cookies.txt-style IO stream
  def dump_cookiestxt(io)
    to_a.each do |cookie|
      io.puts([
        cookie.domain,
        cookie.for_domain? ? "TRUE" : "FALSE",
        cookie.path,
        cookie.secure ? "TRUE" : "FALSE",
        cookie.expires.to_i.to_s,
        cookie.name,
        cookie.value
      ].join("\t"))
    end
  end

  protected

  # Remove expired cookies
  def cleanup session = false
    @jar.each do |domain, paths|
      paths.each do |path, names|
        names.each do |cookie_name, cookie|
          paths[path].delete(cookie_name) if
            cookie.expired? or (session and cookie.session)
        end
      end
    end
  end
end

require 'mechanize/cookie_jar/serialization.rb'
require 'mechanize/cookie_jar/serialization/yaml_coder.rb'
require 'mechanize/cookie_jar/serialization/cookiestxt_coder.rb'