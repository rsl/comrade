require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Comrade
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    # The house zone: date displays and the archive page's Today/Yesterday
    # buckets read in this zone. Hardcoded for now — when comrade grows an
    # operator config, this becomes COMRADE_TIME_ZONE (env) or an in-app
    # setting; until then UTC would misbucket evening conversations.
    config.time_zone = 'Eastern Time (US & Canada)'
    # config.eager_load_paths << Rails.root.join("extras")

    # Postgres-backed job queue (production override lives in production.rb).
    config.active_job.queue_adapter = :good_job
  end
end
