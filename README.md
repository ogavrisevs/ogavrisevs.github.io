
Run local with
---------------  

```
docker-machine create -d virtualbox dev

eval $(docker-machine env dev)

docker run --rm --entrypoint=/bin/sh --volume=$(pwd):/srv/jekyll -it -p 4000:4000 jekyll/jekyll:pages

jekyll serve -w --force_polling -V
```
