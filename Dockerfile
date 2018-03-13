FROM ubuntu:artful

# See: https://github.com/next-l/enju_leaf/wiki/Install

RUN apt-get update && apt-get -y install vim

RUN apt-get update --fix-missing && apt-get -y install software-properties-common
RUN add-apt-repository -y ppa:brightbox/ruby-ng
RUN apt-get install -y ruby ruby-dev \
  imagemagick libicu-dev zlib1g-dev unzip \
  autogen autoconf libtool \
  openjdk-8-jre-headless git libxslt1-dev build-essential nodejs redis-server \
  postgresql libpq-dev file cron \
  && apt-get -qq autoremove --purge -y && apt-get -qq clean  \
  && rm -rf /var/lib/apt/lists/*

#install rails
RUN gem install rails -v=4.2.10

#install enju_leaf
RUN rails _4.2.10_ new enju_leaf -d postgresql --skip-bundle \
 -m https://gist.github.com/nabeta/8024918f41242a16719796c962ed2af1.txt


WORKDIR /enju_leaf

#enju_leaf/Gemfile 以下追加
RUN echo "\ngem 'tzinfo-data'" >> Gemfile \
  && echo "gem 'foreman', '0.82.0'" >> Gemfile \
  && echo "gem 'net-ldap', '0.16.0'" >> Gemfile \
  && echo "gem 'whenever'" >> Gemfile

RUN bundle -j4 --path vendor/bundle && bundle install

ARG temp_db_host
ARG BK_REDIS=REDIS_URL

#イメージ作成時のDB情報
ENV DB_HOST=$temp_db_host
ENV DB_USERNAME=postgres
ENV DB_PASSWORD=password
ENV DB_DATABASE=enju_production
ENV RAILS_ENV=production
ENV REDIS_URL=redis://$temp_db_host/enju_leaf

RUN echo SECRET_KEY_BASE=`bundle exec rake secret` >> .env \
  && echo RAILS_SERVE_STATIC_FILES=true >> .env \
  #&& echo REDIS_URL=redis://redis/enju_leaf >> .env \
  && echo RAILS_ENV=production >> .env

#RUN ruby -v

COPY enju_leaf/config/ /enju_leaf/config/
COPY enju_leaf/db/ /enju_leaf/db/

RUN rails g enju_leaf:setup
#RUN rake assets:precompile

RUN mv config/schedule.rb config/schedule.rb.orig && \
	echo "env :PATH, ENV['PATH']" > config/schedule.rb && \
  echo "env :GEM_PATH, ENV['GEM_PATH']" > config/schedule.rb && \
	echo "env :DB_HOST, ENV['DB_HOST']" >> config/schedule.rb && \
	echo "env :DB_USERNAME, ENV['DB_USERNAME']" >> config/schedule.rb && \
	echo "env :DB_PASSWORD, ENV['DB_PASSWORD']" >> config/schedule.rb && \
	echo "env :DB_DATABASE, ENV['DB_DATABASE']" >> config/schedule.rb && \
	cat config/schedule.rb.orig >> config/schedule.rb && \
	rm config/schedule.rb.orig

RUN bundle exec whenever --update-crontab \
&& sed -i -e '1i redis: redis-server' Procfile \
&& sed -i -e "s/^\(web: bundle exec rails s\)$/\1 -b 0.0.0.0/" Procfile \
&& sed -i -e "s/^\(run Rails.application\)$/map Rails.application.config.relative_url_root || '\/' do\n  \1\nend/" config.ru

#quick_install/quick_install_generator.rb
RUN sed -i -e "s/^set :environment, :development$/set :environment, :${RAILS_ENV}/" config/schedule.rb \
    && rake enju_seed_engine:install:migrations \
    && rake enju_library_engine:install:migrations \
    && rake enju_biblio_engine:install:migrations \
    && rake enju_manifestation_viewer_engine:install:migrations

# RUN cat Gemfile
RUN rails g enju_library:setup \
    && rails g enju_biblio:setup \
    && rails g enju_circulation:setup \
    && rails g enju_subject:setup

#コンテナ稼働時のDB情報
ENV DB_HOST=db
ENV REDIS_URL=redis://redis/enju_leaf

COPY docker-entrypoint.sh ./

VOLUME ["/enju_leaf/log", "/enju_leaf/config", "/enju_leaf/bk/migrate"]
EXPOSE 3000

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["bundle", "exec", "foreman", "start"]
#CMD ["/bin/bash"]
