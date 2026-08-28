require "test_helper"

class SolidCacheConfigTest < ActiveSupport::TestCase
  test "config/cache.yml exists and configures development and production" do
    cache_config = Rails.root.join("config/cache.yml")
    assert cache_config.exist?, "config/cache.yml is missing"

    yaml = YAML.safe_load(cache_config.read, aliases: true)

    assert yaml["development"].key?("store_options"), "development cache config is missing store_options"
    assert yaml["production"].key?("store_options"), "production cache config is missing store_options"
    assert_equal "cache", yaml["production"]["database"], "production cache database should be :cache"
  end

  test "db/cache_schema.rb exists and defines solid_cache_entries" do
    schema = Rails.root.join("db/cache_schema.rb")
    assert schema.exist?, "db/cache_schema.rb is missing"
    assert_match(/create_table "solid_cache_entries"/, schema.read)
  end

  test "db/cache_migrate contains the initial Solid Cache migration" do
    migration_dir = Rails.root.join("db/cache_migrate")
    assert migration_dir.directory?, "db/cache_migrate directory is missing"
    migration_files = migration_dir.children.select(&:file?)
    assert migration_files.any?, "db/cache_migrate has no migration files"
  end

  test "config/database.yml defines a :cache database for development and production" do
    database_config = YAML.safe_load(Rails.root.join("config/database.yml").read, aliases: true)

    assert database_config["development"].key?("cache"), "development database config is missing :cache"
    assert_equal "db/cache_migrate", database_config["development"]["cache"]["migrations_paths"]

    assert database_config["production"].key?("cache"), "production database config is missing :cache"
    assert_equal "db/cache_migrate", database_config["production"]["cache"]["migrations_paths"]
  end

  test "development and production environments configure solid cache store" do
    dev_config = Rails.root.join("config/environments/development.rb").read
    prod_config = Rails.root.join("config/environments/production.rb").read

    assert_match(/config\.cache_store\s*=\s*:solid_cache_store/, dev_config,
      "development.rb should set config.cache_store to :solid_cache_store")
    assert_match(/config\.cache_store\s*=\s*:solid_cache_store/, prod_config,
      "production.rb should set config.cache_store to :solid_cache_store")
  end
end
