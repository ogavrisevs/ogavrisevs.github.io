
Run local with
---------------  

```
docker run --rm --entrypoint=/bin/sh --volume=$(pwd):/srv/jekyll -it -p 4000:4000 jekyll/jekyll:2.5.3

jekyll serve -w --force_polling -V
```
