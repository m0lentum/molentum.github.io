serve:
  zola serve --drafts

tex:
  fd source.md | entr -p node renderKatex.js /_

with-tex:
  just serve &
  just tex

build:
  zola build

# push build results to the `pages` branch after building
publish: build
  git rm -r "[!.git]*"
  # LFS file storage doesn't work with the new git-pages server,
  # remove .gitattributes to push images as regular git objects
  git rm .gitattributes
  mv public/** ./
  echo "molentum.me" > .domains
  echo "molentum.codeberg.page" >> .domains
  git add -A
  git commit -m "publish"
  git push origin HEAD:pages --force
  git reset --hard HEAD~1
  rm -r assets/
