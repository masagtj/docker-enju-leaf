#!/bin/bash

set -e

# DB aka Database
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_HOST_PORT="${DB_HOST_PORT:-5432}"
DB_DATABASE="${DB_DATABASE:-enju_production}"
DB_USERNAME="${DB_USERNAME:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-password}"
DB_ROOT_USER="${DB_ROOT_USER:-postgres}"
DB_ROOT_PASS="${DB_ROOT_PASS:-$(echo $DB_PASS)}"

bootstrappingEnvironment() {
    echo "=== Begin Bootstrap Phase ==="
    operateDBMigrations
    waitingForDatabase
    settingMailer
    settingLdap
    bootstrapEnju-Leaf
    echo "=== End Bootstrap Phase ==="
}

waitingForDatabase() {
    export PGPASSWORD="$DB_PASSWORD"
    local TIMEOUT=60
    echo "Waiting for database server to allow connections ..."
    while ! /usr/bin/pg_isready -h "$DB_HOST" -p "$DB_HOST_PORT" -U "$DB_USERNAME" -t 1 >/dev/null 2>&1
    do
        TIMEOUT=$(expr $TIMEOUT - 1)
        if [[ $TIMEOUT -eq 0 ]]; then
            echo "Could not connect to database server. Exiting."
            unset PGPASSWORD
            exit 1
        fi
        echo -n "."
        sleep 1
    done
    unset PGPASSWORD
}

isDbEmpty(){
  export PGPASSWORD="$DB_PASSWORD"
  result=`psql -t -U $DB_USERNAME -d $DB_DATABASE -h $DB_HOST  << _EOF
    SELECT NOT EXISTS (SELECT * FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema'));
_EOF`
  unset PGPASSWORD
  test $result = "t"
  echo $?
}

operateDBMigrations(){
  #初回起動時に利用したMigrationファイルを使用するため。
  #バージョンが上って処理が何か必要な時はその時考える
  local MIGCOUNT=$(ls -1 /enju_leaf/bk/migrate | wc -l)
  if [ $MIGCOUNT -eq '0' ]; then
    echo "migrations not exist"
    cp -r /enju_leaf/db/migrate/* /enju_leaf/bk/migrate/
  else
    echo "migrations exist"
    rm /enju_leaf/db/migrate/*
    cp -r /enju_leaf/bk/migrate/* /enju_leaf/db/migrate/
  fi
}

ENJU_HOST="${ENJU_HOST:-localhost:3000}"

MAILER=$(cat << EOS
  config.action_mailer.delivery_method = $MAILER_DELIVERY_METHOD
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    :address => ENV['MAILER_ADDRESS'],
    :port => ENV['MAILER_PORT'],
    :domain => ENV['MAILER_DOMAIN'],
    :authentication => ENV['MAILER_AUTH'],
    :user_name => ENV['MAILER_USERNAME'],
    :password => ENV['MAILER_PASSWORD'],
    :enable_starttls_auto => ENV['MAILER_TLS'],
  }
EOS
)

settingMailer(){

  if [ ! -e config/environments/$RAILS_ENV.rb.org ]; then
    mkdir -p /enju_leaf/bk/config/environments
    cp -f config/environments/$RAILS_ENV.rb /enju_leaf/bk/config/environments/$RAILS_ENV.rb.org
    mkdir -p /enju_leaf/bk/config/initializers
    cp -f config/initializers/devise.rb /enju_leaf/bk/config/initializers/devise.rb
  fi

  if [ ! -z "$MAILER_DELIVERY_METHOD" ]; then
    echo "mail setting"
    cp -f /enju_leaf/bk/config/environments/$RAILS_ENV.rb.org config/environments/$RAILS_ENV.rb
    sed -i -e "s/\(config.action_mailer.default_url_options = {host: \).*/\1'$ENJU_HOST'}/" config/environments/$RAILS_ENV.rb

    echo "$MAILER" | sed -i "/config.action_mailer.default_url_options/r /dev/stdin" config/environments/$RAILS_ENV.rb
    #cat config/environments/$RAILS_ENV.rb

    sed -i -e "s/\(config.mailer_sender = \).*/\1'$MAILER_SENDER'/" config/initializers/devise.rb
    #cat config/initializers/devise.rb
  fi

}

LDAP_STRATEGY=$(cat << EOS

  # devise/strategies/authenticatable ldap_authenticatable
  config.warden do |manager|
    manager.default_strategies(:scope => :user).unshift :ldap_authenticatable
  end
EOS
)

settingLdap(){
  if [ ! -z "$LDAP_HOST" ]; then
    echo "Setup LDAP authentication..."

    # LDAP_COUNT=$(grep -c 'ldap_authenticatable' config/initializers/devise.rb)
    # if [ $LDAP_COUNT -eq '0' ]; then
      LDAP_DEVISEEND=$(grep -e "^end$" -n config/initializers/devise.rb | sed -e 's/:.*//g')
      LDAP_INTARGET=`expr $LDAP_DEVISEEND - 1`
      echo "$LDAP_STRATEGY" | sed -i "${LDAP_INTARGET}r /dev/stdin" config/initializers/devise.rb
    # else
    #   echo "Already added LDAP_STRATEGY..."
    # fi
  fi
}

bootstrapEnju-Leaf() {
  echo "Start Enju-Leaf init process."

  echo "Checking if database is empty..."
  IS_DB_EMPTY=$(isDbEmpty)
  if [ $IS_DB_EMPTY = "0" ]; then
    echo "Database is empty."
  fi

  echo "Running database migration..."
  rake db:migrate

  if [ $IS_DB_EMPTY = "0" ]; then
    echo "Inserting initial data..."
    rake enju_leaf:setup
    rake enju_circulation:setup
    rake enju_subject:setup
    rake db:seed
  fi

  echo "Precompile assets..."
  rake assets:precompile

  echo "Upgrading database..."
  rake enju_leaf:upgrade

  if [ -z "$ENJU_SKIP_SOLR" ]; then
    echo "Re-indexing..."

    rake sunspot:solr:start
    sleep 5
    rake sunspot:reindex
    rake sunspot:solr:stop
  fi

  echo "Enju-Leaf init process completed; ready for start up."
}

if [ "$1" = "bundle" ]; then
bootstrappingEnvironment
fi

exec "$@"
