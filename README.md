publish-to-git
==============

[GitHub Action](https://github.com/features/actions) for publishing a directory
and its contents to another git repository.

This can be especially useful for publishing static website, such as with
[GitHub Pages](https://pages.github.com/), from built files in other job
steps, such as [Doxygen](http://www.doxygen.nl/) generated HTML files.

See [action.yml](https://github.com/potatoengine/ghactions/blob/master/publish-to-git/action.yml)
for a complete list of inputs and outputs.

License
-------

MIT License, see [LICENSE](https://github.com/potatoengine/ghactions/blob/master/publish-to-git//LICENSE)
for details.

Usage Example
-------------

```
jobs:
  publish:
    - uses: actions/checkout@master
    - run: sh scripts/build-doxygen-html.sh --out static/html
    - uses: potatoengine/ghactions/publish-to-git@master
      with:
        branch: gh-pages
        github_token: '${{ secrets.GITHUB_TOKEN  }}'
        github_pat: '${{ secrets.GH_PAT }}'
        source_folder: static/html
      if: success() && github.event == 'push'
```