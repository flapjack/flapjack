
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

This will copy slate documentation from `../slate/build` if it's available.

### JSONAPI documentation

JSONAPI documentation is in a [separate repository](https://github.com/flpjck/slate).

There is a task to pull a built copy of the documentation into the Jekyll site:

``` bash
rake slate
```

This will copy slate documentation from `../slate/build` if it's available.

Calling `rake build` will also call the `slate` task.


### LiveReload

If you are using the LiveReload browser extension, Guard will reload the site in your browser when you make changes.

To set this up:

 1. [Install the LiveReload browser extension](http://feedback.livereload.com/knowledgebase/articles/86242-how-do-i-install-and-use-the-browser-extensions-)
 2. Visit the development site at [http://localhost:9000/](http://localhost:9000/).
 3. Enable the LiveReload browser extension on development site tab
 4. Reload the tab
