
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
rake build
```

### LiveReload

If you are using the LiveReload browser extension, Guard will reload the site in your browser when you make changes.

To set this up:

 # [Install the LiveReload browser extension](http://feedback.livereload.com/knowledgebase/articles/86242-how-do-i-install-and-use-the-browser-extensions-)
 # Visit the development site at [http://localhost:9000/](http://localhost:9000/).
 # Enable the LiveReload browser extension on development site tab
 # Reload the tab
