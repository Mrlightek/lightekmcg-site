# Called by the release workflow. Temporary database credentials stay in a 0600
# file and are never printed. Cleanup can delete only the database it created.
require 'json'
require 'pg'
mode, path, run_id = ARGV
if mode == 'prepare'
  raise 'Production read context required' unless Rails.env.production?
  raise 'Invalid release run identity' unless run_id.to_s.match?(/\A\d+\z/)
  config = ActiveRecord::Base.connection_db_config.configuration_hash
  connection = config.slice(:host, :port, :password).merge(user: config[:username], dbname: 'postgres')
  name = "lightek_resort_verify_#{run_id}"
  pg = PG.connect(**connection)
  raise 'Release database already exists; refusing to reuse it' if pg.exec_params('SELECT 1 FROM pg_database WHERE datname=$1',[name]).ntuples.positive?
  pg.exec("CREATE DATABASE #{PG::Connection.quote_ident(name)}")
  data = {database: name, connection: connection, created: true}
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(JSON.generate(data)) }
  puts 'LIGHTEK_ISOLATED_DATABASE=created'
elsif mode == 'url'
  require 'uri'
  data = JSON.parse(File.read(path)); c = data.fetch('connection')
  raise 'Unsafe release database' unless data.fetch('database').match?(/\Alightek_resort_verify_\d+\z/)
  user = URI.encode_www_form_component(c.fetch('user')); password = URI.encode_www_form_component(c.fetch('password','').to_s)
  puts "postgresql://#{user}:#{password}@#{(c['host'] || 'localhost')}:#{(c['port'] || 5432)}/#{data.fetch('database')}"
elsif mode == 'cleanup'
  exit unless File.file?(path)
  data = JSON.parse(File.read(path)); name = data.fetch('database')
  raise 'Unsafe release database' unless data.fetch('created') && name.match?(/\Alightek_resort_verify_\d+\z/)
  pg = PG.connect(**data.fetch('connection').transform_keys(&:to_sym))
  pg.exec_params('SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=$1 AND pid <> pg_backend_pid()', [name])
  pg.exec("DROP DATABASE #{PG::Connection.quote_ident(name)}")
  File.delete(path)
  puts 'LIGHTEK_ISOLATED_DATABASE=removed'
else
  raise 'Unknown release database operation'
end
