
About
-----

This repo contains private blog [ogavrisevs.github.io](http://ogavrisevs.github.io/) source code. Blog runs on Jekyll engine and serves in GitHub Pages. 

Run local with: 
---------------  

```
docker-machine create -d virtualbox dev

eval $(docker-machine env dev)

docker run --rm --entrypoint=/bin/sh --volume=$(pwd):/srv/jekyll -it -p 4000:4000 jekyll/jekyll:pages

jekyll serve -w --force_polling -V
```

Ref: 

[Pygments lexers](http://pygments.org/docs/lexers/)