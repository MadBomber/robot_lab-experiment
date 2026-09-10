# Backport of rails/rails 8-1-stable ActiveSupport::JSON.decode for json 3.x,
# where JSON.parse options are keyword-only (activesupport 8.1.3.1 still passes
# a positional hash and raises ArgumentError). Delete this file — and loosen
# nothing else — once the app is on a Rails release newer than 8.1.3.1; the
# version guard below makes it a no-op there anyway.
if Rails.gem_version <= Gem::Version.new("8.1.3.1") &&
   Gem::Version.new(JSON::VERSION) >= Gem::Version.new("3.0.0")
  module ActiveSupport
    module JSON
      class << self
        def decode(json, options = nil)
          data = if options
                   ::JSON.parse(json, **options)
                 else
                   ::JSON.parse(json)
                 end

          if ActiveSupport.parse_json_times
            convert_dates_from(data)
          else
            data
          end
        end
        alias load decode
      end
    end
  end
end
