
## Building

From your checkout of the [Flapjack repository](https://github.com/flpjck/flapjack):

``` bash
git checkout gh-pages
bundle
bundle exec guard
```

Guard will monitor all files (bar `_site/`) and trigger a Jekyll build on change.

View your changes at [http://localhost:9000/](http://localhost:9000/).

To manually trigger a Jekyll rebuild:

```
rake bulid
```
