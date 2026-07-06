require './src/app'
namespace :db do
  desc "Run migrations"
  task :migrate, [:version] do |t, args|
    puts args, App.db_url
    require "sequel/core"
    Sequel.extension :migration
    version = args[:version].to_i if args[:version]
    puts version
    Sequel.connect(App.db_url) do |db|
      db.extension :pg_enum
      Sequel::Migrator.run(db, "src/migrations", target: version)
    end
  end

  desc "Seed the database with demo data"
  task :seed do
    App.load!
    require './scripts/seed'
  end
end


require 'optparse'


namespace :create do
  desc "Creates Model"
  task :models do #|t, args|
    models = []
    OptionParser.new do |opts|
      puts opts
      opts.banner = "Usage: rake create:models [options]"
      opts.on("-n", "--names ARG", String) { |str| models += str.split(',') }

    end.parse!
    puts models
    exit
  end
end


# DATABASE_URL="postgres://doqhgpwk:faHZB60XTVMZTczxkznkvXC0rcHxyap6@rogue.db.elephantsql.com:5432/doqhgpwk" rake db:migrate\[0\]


# DATABASE_URL="postgres://exbkkjhk:teWF4qtJwyLZMXLm0CDM1eiYfNC-xr_T@satao.db.elephantsql.com:5432/exbkkjhk" rake db:migrate\[7\]
# DATABASE_URL="postgres://lnhtywgf:qfdIK2eJVhJlES3jAsyU4wZAxx1ESzfi@balarama.db.elephantsql.com:5432/lnhtywgf" rake db:migrate