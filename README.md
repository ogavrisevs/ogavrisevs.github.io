
About
-----

This repo contains private blog [ogavrisevs.github.io](http://ogavrisevs.github.io/) source code. Blog runs on Jekyll engine and serves in GitHub Pages.

Run local with (Native Docker on mac) :
---------------  

    docker run --rm --entrypoint=/bin/sh --volume=$(pwd):/srv/jekyll -it -p 4000:4000 jekyll/jekyll:3.1.3

    bundle install

    bundle exec jekyll serve -w --force_polling -V


Ref:

  [Pygments lexers](http://pygments.org/docs/lexers/)

  [Poole](https://github.com/poole/poole)
