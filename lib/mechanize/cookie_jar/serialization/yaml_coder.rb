class Mechanize::CookieJar::Serialization::YAMLCoder
  def initialize
    load_yaml
  end

  def dump(jar)
    YAML.dump(jar)
  end

  def load(serialized_jar)
    YAML.load(serialized_jar)
  end

  private

  def load_yaml # :nodoc:
    begin
      require 'psych'
    rescue LoadError
    end

    require 'yaml'
  end
end