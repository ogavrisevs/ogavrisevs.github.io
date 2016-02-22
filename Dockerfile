FROM jekyll/jekyll:2.7.3

RUN apk --update add readline readline-dev libxml2 libxml2-dev libxslt  \
    libxslt-dev python zlib zlib-dev ruby ruby-dev yaml \
    yaml-dev libffi libffi-dev build-base nodejs ruby-io-console \
    ruby ruby-irb ruby-rake ruby-bigdecimal libstdc++ tzdata \
    libc-dev linux-headers openssl-dev libxml2-dev libxslt-dev

ADD . /srv/jekyll

RUN bundle install

ENTRYPOINT jekyll serve -w --force_polling -V
