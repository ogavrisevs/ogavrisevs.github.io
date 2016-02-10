FROM jekyll/jekyll:2.7.3

RUN apk --update add readline readline-dev libxml2 libxml2-dev libxslt  \
    libxslt-dev python zlib zlib-dev ruby ruby-dev yaml \
    yaml-dev libffi libffi-dev build-base nodejs ruby-io-console \
    ruby ruby-irb ruby-rake ruby-bigdecimal libstdc++ tzdata \
    libc-dev linux-headers openssl-dev libxml2-dev libxslt-dev


    apk update && apk upgrade && apk --update add \
        ruby ruby-irb ruby-rake ruby-io-console ruby-bigdecimal \
        libstdc++ tzdata

    gem install bundler --no-ri --no-rdoc \
        && rm -r /root/.gem \
        && find / -name '*.gem' | xargs rm

    apk --update add --virtual build_deps \
        build-base ruby-dev libc-dev linux-headers \
        openssl-dev postgresql-dev libxml2-dev libxslt-dev && \
        sudo -iu app bundle config build.nokogiri --use-system-libraries && \
        sudo -iu app bundle install --path vendor/bundle && \
        apk del  build_deps

ADD . /srv/jekyll

RUN bundle install

ENTRYPOINT jekyll serve -w --force_polling -V
